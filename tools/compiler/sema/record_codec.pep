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
        LoopBreak(p0, p1, p2, p3) => {
            out.unsigned(8);
            out.flag(p0);
            out.text(p1);
            out.unsigned(out.blank_locs ? 0 : p2.start);
            out.unsigned(out.blank_locs ? 0 : p2.end);
            out.unsigned(out.blank_locs ? 0 : p3.start);
            out.unsigned(out.blank_locs ? 0 : p3.end);
        }
        Labeled(p0, p1, p2, p3) => {
            out.unsigned(9);
            out.text(p0);
            out.unsigned(out.blank_locs ? 0 : p1.start);
            out.unsigned(out.blank_locs ? 0 : p1.end);
            _a_Statement_write(out, p2);
            out.unsigned(out.blank_locs ? 0 : p3.start);
            out.unsigned(out.blank_locs ? 0 : p3.end);
        }
        Destructure(p0, p1, p2, p3) => {
            out.unsigned(10);
            out.unsigned(p0.count);
            for (var _item584 in p0) {
                _a_DestructureBinding_write(out, _item584);
            }
            _a_Expression_write(out, p1);
            out.flag(p2);
            out.unsigned(out.blank_locs ? 0 : p3.start);
            out.unsigned(out.blank_locs ? 0 : p3.end);
        }
        Match(p0) => {
            out.unsigned(11);
            _a_Match_write(out, p0);
        }
        Static(p0) => {
            out.unsigned(12);
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
        var _f573 = input.text();
        var _s574 = input.unsigned();
        var _f575 = ast.Span(_s574, input.unsigned());
        var _s576 = input.unsigned();
        var _f577 = ast.Span(_s576, input.unsigned());
        return ast.Statement.LoopBreak(_f572, _f573, _f575, _f577);
    }
    if (tag == 9) {
        var _f578 = input.text();
        var _s579 = input.unsigned();
        var _f580 = ast.Span(_s579, input.unsigned());
        var _f581 = _a_Statement_read(input);
        var _s582 = input.unsigned();
        var _f583 = ast.Span(_s582, input.unsigned());
        return ast.Statement.Labeled(_f578, _f580, _f581, _f583);
    }
    if (tag == 10) {
        var _v585 = Array<ast.DestructureBinding>();
        var _n586 = input.count();
        for (var _ in 0.._n586) {
            _v585.append(_a_DestructureBinding_read(input));
        }
        var _f587 = _v585;
        var _f588 = _a_Expression_read(input);
        var _f589 = input.flag();
        var _s590 = input.unsigned();
        var _f591 = ast.Span(_s590, input.unsigned());
        return ast.Statement.Destructure(_f587, _f588, _f589, _f591);
    }
    if (tag == 11) {
        var _f592 = _a_Match_read(input);
        return ast.Statement.Match(_f592);
    }
    if (tag == 12) {
        var _f593 = _a_StaticBlock_read(input);
        return ast.Statement.Static(_f593);
    }
    input.fail("Statement", tag);
    return _a_Statement_read(input);
}

_a_StaticBlock_write(out: RecordOut, value: ast.StaticBlock) {
    out.unsigned(value.captures.count);
    for (var _item594 in value.captures) {
        _a_Label_write(out, _item594);
    }
    out.unsigned(value.written_captures.count);
    for (var _item595 in value.written_captures) {
        _a_Expression_write(out, _item595);
    }
    _a_Block_write(out, value.block);
    out.unsigned(out.blank_locs ? 0 : value.keyword_span.start);
    out.unsigned(out.blank_locs ? 0 : value.keyword_span.end);
    out.unsigned(out.blank_locs ? 0 : value.span.start);
    out.unsigned(out.blank_locs ? 0 : value.span.end);
    out.unsigned(value.attributes.count);
    for (var _item596 in value.attributes) {
        _a_Attribute_write(out, _item596);
    }
    out.flag(value.is_exported);
    out.flag(value.is_private);
}

_a_StaticBlock_read(input: RecordIn): ast.StaticBlock {
    var _v597 = Array<ast.Label>();
    var _n598 = input.count();
    for (var _ in 0.._n598) {
        _v597.append(_a_Label_read(input));
    }
    var _f599 = _v597;
    var _v600 = Array<ast.Expression>();
    var _n601 = input.count();
    for (var _ in 0.._n601) {
        _v600.append(_a_Expression_read(input));
    }
    var _f602 = _v600;
    var _f603 = _a_Block_read(input);
    var _s604 = input.unsigned();
    var _f605 = ast.Span(_s604, input.unsigned());
    var _s606 = input.unsigned();
    var _f607 = ast.Span(_s606, input.unsigned());
    var _v608 = Array<ast.Attribute>();
    var _n609 = input.count();
    for (var _ in 0.._n609) {
        _v608.append(_a_Attribute_read(input));
    }
    var _f610 = _v608;
    var _f611 = input.flag();
    var _f612 = input.flag();
    var value = ast.StaticBlock();
    value.captures = _f599;
    value.written_captures = _f602;
    value.block = _f603;
    value.keyword_span = _f605;
    value.span = _f607;
    value.attributes = _f610;
    value.is_exported = _f611;
    value.is_private = _f612;
    return value;
}

_a_Match_write(out: RecordOut, value: ast.Match) {
    _a_Expression_write(out, value.value);
    out.unsigned(value.arms.count);
    for (var _item613 in value.arms) {
        _a_MatchArm_write(out, _item613);
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
    var _f614 = _a_Expression_read(input);
    var _v615 = Array<ast.MatchArm>();
    var _n616 = input.count();
    for (var _ in 0.._n616) {
        _v615.append(_a_MatchArm_read(input));
    }
    var _f617 = _v615;
    var _o618 = Optional<ast.Block>.Empty;
    if (input.unsigned() == 1) {
        _o618 = Optional<ast.Block>.Value(_a_Block_read(input));
    }
    var _f619 = _o618;
    var _s620 = input.unsigned();
    var _f621 = ast.Span(_s620, input.unsigned());
    var _s622 = input.unsigned();
    var _f623 = ast.Span(_s622, input.unsigned());
    var _s624 = input.unsigned();
    var _f625 = ast.Span(_s624, input.unsigned());
    var value = ast.Match(_f614);
    value.value = _f614;
    value.arms = _f617;
    value.else_block = _f619;
    value.else_span = _f621;
    value.keyword_span = _f623;
    value.span = _f625;
    return value;
}

_a_MatchArm_write(out: RecordOut, value: ast.MatchArm) {
    out.unsigned(value.patterns.count);
    for (var _item626 in value.patterns) {
        _a_Pattern_write(out, _item626);
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
    var _v627 = Array<ast.Pattern>();
    var _n628 = input.count();
    for (var _ in 0.._n628) {
        _v627.append(_a_Pattern_read(input));
    }
    var _f629 = _v627;
    var _o630 = Optional<ast.Expression>.Empty;
    if (input.unsigned() == 1) {
        _o630 = Optional<ast.Expression>.Value(_a_Expression_read(input));
    }
    var _f631 = _o630;
    var _f632 = _a_Block_read(input);
    var _s633 = input.unsigned();
    var _f634 = ast.Span(_s633, input.unsigned());
    var value = ast.MatchArm();
    value.patterns = _f629;
    value.guard = _f631;
    value.body = _f632;
    value.span = _f634;
    return value;
}

_a_DestructureBinding_write(out: RecordOut, value: ast.DestructureBinding) {
    out.text(value.name);
    out.unsigned(out.blank_locs ? 0 : value.name_span.start);
    out.unsigned(out.blank_locs ? 0 : value.name_span.end);
    _a_TypeName_write(out, value.type_name);
    out.unsigned(value.nested.count);
    for (var _item635 in value.nested) {
        _a_DestructureBinding_write(out, _item635);
    }
}

_a_DestructureBinding_read(input: RecordIn): ast.DestructureBinding {
    var _f636 = input.text();
    var _s637 = input.unsigned();
    var _f638 = ast.Span(_s637, input.unsigned());
    var _f639 = _a_TypeName_read(input);
    var _v640 = Array<ast.DestructureBinding>();
    var _n641 = input.count();
    for (var _ in 0.._n641) {
        _v640.append(_a_DestructureBinding_read(input));
    }
    var _f642 = _v640;
    var value = ast.DestructureBinding();
    value.name = _f636;
    value.name_span = _f638;
    value.type_name = _f639;
    value.nested = _f642;
    return value;
}

_a_VariableDecl_write(out: RecordOut, value: ast.VariableDecl) {
    out.unsigned(value.attributes.count);
    for (var _item643 in value.attributes) {
        _a_Attribute_write(out, _item643);
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
    var _v644 = Array<ast.Attribute>();
    var _n645 = input.count();
    for (var _ in 0.._n645) {
        _v644.append(_a_Attribute_read(input));
    }
    var _f646 = _v644;
    var _f647 = input.text();
    var _s648 = input.unsigned();
    var _f649 = ast.Span(_s648, input.unsigned());
    var _f650 = _a_TypeName_read(input);
    var _o651 = Optional<ast.Expression>.Empty;
    if (input.unsigned() == 1) {
        _o651 = Optional<ast.Expression>.Value(_a_Expression_read(input));
    }
    var _f652 = _o651;
    var _f653 = input.flag();
    var _s654 = input.unsigned();
    var _f655 = ast.Span(_s654, input.unsigned());
    var _f656 = input.flag();
    var _f657 = input.flag();
    var value = ast.VariableDecl();
    value.attributes = _f646;
    value.name = _f647;
    value.name_span = _f649;
    value.type_name = _f650;
    value.default_value = _f652;
    value.is_const = _f653;
    value.span = _f655;
    value.is_exported = _f656;
    value.is_private = _f657;
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
        var _f658 = _a_VariableDecl_read(input);
        return ast.Declaration.Variable(_f658);
    }
    if (tag == 1) {
        var _f659 = _a_FunctionDecl_read(input);
        return ast.Declaration.Function(_f659);
    }
    if (tag == 2) {
        var _f660 = _a_StructDecl_read(input);
        return ast.Declaration.Struct(_f660);
    }
    if (tag == 3) {
        var _f661 = _a_TraitDecl_read(input);
        return ast.Declaration.Trait(_f661);
    }
    if (tag == 4) {
        var _f662 = _a_ExtendDecl_read(input);
        return ast.Declaration.Extend(_f662);
    }
    if (tag == 5) {
        var _f663 = _a_TypeAliasDecl_read(input);
        return ast.Declaration.TypeAlias(_f663);
    }
    if (tag == 6) {
        var _f664 = _a_StaticBlock_read(input);
        return ast.Declaration.Static(_f664);
    }
    input.fail("Declaration", tag);
    return _a_Declaration_read(input);
}

_a_TypeAliasDecl_write(out: RecordOut, value: ast.TypeAliasDecl) {
    out.unsigned(value.attributes.count);
    for (var _item665 in value.attributes) {
        _a_Attribute_write(out, _item665);
    }
    out.text(value.name);
    out.unsigned(out.blank_locs ? 0 : value.name_span.start);
    out.unsigned(out.blank_locs ? 0 : value.name_span.end);
    out.unsigned(value.generic_params.count);
    for (var _item666 in value.generic_params) {
        _a_GenericParam_write(out, _item666);
    }
    _a_TypeName_write(out, value.target);
    out.unsigned(out.blank_locs ? 0 : value.span.start);
    out.unsigned(out.blank_locs ? 0 : value.span.end);
    out.flag(value.is_exported);
    out.flag(value.is_private);
}

_a_TypeAliasDecl_read(input: RecordIn): ast.TypeAliasDecl {
    var _v667 = Array<ast.Attribute>();
    var _n668 = input.count();
    for (var _ in 0.._n668) {
        _v667.append(_a_Attribute_read(input));
    }
    var _f669 = _v667;
    var _f670 = input.text();
    var _s671 = input.unsigned();
    var _f672 = ast.Span(_s671, input.unsigned());
    var _v673 = Array<ast.GenericParam>();
    var _n674 = input.count();
    for (var _ in 0.._n674) {
        _v673.append(_a_GenericParam_read(input));
    }
    var _f675 = _v673;
    var _f676 = _a_TypeName_read(input);
    var _s677 = input.unsigned();
    var _f678 = ast.Span(_s677, input.unsigned());
    var _f679 = input.flag();
    var _f680 = input.flag();
    var value = ast.TypeAliasDecl();
    value.attributes = _f669;
    value.name = _f670;
    value.name_span = _f672;
    value.generic_params = _f675;
    value.target = _f676;
    value.span = _f678;
    value.is_exported = _f679;
    value.is_private = _f680;
    return value;
}

_a_GenericParam_write(out: RecordOut, value: ast.GenericParam) {
    out.text(value.name);
    out.unsigned(out.blank_locs ? 0 : value.name_span.start);
    out.unsigned(out.blank_locs ? 0 : value.name_span.end);
    out.unsigned(value.bounds.count);
    for (var _item681 in value.bounds) {
        _a_TypeName_write(out, _item681);
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
    var _f682 = input.text();
    var _s683 = input.unsigned();
    var _f684 = ast.Span(_s683, input.unsigned());
    var _v685 = Array<ast.TypeName>();
    var _n686 = input.count();
    for (var _ in 0.._n686) {
        _v685.append(_a_TypeName_read(input));
    }
    var _f687 = _v685;
    var _o688 = Optional<ast.TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o688 = Optional<ast.TypeName>.Value(_a_TypeName_read(input));
    }
    var _f689 = _o688;
    var _f690 = input.flag();
    var value = ast.GenericParam(_f682, _f684);
    value.name = _f682;
    value.name_span = _f684;
    value.bounds = _f687;
    value.default = _f689;
    value.is_argument = _f690;
    return value;
}

_a_ExtendDecl_write(out: RecordOut, value: ast.ExtendDecl) {
    out.unsigned(value.attributes.count);
    for (var _item691 in value.attributes) {
        _a_Attribute_write(out, _item691);
    }
    _a_TypeName_write(out, value.target);
    out.unsigned(value.target_bounds.count);
    for (var _item692 in value.target_bounds) {
        out.unsigned(_item692.count);
        for (var _item693 in _item692) {
            _a_TypeName_write(out, _item693);
        }
    }
    out.unsigned(value.traits.count);
    for (var _item694 in value.traits) {
        _a_TypeName_write(out, _item694);
    }
    out.unsigned(value.methods.count);
    for (var _item695 in value.methods) {
        _a_FunctionDecl_write(out, _item695);
    }
    out.unsigned(value.properties.count);
    for (var _item696 in value.properties) {
        _a_PropertyDecl_write(out, _item696);
    }
    out.unsigned(out.blank_locs ? 0 : value.span.start);
    out.unsigned(out.blank_locs ? 0 : value.span.end);
    out.flag(value.is_exported);
    out.flag(value.is_private);
}

_a_ExtendDecl_read(input: RecordIn): ast.ExtendDecl {
    var _v697 = Array<ast.Attribute>();
    var _n698 = input.count();
    for (var _ in 0.._n698) {
        _v697.append(_a_Attribute_read(input));
    }
    var _f699 = _v697;
    var _f700 = _a_TypeName_read(input);
    var _v701 = Array<Array<ast.TypeName>>();
    var _n702 = input.count();
    for (var _ in 0.._n702) {
        var _v703 = Array<ast.TypeName>();
        var _n704 = input.count();
        for (var _ in 0.._n704) {
            _v703.append(_a_TypeName_read(input));
        }
        _v701.append(_v703);
    }
    var _f705 = _v701;
    var _v706 = Array<ast.TypeName>();
    var _n707 = input.count();
    for (var _ in 0.._n707) {
        _v706.append(_a_TypeName_read(input));
    }
    var _f708 = _v706;
    var _v709 = Array<ast.FunctionDecl>();
    var _n710 = input.count();
    for (var _ in 0.._n710) {
        _v709.append(_a_FunctionDecl_read(input));
    }
    var _f711 = _v709;
    var _v712 = Array<ast.PropertyDecl>();
    var _n713 = input.count();
    for (var _ in 0.._n713) {
        _v712.append(_a_PropertyDecl_read(input));
    }
    var _f714 = _v712;
    var _s715 = input.unsigned();
    var _f716 = ast.Span(_s715, input.unsigned());
    var _f717 = input.flag();
    var _f718 = input.flag();
    var value = ast.ExtendDecl();
    value.attributes = _f699;
    value.target = _f700;
    value.target_bounds = _f705;
    value.traits = _f708;
    value.methods = _f711;
    value.properties = _f714;
    value.span = _f716;
    value.is_exported = _f717;
    value.is_private = _f718;
    return value;
}

_a_PropertyDecl_write(out: RecordOut, value: ast.PropertyDecl) {
    out.unsigned(value.attributes.count);
    for (var _item719 in value.attributes) {
        _a_Attribute_write(out, _item719);
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
    out.flag(value.is_static);
    out.unsigned(out.blank_locs ? 0 : value.span.start);
    out.unsigned(out.blank_locs ? 0 : value.span.end);
}

_a_PropertyDecl_read(input: RecordIn): ast.PropertyDecl {
    var _v720 = Array<ast.Attribute>();
    var _n721 = input.count();
    for (var _ in 0.._n721) {
        _v720.append(_a_Attribute_read(input));
    }
    var _f722 = _v720;
    var _f723 = input.text();
    var _s724 = input.unsigned();
    var _f725 = ast.Span(_s724, input.unsigned());
    var _f726 = _a_TypeName_read(input);
    var _o727 = Optional<ast.Expression>.Empty;
    if (input.unsigned() == 1) {
        _o727 = Optional<ast.Expression>.Value(_a_Expression_read(input));
    }
    var _f728 = _o727;
    var _o729 = Optional<ast.Accessor>.Empty;
    if (input.unsigned() == 1) {
        _o729 = Optional<ast.Accessor>.Value(_a_Accessor_read(input));
    }
    var _f730 = _o729;
    var _o731 = Optional<ast.Accessor>.Empty;
    if (input.unsigned() == 1) {
        _o731 = Optional<ast.Accessor>.Value(_a_Accessor_read(input));
    }
    var _f732 = _o731;
    var _f733 = input.flag();
    var _s734 = input.unsigned();
    var _f735 = ast.Span(_s734, input.unsigned());
    var value = ast.PropertyDecl();
    value.attributes = _f722;
    value.name = _f723;
    value.name_span = _f725;
    value.type_name = _f726;
    value.default_value = _f728;
    value.getter = _f730;
    value.setter = _f732;
    value.is_static = _f733;
    value.span = _f735;
    return value;
}

_a_Accessor_write(out: RecordOut, value: ast.Accessor) {
    out.unsigned(out.blank_locs ? 0 : value.span.start);
    out.unsigned(out.blank_locs ? 0 : value.span.end);
    _a_FunctionDecl_write(out, value.function);
}

_a_Accessor_read(input: RecordIn): ast.Accessor {
    var _s736 = input.unsigned();
    var _f737 = ast.Span(_s736, input.unsigned());
    var _f738 = _a_FunctionDecl_read(input);
    var value = ast.Accessor(_f737, _f738);
    value.span = _f737;
    value.function = _f738;
    return value;
}

_a_FunctionDecl_write(out: RecordOut, value: ast.FunctionDecl) {
    out.text(value.name);
    out.unsigned(out.blank_locs ? 0 : value.name_span.start);
    out.unsigned(out.blank_locs ? 0 : value.name_span.end);
    out.unsigned(value.generic_params.count);
    for (var _item739 in value.generic_params) {
        _a_GenericParam_write(out, _item739);
    }
    _a_TypeName_write(out, value.return_type);
    out.unsigned(value.parameters.count);
    for (var _item740 in value.parameters) {
        _a_VariableDecl_write(out, _item740);
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
    for (var _item741 in value.attributes) {
        _a_Attribute_write(out, _item741);
    }
    out.flag(value.is_exported);
    out.flag(value.is_private);
}

_a_FunctionDecl_read(input: RecordIn): ast.FunctionDecl {
    var _f742 = input.text();
    var _s743 = input.unsigned();
    var _f744 = ast.Span(_s743, input.unsigned());
    var _v745 = Array<ast.GenericParam>();
    var _n746 = input.count();
    for (var _ in 0.._n746) {
        _v745.append(_a_GenericParam_read(input));
    }
    var _f747 = _v745;
    var _f748 = _a_TypeName_read(input);
    var _v749 = Array<ast.VariableDecl>();
    var _n750 = input.count();
    for (var _ in 0.._n750) {
        _v749.append(_a_VariableDecl_read(input));
    }
    var _f751 = _v749;
    var _f752 = input.flag();
    var _o753 = Optional<ast.Block>.Empty;
    if (input.unsigned() == 1) {
        _o753 = Optional<ast.Block>.Value(_a_Block_read(input));
    }
    var _f754 = _o753;
    var _f755 = input.flag();
    var _f756 = input.flag();
    var _f757 = input.flag();
    var _s758 = input.unsigned();
    var _f759 = ast.Span(_s758, input.unsigned());
    var _v760 = Array<ast.Attribute>();
    var _n761 = input.count();
    for (var _ in 0.._n761) {
        _v760.append(_a_Attribute_read(input));
    }
    var _f762 = _v760;
    var _f763 = input.flag();
    var _f764 = input.flag();
    var value = ast.FunctionDecl();
    value.name = _f742;
    value.name_span = _f744;
    value.generic_params = _f747;
    value.return_type = _f748;
    value.parameters = _f751;
    value.external = _f752;
    value.body = _f754;
    value.is_static = _f755;
    value.is_indexer = _f756;
    value.is_variadic = _f757;
    value.span = _f759;
    value.attributes = _f762;
    value.is_exported = _f763;
    value.is_private = _f764;
    return value;
}

_a_TraitDecl_write(out: RecordOut, value: ast.TraitDecl) {
    out.unsigned(value.attributes.count);
    for (var _item765 in value.attributes) {
        _a_Attribute_write(out, _item765);
    }
    out.text(value.name);
    out.unsigned(out.blank_locs ? 0 : value.name_span.start);
    out.unsigned(out.blank_locs ? 0 : value.name_span.end);
    out.unsigned(value.generic_params.count);
    for (var _item766 in value.generic_params) {
        _a_GenericParam_write(out, _item766);
    }
    out.unsigned(value.methods.count);
    for (var _item767 in value.methods) {
        _a_FunctionDecl_write(out, _item767);
    }
    out.unsigned(value.properties.count);
    for (var _item768 in value.properties) {
        _a_PropertyDecl_write(out, _item768);
    }
    out.unsigned(out.blank_locs ? 0 : value.span.start);
    out.unsigned(out.blank_locs ? 0 : value.span.end);
    out.flag(value.is_exported);
    out.flag(value.is_private);
}

_a_TraitDecl_read(input: RecordIn): ast.TraitDecl {
    var _v769 = Array<ast.Attribute>();
    var _n770 = input.count();
    for (var _ in 0.._n770) {
        _v769.append(_a_Attribute_read(input));
    }
    var _f771 = _v769;
    var _f772 = input.text();
    var _s773 = input.unsigned();
    var _f774 = ast.Span(_s773, input.unsigned());
    var _v775 = Array<ast.GenericParam>();
    var _n776 = input.count();
    for (var _ in 0.._n776) {
        _v775.append(_a_GenericParam_read(input));
    }
    var _f777 = _v775;
    var _v778 = Array<ast.FunctionDecl>();
    var _n779 = input.count();
    for (var _ in 0.._n779) {
        _v778.append(_a_FunctionDecl_read(input));
    }
    var _f780 = _v778;
    var _v781 = Array<ast.PropertyDecl>();
    var _n782 = input.count();
    for (var _ in 0.._n782) {
        _v781.append(_a_PropertyDecl_read(input));
    }
    var _f783 = _v781;
    var _s784 = input.unsigned();
    var _f785 = ast.Span(_s784, input.unsigned());
    var _f786 = input.flag();
    var _f787 = input.flag();
    var value = ast.TraitDecl();
    value.attributes = _f771;
    value.name = _f772;
    value.name_span = _f774;
    value.generic_params = _f777;
    value.methods = _f780;
    value.properties = _f783;
    value.span = _f785;
    value.is_exported = _f786;
    value.is_private = _f787;
    return value;
}

_a_StructDecl_write(out: RecordOut, value: ast.StructDecl) {
    out.text(value.name);
    out.unsigned(out.blank_locs ? 0 : value.name_span.start);
    out.unsigned(out.blank_locs ? 0 : value.name_span.end);
    out.unsigned(value.generic_params.count);
    for (var _item788 in value.generic_params) {
        _a_GenericParam_write(out, _item788);
    }
    out.unsigned(value.fields.count);
    for (var _item789 in value.fields) {
        _a_VariableDecl_write(out, _item789);
    }
    out.unsigned(value.properties.count);
    for (var _item790 in value.properties) {
        _a_PropertyDecl_write(out, _item790);
    }
    out.unsigned(value.methods.count);
    for (var _item791 in value.methods) {
        _a_FunctionDecl_write(out, _item791);
    }
    out.unsigned(value.constructors.count);
    for (var _item792 in value.constructors) {
        _a_FunctionDecl_write(out, _item792);
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
    for (var _item793 in value.attributes) {
        _a_Attribute_write(out, _item793);
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
    var _f794 = input.text();
    var _s795 = input.unsigned();
    var _f796 = ast.Span(_s795, input.unsigned());
    var _v797 = Array<ast.GenericParam>();
    var _n798 = input.count();
    for (var _ in 0.._n798) {
        _v797.append(_a_GenericParam_read(input));
    }
    var _f799 = _v797;
    var _v800 = Array<ast.VariableDecl>();
    var _n801 = input.count();
    for (var _ in 0.._n801) {
        _v800.append(_a_VariableDecl_read(input));
    }
    var _f802 = _v800;
    var _v803 = Array<ast.PropertyDecl>();
    var _n804 = input.count();
    for (var _ in 0.._n804) {
        _v803.append(_a_PropertyDecl_read(input));
    }
    var _f805 = _v803;
    var _v806 = Array<ast.FunctionDecl>();
    var _n807 = input.count();
    for (var _ in 0.._n807) {
        _v806.append(_a_FunctionDecl_read(input));
    }
    var _f808 = _v806;
    var _v809 = Array<ast.FunctionDecl>();
    var _n810 = input.count();
    for (var _ in 0.._n810) {
        _v809.append(_a_FunctionDecl_read(input));
    }
    var _f811 = _v809;
    var _o812 = Optional<ast.Block>.Empty;
    if (input.unsigned() == 1) {
        _o812 = Optional<ast.Block>.Value(_a_Block_read(input));
    }
    var _f813 = _o812;
    var _o814 = Optional<ast.Span>.Empty;
    if (input.unsigned() == 1) {
        var _s815 = input.unsigned();
        _o814 = Optional<ast.Span>.Value(ast.Span(_s815, input.unsigned()));
    }
    var _f816 = _o814;
    var _s817 = input.unsigned();
    var _f818 = ast.Span(_s817, input.unsigned());
    var _v819 = Array<ast.Attribute>();
    var _n820 = input.count();
    for (var _ in 0.._n820) {
        _v819.append(_a_Attribute_read(input));
    }
    var _f821 = _v819;
    var _f822 = input.flag();
    var _f823 = input.flag();
    var _o824 = Optional<ast.EnumBody>.Empty;
    if (input.unsigned() == 1) {
        _o824 = Optional<ast.EnumBody>.Value(_a_EnumBody_read(input));
    }
    var _f825 = _o824;
    var value = ast.StructDecl();
    value.name = _f794;
    value.name_span = _f796;
    value.generic_params = _f799;
    value.fields = _f802;
    value.properties = _f805;
    value.methods = _f808;
    value.constructors = _f811;
    value.destructor = _f813;
    value.destruct_span = _f816;
    value.span = _f818;
    value.attributes = _f821;
    value.is_exported = _f822;
    value.is_private = _f823;
    value.enumeration = _f825;
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
    for (var _item826 in value.cases) {
        _a_EnumCase_write(out, _item826);
    }
}

_a_EnumBody_read(input: RecordIn): ast.EnumBody {
    var _o827 = Optional<ast.TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o827 = Optional<ast.TypeName>.Value(_a_TypeName_read(input));
    }
    var _f828 = _o827;
    var _v829 = Array<ast.EnumCase>();
    var _n830 = input.count();
    for (var _ in 0.._n830) {
        _v829.append(_a_EnumCase_read(input));
    }
    var _f831 = _v829;
    var value = ast.EnumBody();
    value.representation = _f828;
    value.cases = _f831;
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
        for (var _item832 in value.payload.value()) {
            _a_VariableDecl_write(out, _item832);
        }
    } else {
        out.unsigned(0);
    }
    out.unsigned(value.attributes.count);
    for (var _item833 in value.attributes) {
        _a_Attribute_write(out, _item833);
    }
    out.unsigned(out.blank_locs ? 0 : value.span.start);
    out.unsigned(out.blank_locs ? 0 : value.span.end);
}

_a_EnumCase_read(input: RecordIn): ast.EnumCase {
    var _f834 = input.text();
    var _s835 = input.unsigned();
    var _f836 = ast.Span(_s835, input.unsigned());
    var _o837 = Optional<ast.Expression>.Empty;
    if (input.unsigned() == 1) {
        _o837 = Optional<ast.Expression>.Value(_a_Expression_read(input));
    }
    var _f838 = _o837;
    var _o839 = Optional<Array<ast.VariableDecl>>.Empty;
    if (input.unsigned() == 1) {
        var _v840 = Array<ast.VariableDecl>();
        var _n841 = input.count();
        for (var _ in 0.._n841) {
            _v840.append(_a_VariableDecl_read(input));
        }
        _o839 = Optional<Array<ast.VariableDecl>>.Value(_v840);
    }
    var _f842 = _o839;
    var _v843 = Array<ast.Attribute>();
    var _n844 = input.count();
    for (var _ in 0.._n844) {
        _v843.append(_a_Attribute_read(input));
    }
    var _f845 = _v843;
    var _s846 = input.unsigned();
    var _f847 = ast.Span(_s846, input.unsigned());
    var value = ast.EnumCase();
    value.name = _f834;
    value.name_span = _f836;
    value.value = _f838;
    value.payload = _f842;
    value.attributes = _f845;
    value.span = _f847;
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
        var _f848 = input.text();
        return ast.Literal.String(_f848);
    }
    if (tag == 1) {
        var _f849 = input.signed();
        return ast.Literal.Integer(_f849);
    }
    if (tag == 2) {
        var _f850 = input.unsigned();
        return ast.Literal.Unsigned(_f850);
    }
    if (tag == 3) {
        var _f851 = input.number();
        return ast.Literal.Float(_f851);
    }
    if (tag == 4) {
        var _f852 = input.flag();
        return ast.Literal.Bool(_f852);
    }
    if (tag == 5) {
        var _f853 = input.unsigned() as u8;
        return ast.Literal.Char(_f853);
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
    for (var _item854 in value.items) {
        _m_Statement_write(out, _item854);
    }
    out.unsigned(value.attributes.count);
    for (var _item855 in value.attributes) {
        _a_Attribute_write(out, _item855);
    }
}

_m_Block_read(input: RecordIn): Block {
    var _f856 = input.text();
    var _v857 = Array<Statement>();
    var _n858 = input.count();
    for (var _ in 0.._n858) {
        _v857.append(_m_Statement_read(input));
    }
    var _f859 = _v857;
    var _v860 = Array<ast.Attribute>();
    var _n861 = input.count();
    for (var _ in 0.._n861) {
        _v860.append(_a_Attribute_read(input));
    }
    var _f862 = _v860;
    return Block(_f856, _f859, _f862);
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
        var _f1281 = _m_Expression_read(input);
        return Statement.Expression(_f1281);
    }
    if (tag == 1) {
        var _f1282 = _m_Block_read(input);
        return Statement.Block(_f1282);
    }
    if (tag == 2) {
        var _f1283 = _m_Declaration_read(input);
        return Statement.Declaration(_f1283);
    }
    if (tag == 3) {
        var _f1284 = _m_Branch_read(input);
        return Statement.Branch(_f1284);
    }
    if (tag == 4) {
        var _f1285 = _m_While_read(input);
        return Statement.While(_f1285);
    }
    if (tag == 5) {
        var _f1286 = _m_ReturnStatement_read(input);
        return Statement.Return(_f1286);
    }
    if (tag == 6) {
        var _f1287 = _m_LoopBreak_read(input);
        return Statement.LoopBreak(_f1287);
    }
    if (tag == 7) {
        var _f1288 = _m_StaticBlock_read(input);
        return Statement.Static(_f1288);
    }
    if (tag == 8) {
        var _f1289 = _m_StaticPass_read(input);
        return Statement.StaticPass(_f1289);
    }
    input.fail("Statement", tag);
    return _m_Statement_read(input);
}

_m_StaticPass_write(out: RecordOut, value: StaticPass) {
    out.loc(value.loc);
    out.flag(value.stop);
    out.unsigned(value.values.count);
    for (var _item863 in value.values) {
        var (_t864, _t865) = _item863;
        out.text(_t864);
        _m_StaticConstant_write(out, _t865);
    }
    if (value.header.is_value()) {
        out.unsigned(1);
        out.unsigned(value.header.value() as ulong);
    } else {
        out.unsigned(0);
    }
    out.unsigned(value.lines.count);
    for (var _item866 in value.lines) {
        var (_t867, _t868) = _item866;
        out.loc(_t867);
        out.unsigned(_t868 as ulong);
    }
}

_m_StaticPass_read(input: RecordIn): StaticPass {
    var _f869 = input.loc();
    var _f870 = input.flag();
    var _v871 = Array<(String, StaticConstant)>();
    var _n872 = input.count();
    for (var _ in 0.._n872) {
        var _t873 = input.text();
        var _t874 = _m_StaticConstant_read(input);
        _v871.append((_t873, _t874));
    }
    var _f875 = _v871;
    var _o876 = Optional<uint>.Empty;
    if (input.unsigned() == 1) {
        _o876 = Optional<uint>.Value(input.unsigned() as uint);
    }
    var _f877 = _o876;
    var _v878 = Array<(Loc, uint)>();
    var _n879 = input.count();
    for (var _ in 0.._n879) {
        var _t880 = input.loc();
        var _t881 = input.unsigned() as uint;
        _v878.append((_t880, _t881));
    }
    var _f882 = _v878;
    return StaticPass(_f869, _f870, _f875, _f877, _f882);
}

_m_RecordStaticConstant_write(out: RecordOut, value: RecordStaticConstant) {
    out.text(value.name);
    out.unsigned(value.fields.count);
    for (var _item1294 in value.fields) {
        var (_t1295, _t1296) = _item1294;
        out.text(_t1295);
        _m_StaticConstant_write(out, _t1296);
    }
}

_m_RecordStaticConstant_read(input: RecordIn): RecordStaticConstant {
    var _f1297 = input.text();
    var _v1298 = Array<(String, StaticConstant)>();
    var _n1299 = input.count();
    for (var _ in 0.._n1299) {
        var _t1300 = input.text();
        var _t1301 = _m_StaticConstant_read(input);
        _v1298.append((_t1300, _t1301));
    }
    var _f1302 = _v1298;
    return RecordStaticConstant(_f1297, _f1302);
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
        var _f1290 = input.signed();
        return StaticConstant.Int(_f1290);
    }
    if (tag == 1) {
        var _f1291 = input.number();
        return StaticConstant.Float(_f1291);
    }
    if (tag == 2) {
        var _f1292 = input.flag();
        return StaticConstant.Bool(_f1292);
    }
    if (tag == 3) {
        var _f1293 = input.text();
        return StaticConstant.String(_f1293);
    }
    if (tag == 4) {
        return StaticConstant.Record(_m_RecordStaticConstant_read(input));
    }
    input.fail("StaticConstant", tag);
    return _m_StaticConstant_read(input);
}

_m_StaticBlock_write(out: RecordOut, value: StaticBlock) {
    out.unsigned(value.captures.count);
    for (var _item883 in value.captures) {
        out.text(_item883);
    }
    out.unsigned(value.items.count);
    for (var _item884 in value.items) {
        _m_StaticItem_write(out, _item884);
    }
    out.unsigned(value.type_map.count);
    for (var _item885 in value.type_map) {
        var (_t886, _t887) = _item885;
        out.text(_t886);
        _m_TypeName_write(out, _t887);
    }
    out.loc(value.loc);
    out.unsigned(out.blank_locs ? 0 : value.span.start);
    out.unsigned(out.blank_locs ? 0 : value.span.end);
}

_m_StaticBlock_read(input: RecordIn): StaticBlock {
    var _v888 = Array<String>();
    var _n889 = input.count();
    for (var _ in 0.._n889) {
        _v888.append(input.text());
    }
    var _f890 = _v888;
    var _v891 = Array<StaticItem>();
    var _n892 = input.count();
    for (var _ in 0.._n892) {
        _v891.append(_m_StaticItem_read(input));
    }
    var _f893 = _v891;
    var _v894 = Array<(String, TypeName)>();
    var _n895 = input.count();
    for (var _ in 0.._n895) {
        var _t896 = input.text();
        var _t897 = _m_TypeName_read(input);
        _v894.append((_t896, _t897));
    }
    var _f898 = _v894;
    var _f899 = input.loc();
    var _s900 = input.unsigned();
    var _f901 = ast.Span(_s900, input.unsigned());
    return StaticBlock(_f890, _f893, _f898, _f899, _f901);
}

_m_TypeName_write(out: RecordOut, value: TypeName) {
    out.text(value.name);
    out.unsigned(value.sub_types.count);
    for (var _item902 in value.sub_types) {
        _m_TypeName_write(out, _item902);
    }
    _m_TypeFlags_write(out, value.flags);
    out.unsigned(value.labels.count);
    for (var _item903 in value.labels) {
        out.text(_item903);
    }
}

_m_TypeName_read(input: RecordIn): TypeName {
    var _f904 = input.text();
    var _v905 = Array<TypeName>();
    var _n906 = input.count();
    for (var _ in 0.._n906) {
        _v905.append(_m_TypeName_read(input));
    }
    var _f907 = _v905;
    var _f908 = _m_TypeFlags_read(input);
    var _v909 = Array<String>();
    var _n910 = input.count();
    for (var _ in 0.._n910) {
        _v909.append(input.text());
    }
    var _f911 = _v909;
    return TypeName(_f904, _f907, _f908, _f911);
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
    for (var _item1303 in value.body) {
        _m_StaticItem_write(out, _item1303);
    }
    out.loc(value.loc);
}

_m_ForStaticItem_read(input: RecordIn): ForStaticItem {
    var _f1304 = input.text();
    var _f1305 = _a_Expression_read(input);
    var _v1306 = Array<StaticItem>();
    var _n1307 = input.count();
    for (var _ in 0.._n1307) {
        _v1306.append(_m_StaticItem_read(input));
    }
    var _f1308 = _v1306;
    var _f1309 = input.loc();
    return ForStaticItem(_f1305, _f1304, _f1308, _f1309);
}

_m_WhileStaticItem_write(out: RecordOut, value: WhileStaticItem) {
    _a_Expression_write(out, value.condition);
    out.unsigned(value.body.count);
    for (var _item1310 in value.body) {
        _m_StaticItem_write(out, _item1310);
    }
    out.loc(value.loc);
}

_m_WhileStaticItem_read(input: RecordIn): WhileStaticItem {
    var _f1311 = _a_Expression_read(input);
    var _v1312 = Array<StaticItem>();
    var _n1313 = input.count();
    for (var _ in 0.._n1313) {
        _v1312.append(_m_StaticItem_read(input));
    }
    var _f1314 = _v1312;
    var _f1315 = input.loc();
    return WhileStaticItem(_f1311, _f1314, _f1315);
}

_m_JumpStaticItem_write(out: RecordOut, value: JumpStaticItem) {
    _m_LoopBreakKind_write(out, value.kind);
    out.loc(value.loc);
}

_m_JumpStaticItem_read(input: RecordIn): JumpStaticItem {
    var _f1316 = _m_LoopBreakKind_read(input);
    var _f1317 = input.loc();
    return JumpStaticItem(_f1316, _f1317);
}

_m_IfStaticItem_write(out: RecordOut, value: IfStaticItem) {
    _a_Expression_write(out, value.condition);
    out.unsigned(value.then_items.count);
    for (var _item1318 in value.then_items) {
        _m_StaticItem_write(out, _item1318);
    }
    out.unsigned(value.else_items.count);
    for (var _item1319 in value.else_items) {
        _m_StaticItem_write(out, _item1319);
    }
    out.loc(value.loc);
}

_m_IfStaticItem_read(input: RecordIn): IfStaticItem {
    var _f1320 = _a_Expression_read(input);
    var _v1321 = Array<StaticItem>();
    var _n1322 = input.count();
    for (var _ in 0.._n1322) {
        _v1321.append(_m_StaticItem_read(input));
    }
    var _f1323 = _v1321;
    var _v1324 = Array<StaticItem>();
    var _n1325 = input.count();
    for (var _ in 0.._n1325) {
        _v1324.append(_m_StaticItem_read(input));
    }
    var _f1326 = _v1324;
    var _f1327 = input.loc();
    return IfStaticItem(_f1320, _f1323, _f1326, _f1327);
}

_m_EmitIfStaticItem_write(out: RecordOut, value: EmitIfStaticItem) {
    _m_Expression_write(out, value.condition);
    out.unsigned(value.then_items.count);
    for (var _item1328 in value.then_items) {
        _m_StaticItem_write(out, _item1328);
    }
    out.unsigned(value.else_items.count);
    for (var _item1329 in value.else_items) {
        _m_StaticItem_write(out, _item1329);
    }
    out.unsigned(out.blank_locs ? 0 : value.span.start);
    out.unsigned(out.blank_locs ? 0 : value.span.end);
}

_m_EmitIfStaticItem_read(input: RecordIn): EmitIfStaticItem {
    var _f1330 = _m_Expression_read(input);
    var _v1331 = Array<StaticItem>();
    var _n1332 = input.count();
    for (var _ in 0.._n1332) {
        _v1331.append(_m_StaticItem_read(input));
    }
    var _f1333 = _v1331;
    var _v1334 = Array<StaticItem>();
    var _n1335 = input.count();
    for (var _ in 0.._n1335) {
        _v1334.append(_m_StaticItem_read(input));
    }
    var _f1336 = _v1334;
    var _s1337 = input.unsigned();
    var _f1338 = ast.Span(_s1337, input.unsigned());
    return EmitIfStaticItem(_f1330, _f1333, _f1336, _f1338);
}

_m_VarStaticItem_write(out: RecordOut, value: VarStaticItem) {
    out.text(value.name);
    _a_Expression_write(out, value.value);
    out.loc(value.loc);
}

_m_VarStaticItem_read(input: RecordIn): VarStaticItem {
    var _f1343 = input.text();
    var _f1344 = _a_Expression_read(input);
    var _f1345 = input.loc();
    return VarStaticItem(_f1344, _f1343, _f1345);
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
            for (var _item1339 in v) {
                _m_StaticItem_write(out, _item1339);
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
        var _v1340 = Array<StaticItem>();
        var _n1341 = input.count();
        for (var _ in 0.._n1341) {
            _v1340.append(_m_StaticItem_read(input));
        }
        var _f1342 = _v1340;
        return StaticItem.Block(_f1342);
    }
    if (tag == 6) {
        return StaticItem.Var(_m_VarStaticItem_read(input));
    }
    if (tag == 7) {
        var _f1346 = _a_Expression_read(input);
        return StaticItem.Evaluate(_f1346);
    }
    if (tag == 8) {
        var _f1347 = _m_Statement_read(input);
        var _s1348 = input.unsigned();
        var _f1349 = ast.Span(_s1348, input.unsigned());
        return StaticItem.Emit(_f1347, _f1349);
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
    var _f1350 = input.text();
    var _f1351 = _m_TypeName_read(input);
    var _f1352 = input.loc();
    return SymbolRefExpression(_f1350, _f1351, _f1352);
}

_m_MemberRefExpression_write(out: RecordOut, value: MemberRefExpression) {
    _m_Expression_write(out, value.lhs);
    out.text(value.name);
    out.loc(value.loc);
}

_m_MemberRefExpression_read(input: RecordIn): MemberRefExpression {
    var _f1353 = _m_Expression_read(input);
    var _f1354 = input.text();
    var _f1355 = input.loc();
    return MemberRefExpression(_f1353, _f1354, _f1355);
}

_m_StringLiteralExpression_write(out: RecordOut, value: StringLiteralExpression) {
    out.text(value.value);
    out.flag(value.is_raw);
    out.loc(value.loc);
}

_m_StringLiteralExpression_read(input: RecordIn): StringLiteralExpression {
    var _f1362 = input.text();
    var _f1363 = input.flag();
    var _f1364 = input.loc();
    return StringLiteralExpression(_f1362, _f1363, _f1364);
}

_m_BinaryExpression_write(out: RecordOut, value: BinaryExpression) {
    _m_BinaryOp_write(out, value.op);
    _m_Expression_write(out, value.lhs);
    _m_Expression_write(out, value.rhs);
    out.loc(value.loc);
}

_m_BinaryExpression_read(input: RecordIn): BinaryExpression {
    var _f1366 = _m_BinaryOp_read(input);
    var _f1367 = _m_Expression_read(input);
    var _f1368 = _m_Expression_read(input);
    var _f1369 = input.loc();
    return BinaryExpression(_f1367, _f1368, _f1366, _f1369);
}

_m_UnaryExpression_write(out: RecordOut, value: UnaryExpression) {
    _m_UnaryOp_write(out, value.op);
    _m_Expression_write(out, value.operand);
    out.loc(value.loc);
}

_m_UnaryExpression_read(input: RecordIn): UnaryExpression {
    var _f1370 = _m_UnaryOp_read(input);
    var _f1371 = _m_Expression_read(input);
    var _f1372 = input.loc();
    return UnaryExpression(_f1371, _f1370, _f1372);
}

_m_CastExpression_write(out: RecordOut, value: CastExpression) {
    _m_Expression_write(out, value.expr);
    _m_TypeName_write(out, value.ty);
    out.loc(value.loc);
    _m_CastKind_write(out, value.kind);
}

_m_CastExpression_read(input: RecordIn): CastExpression {
    var _f1373 = _m_Expression_read(input);
    var _f1374 = _m_TypeName_read(input);
    var _f1375 = input.loc();
    var _f1376 = _m_CastKind_read(input);
    return CastExpression(_f1373, _f1374, _f1375, _f1376);
}

_m_TernaryExpression_write(out: RecordOut, value: TernaryExpression) {
    _m_Expression_write(out, value.condition);
    _m_Expression_write(out, value.true_expr);
    _m_Expression_write(out, value.false_expr);
}

_m_TernaryExpression_read(input: RecordIn): TernaryExpression {
    var _f1377 = _m_Expression_read(input);
    var _f1378 = _m_Expression_read(input);
    var _f1379 = _m_Expression_read(input);
    return TernaryExpression(_f1377, _f1378, _f1379);
}

_m_IndexExpression_write(out: RecordOut, value: IndexExpression) {
    _m_Expression_write(out, value.lhs);
    _m_Expression_write(out, value.rhs);
    out.loc(value.loc);
}

_m_IndexExpression_read(input: RecordIn): IndexExpression {
    var _f1380 = _m_Expression_read(input);
    var _f1381 = _m_Expression_read(input);
    var _f1382 = input.loc();
    return IndexExpression(_f1380, _f1381, _f1382);
}

_m_ArrayIndexExpression_write(out: RecordOut, value: ArrayIndexExpression) {
    _m_TypeName_write(out, value.ty);
    _m_Expression_write(out, value.lhs);
    _m_Expression_write(out, value.rhs);
    out.loc(value.loc);
}

_m_ArrayIndexExpression_read(input: RecordIn): ArrayIndexExpression {
    var _f1383 = _m_TypeName_read(input);
    var _f1384 = _m_Expression_read(input);
    var _f1385 = _m_Expression_read(input);
    var _f1386 = input.loc();
    return ArrayIndexExpression(_f1384, _f1385, _f1383, _f1386);
}

_m_SimdExpression_write(out: RecordOut, value: SimdExpression) {
    _m_SimdOp_write(out, value.op);
    _m_TypeName_write(out, value.ty);
    out.unsigned(value.args.count);
    for (var _item1410 in value.args) {
        _m_Expression_write(out, _item1410);
    }
    out.loc(value.loc);
}

_m_SimdExpression_read(input: RecordIn): SimdExpression {
    var _f1411 = _m_SimdOp_read(input);
    var _f1412 = _m_TypeName_read(input);
    var _v1413 = Array<Expression>();
    var _n1414 = input.count();
    for (var _ in 0.._n1414) {
        _v1413.append(_m_Expression_read(input));
    }
    var _f1415 = _v1413;
    var _f1416 = input.loc();
    return SimdExpression(_f1411, _f1412, _f1415, _f1416);
}

_m_CountStepExpression_write(out: RecordOut, value: CountStepExpression) {
    _m_CountField_write(out, value.field);
    out.flag(value.increment);
    out.flag(value.atomic);
}

_m_CountStepExpression_read(input: RecordIn): CountStepExpression {
    var _f1420 = _m_CountField_read(input);
    var _f1421 = input.flag();
    var _f1422 = input.flag();
    return CountStepExpression(_f1420, _f1421, _f1422);
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
    var _o1423 = Optional<TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o1423 = Optional<TypeName>.Value(_m_TypeName_read(input));
    }
    var _f1424 = _o1423;
    var _f1425 = input.text();
    var _f1426 = input.loc();
    return FunctionPointerExpression(_f1424, _f1425, _f1426);
}

_m_FunctionCallExpression_write(out: RecordOut, value: FunctionCallExpression) {
    out.text(value.function);
    out.unsigned(value.args.count);
    for (var _item1427 in value.args) {
        _m_Expression_write(out, _item1427);
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
    var _f1428 = input.text();
    var _v1429 = Array<Expression>();
    var _n1430 = input.count();
    for (var _ in 0.._n1430) {
        _v1429.append(_m_Expression_read(input));
    }
    var _f1431 = _v1429;
    var _f1432 = input.loc();
    var _o1433 = Optional<TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o1433 = Optional<TypeName>.Value(_m_TypeName_read(input));
    }
    var _f1434 = _o1433;
    var _f1435 = input.flag();
    return FunctionCallExpression(_f1428, _f1431, _f1432, _f1434, _f1435);
}

_m_NamedArgumentExpression_write(out: RecordOut, value: NamedArgumentExpression) {
    out.text(value.name);
    _m_Expression_write(out, value.value);
    out.loc(value.loc);
}

_m_NamedArgumentExpression_read(input: RecordIn): NamedArgumentExpression {
    var _f1436 = input.text();
    var _f1437 = _m_Expression_read(input);
    var _f1438 = input.loc();
    return NamedArgumentExpression(_f1437, _f1436, _f1438);
}

_m_DefaultArgumentExpression_write(out: RecordOut, value: DefaultArgumentExpression) {
    _m_TypeName_write(out, value.ty);
}

_m_DefaultArgumentExpression_read(input: RecordIn): DefaultArgumentExpression {
    var _f1439 = _m_TypeName_read(input);
    return DefaultArgumentExpression(_f1439);
}

_m_MethodCallExpression_write(out: RecordOut, value: MethodCallExpression) {
    _m_Expression_write(out, value.this_value);
    out.text(value.method);
    out.unsigned(value.args.count);
    for (var _item1440 in value.args) {
        _m_Expression_write(out, _item1440);
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
    var _f1441 = _m_Expression_read(input);
    var _f1442 = input.text();
    var _v1443 = Array<Expression>();
    var _n1444 = input.count();
    for (var _ in 0.._n1444) {
        _v1443.append(_m_Expression_read(input));
    }
    var _f1445 = _v1443;
    var _f1446 = input.loc();
    var _o1447 = Optional<TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o1447 = Optional<TypeName>.Value(_m_TypeName_read(input));
    }
    var _f1448 = _o1447;
    return MethodCallExpression(_f1441, _f1442, _f1445, _f1446, _f1448);
}

_m_FunctionRefExpression_write(out: RecordOut, value: FunctionRefExpression) {
    out.text(value.function);
    _m_TypeName_write(out, value.ty);
    out.loc(value.loc);
}

_m_FunctionRefExpression_read(input: RecordIn): FunctionRefExpression {
    var _f1449 = input.text();
    var _f1450 = _m_TypeName_read(input);
    var _f1451 = input.loc();
    return FunctionRefExpression(_f1449, _f1450, _f1451);
}

_m_InvokeExpression_write(out: RecordOut, value: InvokeExpression) {
    _m_Expression_write(out, value.callee);
    out.unsigned(value.args.count);
    for (var _item1452 in value.args) {
        _m_Expression_write(out, _item1452);
    }
}

_m_InvokeExpression_read(input: RecordIn): InvokeExpression {
    var _f1453 = _m_Expression_read(input);
    var _v1454 = Array<Expression>();
    var _n1455 = input.count();
    for (var _ in 0.._n1455) {
        _v1454.append(_m_Expression_read(input));
    }
    var _f1456 = _v1454;
    return InvokeExpression(_f1453, _f1456);
}

_m_MakeClosureExpression_write(out: RecordOut, value: MakeClosureExpression) {
    _m_Expression_write(out, value.value);
    out.text(value.closure);
    _m_TypeName_write(out, value.ty);
    out.loc(value.loc);
}

_m_MakeClosureExpression_read(input: RecordIn): MakeClosureExpression {
    var _f1458 = _m_Expression_read(input);
    var _f1459 = input.text();
    var _f1460 = _m_TypeName_read(input);
    var _f1461 = input.loc();
    return MakeClosureExpression(_f1458, _f1459, _f1460, _f1461);
}

_m_CallPointerExpression_write(out: RecordOut, value: CallPointerExpression) {
    _m_Expression_write(out, value.pointer);
    out.unsigned(value.args.count);
    for (var _item1463 in value.args) {
        _m_Expression_write(out, _item1463);
    }
}

_m_CallPointerExpression_read(input: RecordIn): CallPointerExpression {
    var _f1464 = _m_Expression_read(input);
    var _v1465 = Array<Expression>();
    var _n1466 = input.count();
    for (var _ in 0.._n1466) {
        _v1465.append(_m_Expression_read(input));
    }
    var _f1467 = _v1465;
    return CallPointerExpression(_f1464, _f1467);
}

_m_MoveExpression_write(out: RecordOut, value: MoveExpression) {
    _m_Expression_write(out, value.value);
    out.loc(value.loc);
}

_m_MoveExpression_read(input: RecordIn): MoveExpression {
    var _f1470 = _m_Expression_read(input);
    var _f1471 = input.loc();
    return MoveExpression(_f1470, _f1471);
}

_m_DestructureExpression_write(out: RecordOut, value: DestructureExpression) {
    _m_Expression_write(out, value.value);
    out.unsigned(value.count);
    out.loc(value.loc);
}

_m_DestructureExpression_read(input: RecordIn): DestructureExpression {
    var _f1472 = _m_Expression_read(input);
    var _f1473 = input.unsigned();
    var _f1474 = input.loc();
    return DestructureExpression(_f1472, _f1473, _f1474);
}

_m_StaticCaseExpression_write(out: RecordOut, value: StaticCaseExpression) {
    _m_TypeName_write(out, value.ty);
    out.signed(value.tag as long);
}

_m_StaticCaseExpression_read(input: RecordIn): StaticCaseExpression {
    var _f1477 = _m_TypeName_read(input);
    var _f1478 = input.signed();
    return StaticCaseExpression(_f1477, _f1478);
}

_m_StaticStringExpression_write(out: RecordOut, value: StaticStringExpression) {
    out.text(value.value);
    out.loc(value.loc);
}

_m_StaticStringExpression_read(input: RecordIn): StaticStringExpression {
    var _f1479 = input.text();
    var _f1480 = input.loc();
    return StaticStringExpression(_f1479, _f1480);
}

_m_SubjectExpression_write(out: RecordOut, value: SubjectExpression) {
    out.unsigned(value.id);
    _m_TypeName_write(out, value.ty);
    out.loc(value.loc);
}

_m_SubjectExpression_read(input: RecordIn): SubjectExpression {
    var _f1482 = input.unsigned();
    var _f1483 = _m_TypeName_read(input);
    var _f1484 = input.loc();
    return SubjectExpression(_f1482, _f1483, _f1484);
}

_m_ToTraitExpression_write(out: RecordOut, value: ToTraitExpression) {
    _m_Expression_write(out, value.value);
    _m_TypeName_write(out, value.from);
    _m_TypeName_write(out, value.to);
    out.loc(value.loc);
}

_m_ToTraitExpression_read(input: RecordIn): ToTraitExpression {
    var _f1485 = _m_Expression_read(input);
    var _f1486 = _m_TypeName_read(input);
    var _f1487 = _m_TypeName_read(input);
    var _f1488 = input.loc();
    return ToTraitExpression(_f1485, _f1486, _f1487, _f1488);
}

_m_FromTraitExpression_write(out: RecordOut, value: FromTraitExpression) {
    _m_Expression_write(out, value.value);
    _m_TypeName_write(out, value.from);
    _m_TypeName_write(out, value.to);
    out.unsigned(value.candidates.count);
    for (var _item1489 in value.candidates) {
        _m_TypeName_write(out, _item1489);
    }
    out.flag(value.test);
    out.loc(value.loc);
}

_m_FromTraitExpression_read(input: RecordIn): FromTraitExpression {
    var _f1490 = _m_Expression_read(input);
    var _f1491 = _m_TypeName_read(input);
    var _f1492 = _m_TypeName_read(input);
    var _v1493 = Array<TypeName>();
    var _n1494 = input.count();
    for (var _ in 0.._n1494) {
        _v1493.append(_m_TypeName_read(input));
    }
    var _f1495 = _v1493;
    var _f1496 = input.flag();
    var _f1497 = input.loc();
    return FromTraitExpression(_f1490, _f1491, _f1492, _f1495, _f1496, _f1497);
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
        BoolLiteral(v0, v1) => {
            out.unsigned(3);
            out.flag(v0);
            out.loc(v1);
        }
        IntLiteral(v0, v1) => {
            out.unsigned(4);
            out.signed(v0 as long);
            out.loc(v1);
        }
        FloatLiteral(v0, v1) => {
            out.unsigned(5);
            out.number(v0);
            out.loc(v1);
        }
        StringLiteral(node) => {
            out.unsigned(6);
            _m_StringLiteralExpression_write(out, node);
        }
        PointerLiteral(v) => {
            out.unsigned(7);
            out.loc(v);
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
        var _f1356 = input.flag();
        var _f1357 = input.loc();
        return Expression.BoolLiteral(_f1356, _f1357);
    }
    if (tag == 4) {
        var _f1358 = input.signed();
        var _f1359 = input.loc();
        return Expression.IntLiteral(_f1358, _f1359);
    }
    if (tag == 5) {
        var _f1360 = input.number();
        var _f1361 = input.loc();
        return Expression.FloatLiteral(_f1360, _f1361);
    }
    if (tag == 6) {
        return Expression.StringLiteral(_m_StringLiteralExpression_read(input));
    }
    if (tag == 7) {
        var _f1365 = input.loc();
        return Expression.PointerLiteral(_f1365);
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
        var _f1387 = _m_TypeName_read(input);
        return Expression.SizeOf(_f1387);
    }
    if (tag == 15) {
        var _f1388 = _m_TypeName_read(input);
        return Expression.IsPod(_f1388);
    }
    if (tag == 16) {
        var _f1389 = _m_TypeName_read(input);
        return Expression.Default(_f1389);
    }
    if (tag == 17) {
        var _f1390 = _m_TypeName_read(input);
        return Expression.Allocate(_f1390);
    }
    if (tag == 18) {
        var _f1391 = _m_TypeName_read(input);
        var _f1392 = _m_Expression_read(input);
        return Expression.RefCount(_f1391, _f1392);
    }
    if (tag == 19) {
        var _f1393 = _m_TypeName_read(input);
        var _f1394 = _m_Expression_read(input);
        return Expression.Address(_f1393, _f1394);
    }
    if (tag == 20) {
        var _f1395 = _m_TypeName_read(input);
        var _f1396 = _m_Expression_read(input);
        return Expression.AtomicLoad(_f1395, _f1396);
    }
    if (tag == 21) {
        var _f1397 = _m_TypeName_read(input);
        var _f1398 = _m_Expression_read(input);
        var _f1399 = _m_Expression_read(input);
        return Expression.AtomicStore(_f1397, _f1398, _f1399);
    }
    if (tag == 22) {
        var _f1400 = _m_Expression_read(input);
        var _f1401 = _m_Expression_read(input);
        return Expression.ConstructAt(_f1400, _f1401);
    }
    if (tag == 23) {
        var _f1402 = _m_TypeName_read(input);
        var _f1403 = _m_Expression_read(input);
        var _f1404 = _m_Expression_read(input);
        var _f1405 = _m_Expression_read(input);
        return Expression.AtomicCmpXchg(_f1402, _f1403, _f1404, _f1405);
    }
    if (tag == 24) {
        var _f1406 = _m_AtomicFetchOp_read(input);
        var _f1407 = _m_TypeName_read(input);
        var _f1408 = _m_Expression_read(input);
        var _f1409 = _m_Expression_read(input);
        return Expression.AtomicFetch(_f1406, _f1407, _f1408, _f1409);
    }
    if (tag == 25) {
        return Expression.Simd(_m_SimdExpression_read(input));
    }
    if (tag == 26) {
        var _f1417 = _m_WeakOp_read(input);
        var _f1418 = _m_TypeName_read(input);
        var _f1419 = _m_Expression_read(input);
        return Expression.Weak(_f1417, _f1418, _f1419);
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
        var _f1457 = _m_ClosureLiteral_read(input);
        return Expression.ClosureLiteral(_f1457);
    }
    if (tag == 36) {
        return Expression.MakeClosure(_m_MakeClosureExpression_read(input));
    }
    if (tag == 37) {
        var _f1462 = input.text();
        return Expression.MethodAddress(_f1462);
    }
    if (tag == 38) {
        return Expression.CallPointer(_m_CallPointerExpression_read(input));
    }
    if (tag == 39) {
        var _f1468 = _m_Expression_read(input);
        return Expression.ForIterator(_f1468);
    }
    if (tag == 40) {
        var _f1469 = _m_Expression_read(input);
        return Expression.WithEntered(_f1469);
    }
    if (tag == 41) {
        return Expression.Move(_m_MoveExpression_read(input));
    }
    if (tag == 42) {
        return Expression.Destructure(_m_DestructureExpression_read(input));
    }
    if (tag == 43) {
        var _f1475 = _m_MatchArmTest_read(input);
        return Expression.MatchArm(_f1475);
    }
    if (tag == 44) {
        var _f1476 = _m_CaseValue_read(input);
        return Expression.CaseValue(_f1476);
    }
    if (tag == 45) {
        return Expression.StaticCase(_m_StaticCaseExpression_read(input));
    }
    if (tag == 46) {
        return Expression.StaticString(_m_StaticStringExpression_read(input));
    }
    if (tag == 47) {
        var _f1481 = _m_WithSubject_read(input);
        return Expression.WithSubject(_f1481);
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
        var _f1498 = _m_StaticValue_read(input);
        return Expression.StaticValue(_f1498);
    }
    if (tag == 53) {
        var _f1499 = _m_StaticMember_read(input);
        return Expression.StaticMember(_f1499);
    }
    input.fail("Expression", tag);
    return _m_Expression_read(input);
}

_m_StaticMember_write(out: RecordOut, value: StaticMember) {
    _a_Expression_write(out, value.member);
    out.text(value.method);
    out.unsigned(value.args.count);
    for (var _item912 in value.args) {
        _m_Expression_write(out, _item912);
    }
    out.loc(value.loc);
    out.unsigned(out.blank_locs ? 0 : value.span.start);
    out.unsigned(out.blank_locs ? 0 : value.span.end);
    out.unsigned(value.argument_spans.count);
    for (var _item913 in value.argument_spans) {
        out.unsigned(out.blank_locs ? 0 : _item913.start);
        out.unsigned(out.blank_locs ? 0 : _item913.end);
    }
}

_m_StaticMember_read(input: RecordIn): StaticMember {
    var _f914 = _a_Expression_read(input);
    var _f915 = input.text();
    var _v916 = Array<Expression>();
    var _n917 = input.count();
    for (var _ in 0.._n917) {
        _v916.append(_m_Expression_read(input));
    }
    var _f918 = _v916;
    var _f919 = input.loc();
    var _s920 = input.unsigned();
    var _f921 = ast.Span(_s920, input.unsigned());
    var _v922 = Array<ast.Span>();
    var _n923 = input.count();
    for (var _ in 0.._n923) {
        var _s924 = input.unsigned();
        _v922.append(ast.Span(_s924, input.unsigned()));
    }
    var _f925 = _v922;
    return StaticMember(_f914, _f915, _f918, _f919, _f921, _f925);
}

_m_StaticValue_write(out: RecordOut, value: StaticValue) {
    _a_Expression_write(out, value.expr);
    out.loc(value.loc);
}

_m_StaticValue_read(input: RecordIn): StaticValue {
    var _f926 = _a_Expression_read(input);
    var _f927 = input.loc();
    return StaticValue(_f926, _f927);
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
    var _f928 = input.unsigned();
    var _f929 = _m_Expression_read(input);
    var _f930 = _m_Expression_read(input);
    var _o931 = Optional<String>.Empty;
    if (input.unsigned() == 1) {
        _o931 = Optional<String>.Value(input.text());
    }
    var _f932 = _o931;
    var _f933 = input.loc();
    return WithSubject(_f929, _f930, _f928, _f932, _f933);
}

_m_CaseValue_write(out: RecordOut, value: CaseValue) {
    _m_Expression_write(out, value.subject);
    out.text(value.name);
    out.unsigned(value.choices.count);
    for (var _item934 in value.choices) {
        _m_CaseChoice_write(out, _item934);
    }
    out.loc(value.loc);
}

_m_CaseValue_read(input: RecordIn): CaseValue {
    var _f935 = _m_Expression_read(input);
    var _f936 = input.text();
    var _v937 = Array<CaseChoice>();
    var _n938 = input.count();
    for (var _ in 0.._n938) {
        _v937.append(_m_CaseChoice_read(input));
    }
    var _f939 = _v937;
    var _f940 = input.loc();
    return CaseValue(_f935, _f936, _f939, _f940);
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
    for (var _item941 in value.bindings) {
        out.loc(_item941);
    }
    out.loc(value.loc);
}

_m_CaseChoice_read(input: RecordIn): CaseChoice {
    var _f942 = input.text();
    var _f943 = input.loc();
    var _o944 = Optional<TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o944 = Optional<TypeName>.Value(_m_TypeName_read(input));
    }
    var _f945 = _o944;
    var _f946 = input.unsigned();
    var _v947 = Array<Loc>();
    var _n948 = input.count();
    for (var _ in 0.._n948) {
        _v947.append(input.loc());
    }
    var _f949 = _v947;
    var _f950 = input.loc();
    return CaseChoice(_f942, _f943, _f945, _f946, _f949, _f950);
}

_m_MatchArmTest_write(out: RecordOut, value: MatchArmTest) {
    _m_Expression_write(out, value.subject);
    out.unsigned(value.patterns.count);
    for (var _item951 in value.patterns) {
        _m_CasePattern_write(out, _item951);
    }
    _m_MatchSite_write(out, value.site);
    out.unsigned(value.element_names.count);
    for (var _item952 in value.element_names) {
        _m_ElementName_write(out, _item952);
    }
    out.flag(value.guarded);
}

_m_MatchArmTest_read(input: RecordIn): MatchArmTest {
    var _f953 = _m_Expression_read(input);
    var _v954 = Array<CasePattern>();
    var _n955 = input.count();
    for (var _ in 0.._n955) {
        _v954.append(_m_CasePattern_read(input));
    }
    var _f956 = _v954;
    var _f957 = _m_MatchSite_read(input);
    var _v958 = Array<ElementName>();
    var _n959 = input.count();
    for (var _ in 0.._n959) {
        _v958.append(_m_ElementName_read(input));
    }
    var _f960 = _v958;
    var _f961 = input.flag();
    return MatchArmTest(_f953, _f956, _f957, _f960, _f961);
}

_m_ElementName_write(out: RecordOut, value: ElementName) {
    out.text(value.name);
    out.loc(value.loc);
    out.flag(value.declared);
    if (value.missing.is_value()) {
        out.unsigned(1);
        var (_t962, _t963) = value.missing.value();
        out.text(_t962);
        out.loc(_t963);
    } else {
        out.unsigned(0);
    }
}

_m_ElementName_read(input: RecordIn): ElementName {
    var _f964 = input.text();
    var _f965 = input.loc();
    var _f966 = input.flag();
    var _o967 = Optional<(String, Loc)>.Empty;
    if (input.unsigned() == 1) {
        var _t968 = input.text();
        var _t969 = input.loc();
        _o967 = Optional<(String, Loc)>.Value((_t968, _t969));
    }
    var _f970 = _o967;
    return ElementName(_f964, _f965, _f966, _f970);
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
    var _f971 = input.unsigned();
    var _f972 = input.loc();
    var _o973 = Optional<Loc>.Empty;
    if (input.unsigned() == 1) {
        _o973 = Optional<Loc>.Value(input.loc());
    }
    var _f974 = _o973;
    var _f975 = input.flag();
    var _f976 = input.flag();
    return MatchSite(_f971, _f972, _f974, _f975, _f976);
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
        for (var _item977 in value.bindings.value()) {
            _m_CasePattern_write(out, _item977);
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
        for (var _item978 in value.elements.value()) {
            _m_CasePattern_write(out, _item978);
        }
    } else {
        out.unsigned(0);
    }
    out.flag(value.range);
    out.flag(value.constant);
    if (value.values.is_value()) {
        out.unsigned(1);
        var (_t979, _t980) = value.values.value();
        out.signed(_t979 as long);
        out.signed(_t980 as long);
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
    var _o981 = Optional<TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o981 = Optional<TypeName>.Value(_m_TypeName_read(input));
    }
    var _f982 = _o981;
    var _f983 = input.text();
    var _f984 = input.loc();
    var _o985 = Optional<Array<CasePattern>>.Empty;
    if (input.unsigned() == 1) {
        var _v986 = Array<CasePattern>();
        var _n987 = input.count();
        for (var _ in 0.._n987) {
            _v986.append(_m_CasePattern_read(input));
        }
        _o985 = Optional<Array<CasePattern>>.Value(_v986);
    }
    var _f988 = _o985;
    var _o989 = Optional<Expression>.Empty;
    if (input.unsigned() == 1) {
        _o989 = Optional<Expression>.Value(_m_Expression_read(input));
    }
    var _f990 = _o989;
    var _o991 = Optional<Array<CasePattern>>.Empty;
    if (input.unsigned() == 1) {
        var _v992 = Array<CasePattern>();
        var _n993 = input.count();
        for (var _ in 0.._n993) {
            _v992.append(_m_CasePattern_read(input));
        }
        _o991 = Optional<Array<CasePattern>>.Value(_v992);
    }
    var _f994 = _o991;
    var _f995 = input.flag();
    var _f996 = input.flag();
    var _o997 = Optional<(long, long)>.Empty;
    if (input.unsigned() == 1) {
        var _t998 = input.signed();
        var _t999 = input.signed();
        _o997 = Optional<(long, long)>.Value((_t998, _t999));
    }
    var _f1000 = _o997;
    var _o1001 = Optional<TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o1001 = Optional<TypeName>.Value(_m_TypeName_read(input));
    }
    var _f1002 = _o1001;
    return CasePattern(_f982, _f983, _f984, _f988, _f990, _f994, _f995, _f996, _f1000, _f1002);
}

_m_ClosureLiteral_write(out: RecordOut, value: ClosureLiteral) {
    out.unsigned(value.parameters.count);
    for (var _item1003 in value.parameters) {
        _m_VariableDef_write(out, _item1003);
    }
    _m_TypeName_write(out, value.ty);
    _m_Block_write(out, value.body);
    out.flag(value.expression_body);
    out.loc(value.loc);
}

_m_ClosureLiteral_read(input: RecordIn): ClosureLiteral {
    var _v1004 = Array<VariableDef>();
    var _n1005 = input.count();
    for (var _ in 0.._n1005) {
        _v1004.append(_m_VariableDef_read(input));
    }
    var _f1006 = _v1004;
    var _f1007 = _m_TypeName_read(input);
    var _f1008 = _m_Block_read(input);
    var _f1009 = input.flag();
    var _f1010 = input.loc();
    return ClosureLiteral(_f1006, _f1007, _f1008, _f1009, _f1010);
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
    for (var _item1011 in value.attributes) {
        _a_Attribute_write(out, _item1011);
    }
    out.loc(value.loc);
    out.loc(value.type_loc);
    out.flag(value.is_const);
}

_m_VariableDef_read(input: RecordIn): VariableDef {
    var _f1012 = input.text();
    var _f1013 = _m_TypeName_read(input);
    var _o1014 = Optional<Expression>.Empty;
    if (input.unsigned() == 1) {
        _o1014 = Optional<Expression>.Value(_m_Expression_read(input));
    }
    var _f1015 = _o1014;
    var _f1016 = input.flag();
    var _f1017 = _m_Kind_read(input);
    var _v1018 = Array<ast.Attribute>();
    var _n1019 = input.count();
    for (var _ in 0.._n1019) {
        _v1018.append(_a_Attribute_read(input));
    }
    var _f1020 = _v1018;
    var _f1021 = input.loc();
    var _f1022 = input.loc();
    var _f1023 = input.flag();
    return VariableDef(_f1012, _f1013, _f1015, _f1016, _f1017, _f1020, _f1021, _f1022, _f1023);
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
    out.text(value.label);
}

_m_LoopBreak_read(input: RecordIn): LoopBreak {
    var _f1024 = _m_LoopBreakKind_read(input);
    var _f1025 = input.text();
    return LoopBreak(_f1024, _f1025);
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
    var _o1026 = Optional<Expression>.Empty;
    if (input.unsigned() == 1) {
        _o1026 = Optional<Expression>.Value(_m_Expression_read(input));
    }
    var _f1027 = _o1026;
    var _f1028 = input.loc();
    return ReturnStatement(_f1027, _f1028);
}

_m_While_write(out: RecordOut, value: While) {
    _m_Expression_write(out, value.condition);
    _m_Block_write(out, value.block);
    out.text(value.label);
}

_m_While_read(input: RecordIn): While {
    var _f1029 = _m_Expression_read(input);
    var _f1030 = _m_Block_read(input);
    var _f1031 = input.text();
    return While(_f1029, _f1030, _f1031);
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
    var _f1032 = _m_Expression_read(input);
    var _f1033 = _m_Block_read(input);
    var _o1034 = Optional<Block>.Empty;
    if (input.unsigned() == 1) {
        _o1034 = Optional<Block>.Value(_m_Block_read(input));
    }
    var _f1035 = _o1034;
    return Branch(_f1032, _f1033, _f1035);
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
        var _f1500 = _m_VariableDef_read(input);
        return Declaration.Variable(_f1500);
    }
    if (tag == 1) {
        var _f1501 = _m_FunctionDef_read(input);
        return Declaration.Function(_f1501);
    }
    if (tag == 2) {
        var _f1502 = _m_StructDef_read(input);
        return Declaration.Struct(_f1502);
    }
    if (tag == 3) {
        var _f1503 = _m_TraitDef_read(input);
        return Declaration.Trait(_f1503);
    }
    if (tag == 4) {
        var _f1504 = _m_ExtensionDef_read(input);
        return Declaration.Extension(_f1504);
    }
    if (tag == 5) {
        var _f1505 = _m_ExternDef_read(input);
        return Declaration.Extern(_f1505);
    }
    if (tag == 6) {
        var _f1506 = _m_TypeAliasDef_read(input);
        return Declaration.TypeAlias(_f1506);
    }
    input.fail("Declaration", tag);
    return _m_Declaration_read(input);
}

_m_TypeAliasDef_write(out: RecordOut, value: TypeAliasDef) {
    out.text(value.name);
    out.unsigned(value.generic_params.count);
    for (var _item1036 in value.generic_params) {
        _m_GenericParam_write(out, _item1036);
    }
    _m_TypeName_write(out, value.target);
    out.unsigned(value.attributes.count);
    for (var _item1037 in value.attributes) {
        _a_Attribute_write(out, _item1037);
    }
    out.loc(value.loc);
}

_m_TypeAliasDef_read(input: RecordIn): TypeAliasDef {
    var _f1038 = input.text();
    var _v1039 = Array<GenericParam>();
    var _n1040 = input.count();
    for (var _ in 0.._n1040) {
        _v1039.append(_m_GenericParam_read(input));
    }
    var _f1041 = _v1039;
    var _f1042 = _m_TypeName_read(input);
    var _v1043 = Array<ast.Attribute>();
    var _n1044 = input.count();
    for (var _ in 0.._n1044) {
        _v1043.append(_a_Attribute_read(input));
    }
    var _f1045 = _v1043;
    var _f1046 = input.loc();
    return TypeAliasDef(_f1038, _f1041, _f1042, _f1045, _f1046);
}

_m_GenericParam_write(out: RecordOut, value: GenericParam) {
    out.text(value.name);
    out.loc(value.loc);
    out.unsigned(value.bounds.count);
    for (var _item1047 in value.bounds) {
        _m_Bound_write(out, _item1047);
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
    var _f1048 = input.text();
    var _f1049 = input.loc();
    var _v1050 = Array<Bound>();
    var _n1051 = input.count();
    for (var _ in 0.._n1051) {
        _v1050.append(_m_Bound_read(input));
    }
    var _f1052 = _v1050;
    var _o1053 = Optional<TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o1053 = Optional<TypeName>.Value(_m_TypeName_read(input));
    }
    var _f1054 = _o1053;
    var _f1055 = input.loc();
    var _f1056 = input.flag();
    return GenericParam(_f1048, _f1049, _f1052, _f1054, _f1055, _f1056);
}

_m_Bound_write(out: RecordOut, value: Bound) {
    _m_TypeName_write(out, value.ty);
    out.loc(value.loc);
}

_m_Bound_read(input: RecordIn): Bound {
    var _f1057 = _m_TypeName_read(input);
    var _f1058 = input.loc();
    return Bound(_f1057, _f1058);
}

_m_ExternDef_write(out: RecordOut, value: ExternDef) {
    out.text(value.name);
    _m_TypeName_write(out, value.ty);
    out.unsigned(value.parameters.count);
    for (var _item1059 in value.parameters) {
        _m_VariableDef_write(out, _item1059);
    }
    out.flag(value.is_variadic);
    out.unsigned(value.attributes.count);
    for (var _item1060 in value.attributes) {
        _a_Attribute_write(out, _item1060);
    }
    out.loc(value.loc);
}

_m_ExternDef_read(input: RecordIn): ExternDef {
    var _f1061 = input.text();
    var _f1062 = _m_TypeName_read(input);
    var _v1063 = Array<VariableDef>();
    var _n1064 = input.count();
    for (var _ in 0.._n1064) {
        _v1063.append(_m_VariableDef_read(input));
    }
    var _f1065 = _v1063;
    var _f1066 = input.flag();
    var _v1067 = Array<ast.Attribute>();
    var _n1068 = input.count();
    for (var _ in 0.._n1068) {
        _v1067.append(_a_Attribute_read(input));
    }
    var _f1069 = _v1067;
    var _f1070 = input.loc();
    return ExternDef(_f1061, _f1062, _f1065, _f1066, _f1069, _f1070);
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
    for (var _item1071 in value.traits) {
        _m_TypeName_write(out, _item1071);
    }
    out.unsigned(value.trait_locs.count);
    for (var _item1072 in value.trait_locs) {
        out.loc(_item1072);
    }
    out.unsigned(value.restated.count);
    for (var _item1073 in value.restated) {
        var (_t1074, _t1075) = _item1073;
        out.unsigned(_t1074);
        _m_Bound_write(out, _t1075);
    }
    out.unsigned(value.methods.count);
    for (var _item1076 in value.methods) {
        _m_FunctionDef_write(out, _item1076);
    }
    out.unsigned(value.attributes.count);
    for (var _item1077 in value.attributes) {
        _a_Attribute_write(out, _item1077);
    }
    out.loc(value.loc);
    out.flag(value.is_exported);
    out.flag(value.is_private);
}

_m_ExtensionDef_read(input: RecordIn): ExtensionDef {
    var _f1078 = _m_TypeName_read(input);
    var _o1079 = Optional<String>.Empty;
    if (input.unsigned() == 1) {
        _o1079 = Optional<String>.Value(input.text());
    }
    var _f1080 = _o1079;
    var _v1081 = Array<TypeName>();
    var _n1082 = input.count();
    for (var _ in 0.._n1082) {
        _v1081.append(_m_TypeName_read(input));
    }
    var _f1083 = _v1081;
    var _v1084 = Array<Loc>();
    var _n1085 = input.count();
    for (var _ in 0.._n1085) {
        _v1084.append(input.loc());
    }
    var _f1086 = _v1084;
    var _v1087 = Array<(ulong, Bound)>();
    var _n1088 = input.count();
    for (var _ in 0.._n1088) {
        var _t1089 = input.unsigned();
        var _t1090 = _m_Bound_read(input);
        _v1087.append((_t1089, _t1090));
    }
    var _f1091 = _v1087;
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
    var _f1099 = input.flag();
    var _f1100 = input.flag();
    return ExtensionDef(_f1078, _f1080, _f1083, _f1086, _f1091, _f1094, _f1097, _f1098, _f1099, _f1100);
}

_m_TraitDef_write(out: RecordOut, value: TraitDef) {
    out.text(value.name);
    out.unsigned(value.generic_params.count);
    for (var _item1101 in value.generic_params) {
        _m_GenericParam_write(out, _item1101);
    }
    out.unsigned(value.methods.count);
    for (var _item1102 in value.methods) {
        _m_FunctionDef_write(out, _item1102);
    }
    out.unsigned(value.attributes.count);
    for (var _item1103 in value.attributes) {
        _a_Attribute_write(out, _item1103);
    }
    out.loc(value.loc);
}

_m_TraitDef_read(input: RecordIn): TraitDef {
    var _f1104 = input.text();
    var _v1105 = Array<GenericParam>();
    var _n1106 = input.count();
    for (var _ in 0.._n1106) {
        _v1105.append(_m_GenericParam_read(input));
    }
    var _f1107 = _v1105;
    var _v1108 = Array<FunctionDef>();
    var _n1109 = input.count();
    for (var _ in 0.._n1109) {
        _v1108.append(_m_FunctionDef_read(input));
    }
    var _f1110 = _v1108;
    var _v1111 = Array<ast.Attribute>();
    var _n1112 = input.count();
    for (var _ in 0.._n1112) {
        _v1111.append(_a_Attribute_read(input));
    }
    var _f1113 = _v1111;
    var _f1114 = input.loc();
    return TraitDef(_f1104, _f1107, _f1110, _f1113, _f1114);
}

_m_StructDef_write(out: RecordOut, value: StructDef) {
    out.text(value.name);
    _m_TypeName_write(out, value.ty);
    out.unsigned(value.generic_params.count);
    for (var _item1115 in value.generic_params) {
        _m_GenericParam_write(out, _item1115);
    }
    out.unsigned(value.field_members.count);
    for (var _item1116 in value.field_members) {
        _m_VariableDef_write(out, _item1116);
    }
    out.unsigned(value.method_members.count);
    for (var _item1117 in value.method_members) {
        _m_FunctionDef_write(out, _item1117);
    }
    out.unsigned(value.generic_methods.count);
    for (var _item1118 in value.generic_methods) {
        _m_FunctionDef_write(out, _item1118);
    }
    out.unsigned(value.constructors.count);
    for (var _item1119 in value.constructors) {
        _m_FunctionDef_write(out, _item1119);
    }
    _m_FunctionDef_write(out, value.destructor);
    _m_FunctionDef_write(out, value.acquire);
    _m_FunctionDef_write(out, value.release);
    out.unsigned(value.traits.count);
    for (var _item1120 in value.traits) {
        _m_TypeName_write(out, _item1120);
    }
    out.unsigned(value.attributes.count);
    for (var _item1121 in value.attributes) {
        _a_Attribute_write(out, _item1121);
    }
    out.loc(value.loc);
    if (value.enum_cases.is_value()) {
        out.unsigned(1);
        out.unsigned(value.enum_cases.value().count);
        for (var _item1122 in value.enum_cases.value()) {
            _m_EnumCaseDef_write(out, _item1122);
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
    var _f1123 = input.text();
    var _f1124 = _m_TypeName_read(input);
    var _v1125 = Array<GenericParam>();
    var _n1126 = input.count();
    for (var _ in 0.._n1126) {
        _v1125.append(_m_GenericParam_read(input));
    }
    var _f1127 = _v1125;
    var _v1128 = Array<VariableDef>();
    var _n1129 = input.count();
    for (var _ in 0.._n1129) {
        _v1128.append(_m_VariableDef_read(input));
    }
    var _f1130 = _v1128;
    var _v1131 = Array<FunctionDef>();
    var _n1132 = input.count();
    for (var _ in 0.._n1132) {
        _v1131.append(_m_FunctionDef_read_with(input, lazy));
    }
    var _f1133 = _v1131;
    var _v1134 = Array<FunctionDef>();
    var _n1135 = input.count();
    for (var _ in 0.._n1135) {
        _v1134.append(_m_FunctionDef_read(input));
    }
    var _f1136 = _v1134;
    var _v1137 = Array<FunctionDef>();
    var _n1138 = input.count();
    for (var _ in 0.._n1138) {
        _v1137.append(_m_FunctionDef_read_with(input, lazy));
    }
    var _f1139 = _v1137;
    var _f1140 = _m_FunctionDef_read_with(input, lazy);
    var _f1141 = _m_FunctionDef_read_with(input, lazy);
    var _f1142 = _m_FunctionDef_read_with(input, lazy);
    var _v1143 = Array<TypeName>();
    var _n1144 = input.count();
    for (var _ in 0.._n1144) {
        _v1143.append(_m_TypeName_read(input));
    }
    var _f1145 = _v1143;
    var _v1146 = Array<ast.Attribute>();
    var _n1147 = input.count();
    for (var _ in 0.._n1147) {
        _v1146.append(_a_Attribute_read(input));
    }
    var _f1148 = _v1146;
    var _f1149 = input.loc();
    var _o1150 = Optional<Array<EnumCaseDef>>.Empty;
    if (input.unsigned() == 1) {
        var _v1151 = Array<EnumCaseDef>();
        var _n1152 = input.count();
        for (var _ in 0.._n1152) {
            _v1151.append(_m_EnumCaseDef_read(input));
        }
        _o1150 = Optional<Array<EnumCaseDef>>.Value(_v1151);
    }
    var _f1153 = _o1150;
    return StructDef(
        _f1123, _f1124, _f1127, _f1130, _f1133, _f1136, _f1139, _f1140, _f1141, _f1142, _f1145, _f1148, _f1149, _f1153
    );
}

_m_EnumCaseDef_write(out: RecordOut, value: EnumCaseDef) {
    out.text(value.name);
    out.signed(value.value as long);
    out.unsigned(value.payload.count);
    for (var _item1154 in value.payload) {
        var (_t1155, _t1156) = _item1154;
        out.text(_t1155);
        out.loc(_t1156);
    }
    out.unsigned(value.attributes.count);
    for (var _item1157 in value.attributes) {
        _a_Attribute_write(out, _item1157);
    }
    out.loc(value.loc);
}

_m_EnumCaseDef_read(input: RecordIn): EnumCaseDef {
    var _f1158 = input.text();
    var _f1159 = input.signed();
    var _v1160 = Array<(String, Loc)>();
    var _n1161 = input.count();
    for (var _ in 0.._n1161) {
        var _t1162 = input.text();
        var _t1163 = input.loc();
        _v1160.append((_t1162, _t1163));
    }
    var _f1164 = _v1160;
    var _v1165 = Array<ast.Attribute>();
    var _n1166 = input.count();
    for (var _ in 0.._n1166) {
        _v1165.append(_a_Attribute_read(input));
    }
    var _f1167 = _v1165;
    var _f1168 = input.loc();
    return EnumCaseDef(_f1158, _f1159, _f1164, _f1167, _f1168);
}

_m_ExtensionScopes_write(out: RecordOut, value: ExtensionScopes) {
    var _keys1170 = Array<(u8[], u8[], uint)>();
    for (var _key1169 in value.prelude) {
        var _scratch1171 = out.scratch();
        _scratch1171.unsigned(_key1169 as ulong);
        var _vscratch1173 = out.scratch();
        _keys1170.append((_scratch1171.finish(), _vscratch1173.finish(), _key1169));
    }
    _keys1170.sort((a, b) => {
        var (x, xv, _) = a;
        var (y, yv, _) = b;
        var by_key = compare_bytes(x, y);
        return by_key != 0 ? by_key : compare_bytes(xv, yv);
    });
    out.unsigned(_keys1170.count);
    for (var (_bytes1172, _, _key1169) in _keys1170) {
        out.unsigned(_key1169 as ulong);
    }
    out.unsigned(value.visible.count);
    for (var _item1174 in value.visible) {
        var _keys1176 = Array<(u8[], u8[], uint)>();
        for (var _key1175 in _item1174) {
            var _scratch1177 = out.scratch();
            _scratch1177.unsigned(_key1175 as ulong);
            var _vscratch1179 = out.scratch();
            _keys1176.append((_scratch1177.finish(), _vscratch1179.finish(), _key1175));
        }
        _keys1176.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1176.count);
        for (var (_bytes1178, _, _key1175) in _keys1176) {
            out.unsigned(_key1175 as ulong);
        }
    }
    out.unsigned(value.module.count);
    for (var _item1180 in value.module) {
        if (_item1180.is_value()) {
            out.unsigned(1);
            out.unsigned(_item1180.value() as ulong);
        } else {
            out.unsigned(0);
        }
    }
}

_m_ExtensionScopes_read(input: RecordIn): ExtensionScopes {
    var _v1181 = HashSet<uint>();
    var _n1182 = input.count();
    for (var _ in 0.._n1182) {
        _v1181.insert(input.unsigned() as uint);
    }
    var _f1183 = _v1181;
    var _v1184 = Array<HashSet<uint>>();
    var _n1185 = input.count();
    for (var _ in 0.._n1185) {
        var _v1186 = HashSet<uint>();
        var _n1187 = input.count();
        for (var _ in 0.._n1187) {
            _v1186.insert(input.unsigned() as uint);
        }
        _v1184.append(_v1186);
    }
    var _f1188 = _v1184;
    var _v1189 = Array<Optional<uint>>();
    var _n1190 = input.count();
    for (var _ in 0.._n1190) {
        var _o1191 = Optional<uint>.Empty;
        if (input.unsigned() == 1) {
            _o1191 = Optional<uint>.Value(input.unsigned() as uint);
        }
        _v1189.append(_o1191);
    }
    var _f1192 = _v1189;
    return ExtensionScopes(_f1183, _f1188, _f1192);
}

_m_Conversion_write(out: RecordOut, value: Conversion) {
    out.loc(value.at);
    _m_TypeName_write(out, value.from);
    _m_TypeName_write(out, value.to);
    out.loc(value.constructor);
}

_m_Conversion_read(input: RecordIn): Conversion {
    var _f1193 = input.loc();
    var _f1194 = _m_TypeName_read(input);
    var _f1195 = _m_TypeName_read(input);
    var _f1196 = input.loc();
    return Conversion(_f1193, _f1194, _f1195, _f1196);
}

_m_TraitType_write(out: RecordOut, value: TraitType) {
    _m_TypeName_write(out, value.ty);
    out.unsigned(value.methods.count);
    for (var _item1197 in value.methods) {
        _m_FunctionDef_write(out, _item1197);
    }
}

_m_TraitType_read(input: RecordIn): TraitType {
    var _f1198 = _m_TypeName_read(input);
    var _v1199 = Array<FunctionDef>();
    var _n1200 = input.count();
    for (var _ in 0.._n1200) {
        _v1199.append(_m_FunctionDef_read(input));
    }
    var _f1201 = _v1199;
    return TraitType(_f1198, _f1201);
}

_m_UseContext_write(out: RecordOut, value: UseContext) {
    out.unsigned(value.scope.count);
    for (var _item1202 in value.scope) {
        _m_GenericParam_write(out, _item1202);
    }
    if (value.extension.is_value()) {
        out.unsigned(1);
        _m_TypeName_write(out, value.extension.value());
    } else {
        out.unsigned(0);
    }
    out.unsigned(value.conditions.count);
    for (var _item1203 in value.conditions) {
        _a_Attribute_write(out, _item1203);
    }
}

_m_UseContext_read(input: RecordIn): UseContext {
    var _v1204 = Array<GenericParam>();
    var _n1205 = input.count();
    for (var _ in 0.._n1205) {
        _v1204.append(_m_GenericParam_read(input));
    }
    var _f1206 = _v1204;
    var _o1207 = Optional<TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o1207 = Optional<TypeName>.Value(_m_TypeName_read(input));
    }
    var _f1208 = _o1207;
    var _v1209 = Array<ast.Attribute>();
    var _n1210 = input.count();
    for (var _ in 0.._n1210) {
        _v1209.append(_a_Attribute_read(input));
    }
    var _f1211 = _v1209;
    return UseContext(_f1206, _f1208, _f1211);
}

_m_TypeUse_write(out: RecordOut, value: TypeUse) {
    _m_TypeName_write(out, value.ty);
    out.unsigned(value.args.count);
    for (var _item1212 in value.args) {
        out.loc(_item1212);
    }
    out.unsigned(value.context);
}

_m_TypeUse_read(input: RecordIn): TypeUse {
    var _f1213 = _m_TypeName_read(input);
    var _v1214 = Array<Loc>();
    var _n1215 = input.count();
    for (var _ in 0.._n1215) {
        _v1214.append(input.loc());
    }
    var _f1216 = _v1214;
    var _f1217 = input.unsigned();
    return TypeUse(_f1213, _f1216, _f1217);
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
    var _f1218 = input.text();
    var _f1219 = input.text();
    var _f1220 = input.flag();
    var _f1221 = input.loc();
    var _f1222 = _m_AccessorKind_read(input);
    var _o1223 = Optional<AccessorKind>.Empty;
    if (input.unsigned() == 1) {
        _o1223 = Optional<AccessorKind>.Value(_m_AccessorKind_read(input));
    }
    var _f1224 = _o1223;
    var _f1225 = input.loc();
    var _o1226 = Optional<String>.Empty;
    if (input.unsigned() == 1) {
        _o1226 = Optional<String>.Value(input.text());
    }
    var _f1227 = _o1226;
    var _f1228 = input.flag();
    return PropertyDef(_f1218, _f1219, _f1220, _f1221, _f1222, _f1224, _f1225, _f1227, _f1228);
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
    var _f1229 = input.text();
    var _f1230 = input.text();
    var _f1231 = input.text();
    var _f1232 = input.unsigned();
    var _f1233 = _m_TypeName_read(input);
    var _f1234 = _m_TypeName_read(input);
    var _f1235 = input.loc();
    return Withheld(_f1229, _f1230, _f1231, _f1232, _f1233, _f1234, _f1235);
}

_m_EnumDef_write(out: RecordOut, value: EnumDef) {
    out.text(value.name);
    _m_TypeName_write(out, value.representation);
    out.unsigned(value.cases.count);
    for (var _item1236 in value.cases) {
        _m_EnumCaseDef_write(out, _item1236);
    }
    out.unsigned(value.attributes.count);
    for (var _item1237 in value.attributes) {
        _a_Attribute_write(out, _item1237);
    }
    out.loc(value.loc);
}

_m_EnumDef_read(input: RecordIn): EnumDef {
    var _f1238 = input.text();
    var _f1239 = _m_TypeName_read(input);
    var _v1240 = Array<EnumCaseDef>();
    var _n1241 = input.count();
    for (var _ in 0.._n1241) {
        _v1240.append(_m_EnumCaseDef_read(input));
    }
    var _f1242 = _v1240;
    var _v1243 = Array<ast.Attribute>();
    var _n1244 = input.count();
    for (var _ in 0.._n1244) {
        _v1243.append(_a_Attribute_read(input));
    }
    var _f1245 = _v1243;
    var _f1246 = input.loc();
    return EnumDef(_f1238, _f1239, _f1242, _f1245, _f1246);
}

_m_ModuleStaticBlock_write(out: RecordOut, value: ModuleStaticBlock) {
    _m_StaticBlock_write(out, value.block);
    out.unsigned(value.constants.count);
    for (var _item1247 in value.constants) {
        var (_t1248, _t1249) = _item1247;
        out.text(_t1248);
        out.loc(_t1249);
    }
}

_m_ModuleStaticBlock_read(input: RecordIn): ModuleStaticBlock {
    var _f1250 = _m_StaticBlock_read(input);
    var _v1251 = Array<(String, Loc)>();
    var _n1252 = input.count();
    for (var _ in 0.._n1252) {
        var _t1253 = input.text();
        var _t1254 = input.loc();
        _v1251.append((_t1253, _t1254));
    }
    var _f1255 = _v1251;
    return ModuleStaticBlock(_f1250, _f1255);
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
        for (var _item1256 in value.symbols.value()) {
            _a_ImportedSymbol_write(out, _item1256);
        }
    } else {
        out.unsigned(0);
    }
    out.flag(value.reexport);
    out.unsigned(value.attributes.count);
    for (var _item1257 in value.attributes) {
        _a_Attribute_write(out, _item1257);
    }
    out.unsigned(out.blank_locs ? 0 : value.span.start);
    out.unsigned(out.blank_locs ? 0 : value.span.end);
}

_a_Import_read(input: RecordIn): ast.Import {
    var _f1258 = input.text();
    var _s1259 = input.unsigned();
    var _f1260 = ast.Span(_s1259, input.unsigned());
    var _o1261 = Optional<String>.Empty;
    if (input.unsigned() == 1) {
        _o1261 = Optional<String>.Value(input.text());
    }
    var _f1262 = _o1261;
    var _f1263 = input.flag();
    var _o1264 = Optional<Array<ast.ImportedSymbol>>.Empty;
    if (input.unsigned() == 1) {
        var _v1265 = Array<ast.ImportedSymbol>();
        var _n1266 = input.count();
        for (var _ in 0.._n1266) {
            _v1265.append(_a_ImportedSymbol_read(input));
        }
        _o1264 = Optional<Array<ast.ImportedSymbol>>.Value(_v1265);
    }
    var _f1267 = _o1264;
    var _f1268 = input.flag();
    var _v1269 = Array<ast.Attribute>();
    var _n1270 = input.count();
    for (var _ in 0.._n1270) {
        _v1269.append(_a_Attribute_read(input));
    }
    var _f1271 = _v1269;
    var _s1272 = input.unsigned();
    var _f1273 = ast.Span(_s1272, input.unsigned());
    var value = ast.Import();
    value.name = _f1258;
    value.name_span = _f1260;
    value.alias = _f1262;
    value.is_local = _f1263;
    value.symbols = _f1267;
    value.reexport = _f1268;
    value.attributes = _f1271;
    value.span = _f1273;
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
    var _f1274 = input.text();
    var _s1275 = input.unsigned();
    var _f1276 = ast.Span(_s1275, input.unsigned());
    var _o1277 = Optional<String>.Empty;
    if (input.unsigned() == 1) {
        _o1277 = Optional<String>.Value(input.text());
    }
    var _f1278 = _o1277;
    var _s1279 = input.unsigned();
    var _f1280 = ast.Span(_s1279, input.unsigned());
    var value = ast.ImportedSymbol();
    value.name = _f1274;
    value.name_span = _f1276;
    value.alias = _f1278;
    value.span = _f1280;
    return value;
}

_m_Module_write_delta(out: RecordOut, value: Module, base: DeltaBase) {
    ulong _mark = out.values.count;
    var _hs1512 = Array<String>();
    for (var _item1507 in value.imports) {
        var scratch = base.scratch();
        _a_Import_write(scratch, _item1507);
        _hs1512.append(base.hash_of(scratch));
    }
    var _seq1513 = base.sequence("imports");
    ulong _bj1514 = 0;
    var _news1515 = Array<ulong>();
    for (var _i1516 in 0.._hs1512.count) {
        if (_bj1514 < _seq1513.count and _hs1512[_i1516] == _seq1513[_bj1514]) {
            _bj1514 += 1;
        } else {
            _news1515.append(_i1516);
        }
    }
    if (_bj1514 == _seq1513.count) {
        out.unsigned(2);
        out.unsigned(_news1515.count);
        for (var _i1516 in _news1515) {
            out.unsigned(_i1516);
            _a_Import_write(out, value.imports[_i1516]);
            {
                var _own1517 = RecordOut();
                _own1517.blank_bodies = true;
                _own1517.blank_locs = true;
                _own1517.pending_as_bytes = true;
                _a_Import_write(_own1517, value.imports[_i1516]);
                base.own("imports", interface_text(_own1517));
            }
        }
        base.count("imports" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("imports" + " whole", 0);
        out.unsigned(value.imports.count);
        for (var _i1516 in 0..value.imports.count) {
            _a_Import_write(out, value.imports[_i1516]);
            {
                var _own1518 = RecordOut();
                _own1518.blank_bodies = true;
                _own1518.blank_locs = true;
                _own1518.pending_as_bytes = true;
                _a_Import_write(_own1518, value.imports[_i1516]);
                base.own("imports", interface_text(_own1518));
            }
        }
    }
    base.stat("imports", out.values.count - _mark);
    _mark = out.values.count;
    var _seq1528 = base.ref_structs;
    ulong _bj1529 = 0;
    var _news1531 = Array<ulong>();
    var _patches1532 = Array<(ulong, ulong)>();
    for (var _i1533 in 0..value.structs.count) {
        if (_bj1529 < _seq1528.count
            and value.structs[_i1533] === _seq1528[_bj1529]
            and !value.extended_checked.contains(value.structs[_i1533].name)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_StructDef_write(scratch, value.structs[_i1533]);
                base.verify_same("s", _bj1529, scratch, value.structs[_i1533].name);
            }
            _bj1529 += 1;
        } else if (_bj1529 < _seq1528.count
            and !(value.structs[_i1533] === _seq1528[_bj1529])
            and _same_m_StructDef(value.structs[_i1533], _seq1528[_bj1529], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_StructDef_write(scratch, value.structs[_i1533]);
                base.verify_same("s", _bj1529, scratch, value.structs[_i1533].name);
            }
            _bj1529 += 1;
        } else if (_bj1529 < _seq1528.count and value.structs[_i1533].name == _seq1528[_bj1529].name) {
            _patches1532.append((_i1533, _bj1529));
            _bj1529 += 1;
        } else {
            _news1531.append(_i1533);
        }
    }
    if (_bj1529 == _seq1528.count) {
        out.unsigned(2);
        out.unsigned(_patches1532.count);
        for (var (_i1533, _b) in _patches1532) {
            ulong _before = out.values.count;
            out.text(value.structs[_i1533].name);
            out.unsigned(_b);
            _patch_s_write(out, value.structs[_i1533], base, _b);
            base.count("s patched", out.values.count - _before);
            {
                var _own1534 = RecordOut();
                _own1534.blank_bodies = true;
                _own1534.blank_locs = true;
                _own1534.pending_as_bytes = true;
                var _s1535 = value.structs[_i1533];
                var _methods1536 = _s1535.method_members;
                _s1535.method_members = Array<FunctionDef>();
                var _fields1537 = _s1535.field_members;
                var split__fields1537 = splits_fields(_s1535);
                if (split__fields1537) {
                    _s1535.field_members = Array<VariableDef>();
                }
                _m_StructDef_write(_own1534, _s1535);
                _s1535.method_members = _methods1536;
                _s1535.field_members = _fields1537;
                base.own_named("structs", _s1535.name, interface_text(_own1534));
                for (var _m1538 in _methods1536) {
                    var _own1539 = RecordOut();
                    _own1539.blank_bodies = true;
                    _own1539.blank_locs = true;
                    _own1539.pending_as_bytes = true;
                    _m_FunctionDef_write(_own1539, _m1538);
                    base.own_method("structs", _s1535.name, _m1538.name, interface_text(_own1539));
                }
                if (_s1535.is_value()) {
                    for (var _m1538 in _s1535.constructors) {
                        var _own1539 = RecordOut();
                        _own1539.blank_locs = true;
                        _own1539.pending_as_bytes = true;
                        _m_FunctionDef_write(_own1539, _m1538);
                        base.own_method("structs", _s1535.name, "__ctor", interface_text(_own1539));
                    }
                }
                if (split__fields1537) {
                    var _order1541 = StringBuilder();
                    for (var _f1540 in _fields1537) {
                        var _own1542 = RecordOut();
                        _own1542.blank_locs = true;
                        _m_VariableDef_write(_own1542, _f1540);
                        base.own_method("structs", _s1535.name, "." + _f1540.name, interface_text(_own1542));
                        _order1541.append(_f1540.name);
                        _order1541.append(",");
                    }
                    base.own_method("structs", _s1535.name, ".#order", _order1541.to_string());
                }
            }
        }
        out.unsigned(_news1531.count);
        for (var _i1533 in _news1531) {
            ulong _before = out.values.count;
            out.unsigned(_i1533);
            _m_StructDef_write(out, value.structs[_i1533]);
            base.count("s new", out.values.count - _before);
            {
                var _own1543 = RecordOut();
                _own1543.blank_bodies = true;
                _own1543.blank_locs = true;
                _own1543.pending_as_bytes = true;
                var _s1544 = value.structs[_i1533];
                var _methods1545 = _s1544.method_members;
                _s1544.method_members = Array<FunctionDef>();
                var _fields1546 = _s1544.field_members;
                var split__fields1546 = splits_fields(_s1544);
                if (split__fields1546) {
                    _s1544.field_members = Array<VariableDef>();
                }
                _m_StructDef_write(_own1543, _s1544);
                _s1544.method_members = _methods1545;
                _s1544.field_members = _fields1546;
                base.own_named("structs", _s1544.name, interface_text(_own1543));
                for (var _m1547 in _methods1545) {
                    var _own1548 = RecordOut();
                    _own1548.blank_bodies = true;
                    _own1548.blank_locs = true;
                    _own1548.pending_as_bytes = true;
                    _m_FunctionDef_write(_own1548, _m1547);
                    base.own_method("structs", _s1544.name, _m1547.name, interface_text(_own1548));
                }
                if (_s1544.is_value()) {
                    for (var _m1547 in _s1544.constructors) {
                        var _own1548 = RecordOut();
                        _own1548.blank_locs = true;
                        _own1548.pending_as_bytes = true;
                        _m_FunctionDef_write(_own1548, _m1547);
                        base.own_method("structs", _s1544.name, "__ctor", interface_text(_own1548));
                    }
                }
                if (split__fields1546) {
                    var _order1550 = StringBuilder();
                    for (var _f1549 in _fields1546) {
                        var _own1551 = RecordOut();
                        _own1551.blank_locs = true;
                        _m_VariableDef_write(_own1551, _f1549);
                        base.own_method("structs", _s1544.name, "." + _f1549.name, interface_text(_own1551));
                        _order1550.append(_f1549.name);
                        _order1550.append(",");
                    }
                    base.own_method("structs", _s1544.name, ".#order", _order1550.to_string());
                }
            }
        }
        base.count("s merged", 0);
    } else {
        out.unsigned(1);
        base.count("s by place", 0);
        var _struct_hits1527 = HashSet<long>();
        var _slots1530 = HashMap<String, long>();
        for (var _i1533 in 0.._seq1528.count) {
            if (!_slots1530.contains(_seq1528[_i1533].name)) {
                _slots1530[_seq1528[_i1533].name] = _i1533 as long;
            }
        }
        out.unsigned(value.structs.count);
        for (var _i1533 in 0..value.structs.count) {
            var _item1526 = value.structs[_i1533];
            var _slot = _slots1530.try_get(_item1526.name);
            long named = _slot.is_value() ? _slot.value() : -1;
            long at = -1;
            if (named >= 0
                and _seq1528[named as ulong] === _item1526
                and !value.extended_checked.contains(_item1526.name)) {
                at = named;
            }
            ulong _before = out.values.count;
            if (at >= 0) {
                _struct_hits1527.insert(at);
                out.unsigned((at as ulong) * 2 + 1);
            } else if (named >= 0) {
                _struct_hits1527.insert(named);
                out.unsigned(2);
                out.unsigned(named as ulong);
                _patch_s_write(out, _item1526, base, named as ulong);
                base.count("s patched", out.values.count - _before);
            } else {
                out.unsigned(0);
                _m_StructDef_write(out, _item1526);
                base.count("s new", out.values.count - _before);
            }
        }
        base.missed("s", "s", _struct_hits1527.count);
    }
    base.stat("structs", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1565 = Array<String>();
    for (var _item1560 in value.traits) {
        var scratch = base.scratch();
        _m_TraitDef_write(scratch, _item1560);
        _hs1565.append(base.hash_of(scratch));
    }
    var _seq1566 = base.sequence("traits");
    ulong _bj1567 = 0;
    var _news1568 = Array<ulong>();
    for (var _i1569 in 0.._hs1565.count) {
        if (_bj1567 < _seq1566.count and _hs1565[_i1569] == _seq1566[_bj1567]) {
            _bj1567 += 1;
        } else {
            _news1568.append(_i1569);
        }
    }
    if (_bj1567 == _seq1566.count) {
        out.unsigned(2);
        out.unsigned(_news1568.count);
        for (var _i1569 in _news1568) {
            out.unsigned(_i1569);
            _m_TraitDef_write(out, value.traits[_i1569]);
            {
                var _own1570 = RecordOut();
                _own1570.blank_bodies = false;
                _own1570.blank_locs = true;
                _own1570.pending_as_bytes = true;
                _m_TraitDef_write(_own1570, value.traits[_i1569]);
                base.own("traits", interface_text(_own1570));
            }
        }
        base.count("traits" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("traits" + " whole", 0);
        out.unsigned(value.traits.count);
        for (var _i1569 in 0..value.traits.count) {
            _m_TraitDef_write(out, value.traits[_i1569]);
            {
                var _own1571 = RecordOut();
                _own1571.blank_bodies = false;
                _own1571.blank_locs = true;
                _own1571.pending_as_bytes = true;
                _m_TraitDef_write(_own1571, value.traits[_i1569]);
                base.own("traits", interface_text(_own1571));
            }
        }
    }
    base.stat("traits", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1584 = Array<String>();
    for (var _item1579 in value.extensions) {
        var scratch = base.scratch();
        _m_ExtensionDef_write(scratch, _item1579);
        _hs1584.append(base.hash_of(scratch));
    }
    var _seq1585 = base.sequence("extensions");
    ulong _bj1586 = 0;
    var _news1587 = Array<ulong>();
    for (var _i1588 in 0.._hs1584.count) {
        if (_bj1586 < _seq1585.count and _hs1584[_i1588] == _seq1585[_bj1586]) {
            _bj1586 += 1;
        } else {
            _news1587.append(_i1588);
        }
    }
    if (_bj1586 == _seq1585.count) {
        out.unsigned(2);
        out.unsigned(_news1587.count);
        for (var _i1588 in _news1587) {
            out.unsigned(_i1588);
            _m_ExtensionDef_write(out, value.extensions[_i1588]);
            {
                var _own1589 = RecordOut();
                _own1589.blank_bodies = true;
                _own1589.blank_locs = true;
                _own1589.pending_as_bytes = true;
                _m_ExtensionDef_write(_own1589, value.extensions[_i1588]);
                base.own("extensions", interface_text(_own1589));
            }
        }
        base.count("extensions" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("extensions" + " whole", 0);
        out.unsigned(value.extensions.count);
        for (var _i1588 in 0..value.extensions.count) {
            _m_ExtensionDef_write(out, value.extensions[_i1588]);
            {
                var _own1590 = RecordOut();
                _own1590.blank_bodies = true;
                _own1590.blank_locs = true;
                _own1590.pending_as_bytes = true;
                _m_ExtensionDef_write(_own1590, value.extensions[_i1588]);
                base.own("extensions", interface_text(_own1590));
            }
        }
    }
    base.stat("extensions", out.values.count - _mark);
    _mark = out.values.count;
    var _seq1603 = base.ref_functions;
    ulong _bj1604 = 0;
    var _news1605 = Array<ulong>();
    var _changed1599 = Array<(ulong, ulong)>();
    for (var _i1606 in 0..value.functions.count) {
        if (_bj1604 < _seq1603.count and value.functions[_i1606] === _seq1603[_bj1604]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.functions[_i1606]);
                base.verify_same("functions", _bj1604, scratch);
            }
            _bj1604 += 1;
        } else if (_bj1604 < _seq1603.count and _same_m_FunctionDef(value.functions[_i1606], _seq1603[_bj1604], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.functions[_i1606]);
                base.verify_same("functions", _bj1604, scratch);
            }
            _bj1604 += 1;
        } else if (_bj1604 < _seq1603.count and value.functions[_i1606].name == _seq1603[_bj1604].name) {
            _changed1599.append((_i1606, _bj1604));
            _bj1604 += 1;
        } else {
            _news1605.append(_i1606);
        }
    }
    if (_bj1604 == _seq1603.count) {
        out.unsigned(2);
        out.unsigned(_changed1599.count);
        for (var (_i1606, _b) in _changed1599) {
            out.text(value.functions[_i1606].name);
            out.unsigned(_b);
            _m_FunctionDef_write(out, value.functions[_i1606]);
            {
                var _own1607 = RecordOut();
                _own1607.blank_bodies = true;
                _own1607.blank_locs = true;
                _own1607.pending_as_bytes = true;
                _m_FunctionDef_write(_own1607, value.functions[_i1606]);
                base.own_function("functions", value.functions[_i1606], interface_text(_own1607));
            }
        }
        base.count("functions" + " changed", _changed1599.count);
        out.unsigned(_news1605.count);
        for (var _i1606 in _news1605) {
            out.unsigned(_i1606);
            _m_FunctionDef_write(out, value.functions[_i1606]);
            {
                var _own1608 = RecordOut();
                _own1608.blank_bodies = true;
                _own1608.blank_locs = true;
                _own1608.pending_as_bytes = true;
                _m_FunctionDef_write(_own1608, value.functions[_i1606]);
                base.own_function("functions", value.functions[_i1606], interface_text(_own1608));
            }
        }
        base.count("functions" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("functions" + " whole", 0);
        out.unsigned(value.functions.count);
        for (var _i1606 in 0..value.functions.count) {
            _m_FunctionDef_write(out, value.functions[_i1606]);
            {
                var _own1609 = RecordOut();
                _own1609.blank_bodies = true;
                _own1609.blank_locs = true;
                _own1609.pending_as_bytes = true;
                _m_FunctionDef_write(_own1609, value.functions[_i1606]);
                base.own_function("functions", value.functions[_i1606], interface_text(_own1609));
            }
        }
    }
    base.stat("functions", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1622 = Array<String>();
    for (var _item1617 in value.externs) {
        var scratch = base.scratch();
        _m_ExternDef_write(scratch, _item1617);
        _hs1622.append(base.hash_of(scratch));
    }
    var _seq1623 = base.sequence("externs");
    ulong _bj1624 = 0;
    var _news1625 = Array<ulong>();
    for (var _i1626 in 0.._hs1622.count) {
        if (_bj1624 < _seq1623.count and _hs1622[_i1626] == _seq1623[_bj1624]) {
            _bj1624 += 1;
        } else {
            _news1625.append(_i1626);
        }
    }
    if (_bj1624 == _seq1623.count) {
        out.unsigned(2);
        out.unsigned(_news1625.count);
        for (var _i1626 in _news1625) {
            out.unsigned(_i1626);
            _m_ExternDef_write(out, value.externs[_i1626]);
            {
                var _own1627 = RecordOut();
                _own1627.blank_bodies = true;
                _own1627.blank_locs = true;
                _own1627.pending_as_bytes = true;
                _m_ExternDef_write(_own1627, value.externs[_i1626]);
                base.own("externs", interface_text(_own1627));
            }
        }
        base.count("externs" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("externs" + " whole", 0);
        out.unsigned(value.externs.count);
        for (var _i1626 in 0..value.externs.count) {
            _m_ExternDef_write(out, value.externs[_i1626]);
            {
                var _own1628 = RecordOut();
                _own1628.blank_bodies = true;
                _own1628.blank_locs = true;
                _own1628.pending_as_bytes = true;
                _m_ExternDef_write(_own1628, value.externs[_i1626]);
                base.own("externs", interface_text(_own1628));
            }
        }
    }
    base.stat("externs", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1641 = Array<String>();
    for (var _item1636 in value.globals) {
        var scratch = base.scratch();
        _m_VariableDef_write(scratch, _item1636);
        _hs1641.append(base.hash_of(scratch));
    }
    var _seq1642 = base.sequence("globals");
    ulong _bj1643 = 0;
    var _news1644 = Array<ulong>();
    for (var _i1645 in 0.._hs1641.count) {
        if (_bj1643 < _seq1642.count and _hs1641[_i1645] == _seq1642[_bj1643]) {
            _bj1643 += 1;
        } else {
            _news1644.append(_i1645);
        }
    }
    if (_bj1643 == _seq1642.count) {
        out.unsigned(2);
        out.unsigned(_news1644.count);
        for (var _i1645 in _news1644) {
            out.unsigned(_i1645);
            _m_VariableDef_write(out, value.globals[_i1645]);
            {
                var _own1646 = RecordOut();
                _own1646.blank_bodies = true;
                _own1646.blank_locs = true;
                _own1646.pending_as_bytes = true;
                _m_VariableDef_write(_own1646, value.globals[_i1645]);
                base.own("globals", interface_text(_own1646));
            }
        }
        base.count("globals" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("globals" + " whole", 0);
        out.unsigned(value.globals.count);
        for (var _i1645 in 0..value.globals.count) {
            _m_VariableDef_write(out, value.globals[_i1645]);
            {
                var _own1647 = RecordOut();
                _own1647.blank_bodies = true;
                _own1647.blank_locs = true;
                _own1647.pending_as_bytes = true;
                _m_VariableDef_write(_own1647, value.globals[_i1645]);
                base.own("globals", interface_text(_own1647));
            }
        }
    }
    base.stat("globals", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1660 = Array<String>();
    for (var _item1655 in value.static_blocks) {
        var scratch = base.scratch();
        _m_ModuleStaticBlock_write(scratch, _item1655);
        _hs1660.append(base.hash_of(scratch));
    }
    var _seq1661 = base.sequence("static_blocks");
    ulong _bj1662 = 0;
    var _news1663 = Array<ulong>();
    for (var _i1664 in 0.._hs1660.count) {
        if (_bj1662 < _seq1661.count and _hs1660[_i1664] == _seq1661[_bj1662]) {
            _bj1662 += 1;
        } else {
            _news1663.append(_i1664);
        }
    }
    if (_bj1662 == _seq1661.count) {
        out.unsigned(2);
        out.unsigned(_news1663.count);
        for (var _i1664 in _news1663) {
            out.unsigned(_i1664);
            _m_ModuleStaticBlock_write(out, value.static_blocks[_i1664]);
            {
                var _own1665 = RecordOut();
                _own1665.blank_bodies = true;
                _own1665.blank_locs = true;
                _own1665.pending_as_bytes = true;
                _m_ModuleStaticBlock_write(_own1665, value.static_blocks[_i1664]);
                base.own("static_blocks", interface_text(_own1665));
            }
        }
        base.count("static_blocks" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("static_blocks" + " whole", 0);
        out.unsigned(value.static_blocks.count);
        for (var _i1664 in 0..value.static_blocks.count) {
            _m_ModuleStaticBlock_write(out, value.static_blocks[_i1664]);
            {
                var _own1666 = RecordOut();
                _own1666.blank_bodies = true;
                _own1666.blank_locs = true;
                _own1666.pending_as_bytes = true;
                _m_ModuleStaticBlock_write(_own1666, value.static_blocks[_i1664]);
                base.own("static_blocks", interface_text(_own1666));
            }
        }
    }
    base.stat("static_blocks", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1679 = Array<String>();
    for (var _item1674 in value.enums) {
        var scratch = base.scratch();
        _m_EnumDef_write(scratch, _item1674);
        _hs1679.append(base.hash_of(scratch));
    }
    var _seq1680 = base.sequence("enums");
    ulong _bj1681 = 0;
    var _news1682 = Array<ulong>();
    for (var _i1683 in 0.._hs1679.count) {
        if (_bj1681 < _seq1680.count and _hs1679[_i1683] == _seq1680[_bj1681]) {
            _bj1681 += 1;
        } else {
            _news1682.append(_i1683);
        }
    }
    if (_bj1681 == _seq1680.count) {
        out.unsigned(2);
        out.unsigned(_news1682.count);
        for (var _i1683 in _news1682) {
            out.unsigned(_i1683);
            _m_EnumDef_write(out, value.enums[_i1683]);
            {
                var _own1684 = RecordOut();
                _own1684.blank_bodies = true;
                _own1684.blank_locs = true;
                _own1684.pending_as_bytes = true;
                _m_EnumDef_write(_own1684, value.enums[_i1683]);
                base.own_named("enums", value.enums[_i1683].name, interface_text(_own1684));
            }
        }
        base.count("enums" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("enums" + " whole", 0);
        out.unsigned(value.enums.count);
        for (var _i1683 in 0..value.enums.count) {
            _m_EnumDef_write(out, value.enums[_i1683]);
            {
                var _own1685 = RecordOut();
                _own1685.blank_bodies = true;
                _own1685.blank_locs = true;
                _own1685.pending_as_bytes = true;
                _m_EnumDef_write(_own1685, value.enums[_i1683]);
                base.own_named("enums", value.enums[_i1683].name, interface_text(_own1685));
            }
        }
    }
    base.stat("enums", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1698 = Array<String>();
    for (var _item1693 in value.struct_specs) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item1693);
        _hs1698.append(base.hash_of(scratch));
    }
    var _seq1699 = base.sequence("struct_specs");
    ulong _bj1700 = 0;
    var _news1701 = Array<ulong>();
    for (var _i1702 in 0.._hs1698.count) {
        if (_bj1700 < _seq1699.count and _hs1698[_i1702] == _seq1699[_bj1700]) {
            _bj1700 += 1;
        } else {
            _news1701.append(_i1702);
        }
    }
    if (_bj1700 == _seq1699.count) {
        out.unsigned(2);
        out.unsigned(_news1701.count);
        for (var _i1702 in _news1701) {
            out.unsigned(_i1702);
            _m_TypeName_write(out, value.struct_specs[_i1702]);
            {
                var _own1703 = RecordOut();
                _own1703.blank_bodies = true;
                _own1703.blank_locs = true;
                _own1703.pending_as_bytes = true;
                _m_TypeName_write(_own1703, value.struct_specs[_i1702]);
                base.own("struct_specs", interface_text(_own1703));
            }
        }
        base.count("struct_specs" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("struct_specs" + " whole", 0);
        out.unsigned(value.struct_specs.count);
        for (var _i1702 in 0..value.struct_specs.count) {
            _m_TypeName_write(out, value.struct_specs[_i1702]);
            {
                var _own1704 = RecordOut();
                _own1704.blank_bodies = true;
                _own1704.blank_locs = true;
                _own1704.pending_as_bytes = true;
                _m_TypeName_write(_own1704, value.struct_specs[_i1702]);
                base.own("struct_specs", interface_text(_own1704));
            }
        }
    }
    base.stat("struct_specs", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1717 = Array<String>();
    for (var _item1712 in value.func_specs) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item1712);
        _hs1717.append(base.hash_of(scratch));
    }
    var _seq1718 = base.sequence("func_specs");
    ulong _bj1719 = 0;
    var _news1720 = Array<ulong>();
    for (var _i1721 in 0.._hs1717.count) {
        if (_bj1719 < _seq1718.count and _hs1717[_i1721] == _seq1718[_bj1719]) {
            _bj1719 += 1;
        } else {
            _news1720.append(_i1721);
        }
    }
    if (_bj1719 == _seq1718.count) {
        out.unsigned(2);
        out.unsigned(_news1720.count);
        for (var _i1721 in _news1720) {
            out.unsigned(_i1721);
            _m_TypeName_write(out, value.func_specs[_i1721]);
            {
                var _own1722 = RecordOut();
                _own1722.blank_bodies = true;
                _own1722.blank_locs = true;
                _own1722.pending_as_bytes = true;
                _m_TypeName_write(_own1722, value.func_specs[_i1721]);
                base.own("func_specs", interface_text(_own1722));
            }
        }
        base.count("func_specs" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("func_specs" + " whole", 0);
        out.unsigned(value.func_specs.count);
        for (var _i1721 in 0..value.func_specs.count) {
            _m_TypeName_write(out, value.func_specs[_i1721]);
            {
                var _own1723 = RecordOut();
                _own1723.blank_bodies = true;
                _own1723.blank_locs = true;
                _own1723.pending_as_bytes = true;
                _m_TypeName_write(_own1723, value.func_specs[_i1721]);
                base.own("func_specs", interface_text(_own1723));
            }
        }
    }
    base.stat("func_specs", out.values.count - _mark);
    _mark = out.values.count;
    var _hits1735 = HashSet<long>();
    out.unsigned(value.type_aliases.count);
    for (var _item1731 in value.type_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1731);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed("type_aliases", hash);
        if (at >= 0) {
            _hits1735.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_TypeAliasDef_write(out, _item1731);
        }
    }
    base.missed("type_aliases", "type_aliases", _hits1735.count);
    base.stat("type_aliases", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1745 = Array<String>();
    for (var _item1740 in value.withheld) {
        var scratch = base.scratch();
        _m_Withheld_write(scratch, _item1740);
        _hs1745.append(base.hash_of(scratch));
    }
    var _seq1746 = base.sequence("withheld");
    ulong _bj1747 = 0;
    var _news1748 = Array<ulong>();
    for (var _i1749 in 0.._hs1745.count) {
        if (_bj1747 < _seq1746.count and _hs1745[_i1749] == _seq1746[_bj1747]) {
            _bj1747 += 1;
        } else {
            _news1748.append(_i1749);
        }
    }
    if (_bj1747 == _seq1746.count) {
        out.unsigned(2);
        out.unsigned(_news1748.count);
        for (var _i1749 in _news1748) {
            out.unsigned(_i1749);
            _m_Withheld_write(out, value.withheld[_i1749]);
            {
                var _own1750 = RecordOut();
                _own1750.blank_bodies = true;
                _own1750.blank_locs = true;
                _own1750.pending_as_bytes = true;
                _m_Withheld_write(_own1750, value.withheld[_i1749]);
                base.own("withheld", interface_text(_own1750));
            }
        }
        base.count("withheld" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("withheld" + " whole", 0);
        out.unsigned(value.withheld.count);
        for (var _i1749 in 0..value.withheld.count) {
            _m_Withheld_write(out, value.withheld[_i1749]);
            {
                var _own1751 = RecordOut();
                _own1751.blank_bodies = true;
                _own1751.blank_locs = true;
                _own1751.pending_as_bytes = true;
                _m_Withheld_write(_own1751, value.withheld[_i1749]);
                base.own("withheld", interface_text(_own1751));
            }
        }
    }
    base.stat("withheld", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1764 = Array<String>();
    for (var _item1759 in value.properties) {
        var scratch = base.scratch();
        _m_PropertyDef_write(scratch, _item1759);
        _hs1764.append(base.hash_of(scratch));
    }
    var _seq1765 = base.sequence("properties");
    ulong _bj1766 = 0;
    var _news1767 = Array<ulong>();
    for (var _i1768 in 0.._hs1764.count) {
        if (_bj1766 < _seq1765.count and _hs1764[_i1768] == _seq1765[_bj1766]) {
            _bj1766 += 1;
        } else {
            _news1767.append(_i1768);
        }
    }
    if (_bj1766 == _seq1765.count) {
        out.unsigned(2);
        out.unsigned(_news1767.count);
        for (var _i1768 in _news1767) {
            out.unsigned(_i1768);
            _m_PropertyDef_write(out, value.properties[_i1768]);
            {
                var _own1769 = RecordOut();
                _own1769.blank_bodies = true;
                _own1769.blank_locs = true;
                _own1769.pending_as_bytes = true;
                _m_PropertyDef_write(_own1769, value.properties[_i1768]);
                base.own("properties", interface_text(_own1769));
            }
        }
        base.count("properties" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("properties" + " whole", 0);
        out.unsigned(value.properties.count);
        for (var _i1768 in 0..value.properties.count) {
            _m_PropertyDef_write(out, value.properties[_i1768]);
            {
                var _own1770 = RecordOut();
                _own1770.blank_bodies = true;
                _own1770.blank_locs = true;
                _own1770.pending_as_bytes = true;
                _m_PropertyDef_write(_own1770, value.properties[_i1768]);
                base.own("properties", interface_text(_own1770));
            }
        }
    }
    base.stat("properties", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1783 = Array<String>();
    for (var _item1778 in value.type_uses) {
        var scratch = base.scratch();
        _m_TypeUse_write(scratch, _item1778);
        _hs1783.append(base.hash_of(scratch));
    }
    var _seq1784 = base.sequence("type_uses");
    ulong _bj1785 = 0;
    var _news1786 = Array<ulong>();
    for (var _i1787 in 0.._hs1783.count) {
        if (_bj1785 < _seq1784.count and _hs1783[_i1787] == _seq1784[_bj1785]) {
            _bj1785 += 1;
        } else {
            _news1786.append(_i1787);
        }
    }
    if (_bj1785 == _seq1784.count) {
        out.unsigned(2);
        out.unsigned(_news1786.count);
        for (var _i1787 in _news1786) {
            out.unsigned(_i1787);
            _m_TypeUse_write(out, value.type_uses[_i1787]);
            {
                var _own1788 = RecordOut();
                _own1788.blank_bodies = true;
                _own1788.blank_locs = true;
                _own1788.pending_as_bytes = true;
                _m_TypeUse_write(_own1788, value.type_uses[_i1787]);
                base.own("type_uses", interface_text(_own1788));
            }
        }
        base.count("type_uses" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("type_uses" + " whole", 0);
        out.unsigned(value.type_uses.count);
        for (var _i1787 in 0..value.type_uses.count) {
            _m_TypeUse_write(out, value.type_uses[_i1787]);
            {
                var _own1789 = RecordOut();
                _own1789.blank_bodies = true;
                _own1789.blank_locs = true;
                _own1789.pending_as_bytes = true;
                _m_TypeUse_write(_own1789, value.type_uses[_i1787]);
                base.own("type_uses", interface_text(_own1789));
            }
        }
    }
    base.stat("type_uses", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1802 = Array<String>();
    for (var _item1797 in value.use_contexts) {
        var scratch = base.scratch();
        _m_UseContext_write(scratch, _item1797);
        _hs1802.append(base.hash_of(scratch));
    }
    var _seq1803 = base.sequence("use_contexts");
    ulong _bj1804 = 0;
    var _news1805 = Array<ulong>();
    for (var _i1806 in 0.._hs1802.count) {
        if (_bj1804 < _seq1803.count and _hs1802[_i1806] == _seq1803[_bj1804]) {
            _bj1804 += 1;
        } else {
            _news1805.append(_i1806);
        }
    }
    if (_bj1804 == _seq1803.count) {
        out.unsigned(2);
        out.unsigned(_news1805.count);
        for (var _i1806 in _news1805) {
            out.unsigned(_i1806);
            _m_UseContext_write(out, value.use_contexts[_i1806]);
            {
                var _own1807 = RecordOut();
                _own1807.blank_bodies = true;
                _own1807.blank_locs = true;
                _own1807.pending_as_bytes = true;
                _m_UseContext_write(_own1807, value.use_contexts[_i1806]);
                base.own("use_contexts", interface_text(_own1807));
            }
        }
        base.count("use_contexts" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("use_contexts" + " whole", 0);
        out.unsigned(value.use_contexts.count);
        for (var _i1806 in 0..value.use_contexts.count) {
            _m_UseContext_write(out, value.use_contexts[_i1806]);
            {
                var _own1808 = RecordOut();
                _own1808.blank_bodies = true;
                _own1808.blank_locs = true;
                _own1808.pending_as_bytes = true;
                _m_UseContext_write(_own1808, value.use_contexts[_i1806]);
                base.own("use_contexts", interface_text(_own1808));
            }
        }
    }
    base.stat("use_contexts", out.values.count - _mark);
    _mark = out.values.count;
    var _n1818 = base.size("literal_args");
    var _scratch1817 = base.scratch();
    if (value.literal_args.count >= _n1818) {
        for (var _i1819 in 0.._n1818) {
            var (_t1820, _t1821, _t1822) = value.literal_args[_i1819];
            _scratch1817.loc(_t1820);
            _scratch1817.unsigned(_t1821);
            _scratch1817.loc(_t1822);
        }
    }
    if (value.literal_args.count >= _n1818 and base.same_list("literal_args", _scratch1817)) {
        out.unsigned(1);
        out.unsigned(_n1818);
        out.unsigned(value.literal_args.count - _n1818);
        for (var _i1819 in _n1818..value.literal_args.count) {
            var (_t1823, _t1824, _t1825) = value.literal_args[_i1819];
            out.loc(_t1823);
            out.unsigned(_t1824);
            out.loc(_t1825);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.literal_args.count);
        for (var _item1826 in value.literal_args) {
            var (_t1827, _t1828, _t1829) = _item1826;
            out.loc(_t1827);
            out.unsigned(_t1828);
            out.loc(_t1829);
        }
        base.count("literal_args whole", 0);
    }
    base.stat("literal_args", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1852 = Array<String>();
    for (var _item1847 in value.constrained_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1847);
        _hs1852.append(base.hash_of(scratch));
    }
    var _seq1853 = base.sequence("constrained_aliases");
    ulong _bj1854 = 0;
    var _news1855 = Array<ulong>();
    for (var _i1856 in 0.._hs1852.count) {
        if (_bj1854 < _seq1853.count and _hs1852[_i1856] == _seq1853[_bj1854]) {
            _bj1854 += 1;
        } else {
            _news1855.append(_i1856);
        }
    }
    if (_bj1854 == _seq1853.count) {
        out.unsigned(2);
        out.unsigned(_news1855.count);
        for (var _i1856 in _news1855) {
            out.unsigned(_i1856);
            _m_TypeAliasDef_write(out, value.constrained_aliases[_i1856]);
            {
                var _own1857 = RecordOut();
                _own1857.blank_bodies = true;
                _own1857.blank_locs = true;
                _own1857.pending_as_bytes = true;
                _m_TypeAliasDef_write(_own1857, value.constrained_aliases[_i1856]);
                base.own("constrained_aliases", interface_text(_own1857));
            }
        }
        base.count("constrained_aliases" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("constrained_aliases" + " whole", 0);
        out.unsigned(value.constrained_aliases.count);
        for (var _i1856 in 0..value.constrained_aliases.count) {
            _m_TypeAliasDef_write(out, value.constrained_aliases[_i1856]);
            {
                var _own1858 = RecordOut();
                _own1858.blank_bodies = true;
                _own1858.blank_locs = true;
                _own1858.pending_as_bytes = true;
                _m_TypeAliasDef_write(_own1858, value.constrained_aliases[_i1856]);
                base.own("constrained_aliases", interface_text(_own1858));
            }
        }
    }
    base.stat("constrained_aliases", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1871 = Array<String>();
    for (var _item1866 in value.trait_types) {
        var scratch = base.scratch();
        _m_TraitType_write(scratch, _item1866);
        _hs1871.append(base.hash_of(scratch));
    }
    var _seq1872 = base.sequence("trait_types");
    ulong _bj1873 = 0;
    var _news1874 = Array<ulong>();
    for (var _i1875 in 0.._hs1871.count) {
        if (_bj1873 < _seq1872.count and _hs1871[_i1875] == _seq1872[_bj1873]) {
            _bj1873 += 1;
        } else {
            _news1874.append(_i1875);
        }
    }
    if (_bj1873 == _seq1872.count) {
        out.unsigned(2);
        out.unsigned(_news1874.count);
        for (var _i1875 in _news1874) {
            out.unsigned(_i1875);
            _m_TraitType_write(out, value.trait_types[_i1875]);
            {
                var _own1876 = RecordOut();
                _own1876.blank_bodies = true;
                _own1876.blank_locs = true;
                _own1876.pending_as_bytes = true;
                _m_TraitType_write(_own1876, value.trait_types[_i1875]);
                base.own("trait_types", interface_text(_own1876));
            }
        }
        base.count("trait_types" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("trait_types" + " whole", 0);
        out.unsigned(value.trait_types.count);
        for (var _i1875 in 0..value.trait_types.count) {
            _m_TraitType_write(out, value.trait_types[_i1875]);
            {
                var _own1877 = RecordOut();
                _own1877.blank_bodies = true;
                _own1877.blank_locs = true;
                _own1877.pending_as_bytes = true;
                _m_TraitType_write(_own1877, value.trait_types[_i1875]);
                base.own("trait_types", interface_text(_own1877));
            }
        }
    }
    base.stat("trait_types", out.values.count - _mark);
    _mark = out.values.count;
    out.unsigned(value.conversions.count);
    for (var _item1885 in value.conversions) {
        _m_Conversion_write(out, _item1885);
    }
    for (var _conv1886 in value.conversions) {
        var _own1887 = RecordOut();
        _own1887.blank_locs = true;
        _m_Conversion_write(_own1887, _conv1886);
        var _h = interface_text(_own1887);
        if (base.find_hashed("conversions", _h) < 0) {
            base.own("conversions", _h);
        }
    }
    base.stat("conversions", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept1895 = 0;
    var _news1896 = Map<String, Array<String>>();
    for (var (_key1892, _) in value.overload_sets) {
        var _kscratch1893 = base.scratch();
        _kscratch1893.text(_key1892);
        var _vscratch1894 = base.scratch();
        _vscratch1894.unsigned(value.overload_sets[_key1892].count);
        for (var _item1897 in value.overload_sets[_key1892]) {
            _vscratch1894.text(_item1897);
        }
        var _had = base.entry("overload_sets", _kscratch1893, _vscratch1894);
        if (_had >= 0) {
            _kept1895 += 1;
        }
        if (_had != 1) {
            _news1896[_key1892] = value.overload_sets[_key1892];
        }
    }
    if (_kept1895 == base.size("overload_sets")) {
        out.unsigned(1);
        var _keys1899 = Array<(u8[], u8[], String)>();
        for (var (_key1898, _) in _news1896) {
            var _scratch1900 = out.scratch();
            _scratch1900.text(_key1898);
            var _vscratch1902 = out.scratch();
            _vscratch1902.unsigned(_news1896[_key1898].count);
            for (var _item1903 in _news1896[_key1898]) {
                _vscratch1902.text(_item1903);
            }
            _keys1899.append((_scratch1900.finish(), _vscratch1902.finish(), _key1898));
        }
        _keys1899.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1899.count);
        for (var (_bytes1901, _, _key1898) in _keys1899) {
            out.text(_key1898);
            out.unsigned(_news1896[_key1898].count);
            for (var _item1904 in _news1896[_key1898]) {
                out.text(_item1904);
            }
        }
        for (var (_okey1905, _) in _news1896) {
            var _own1906 = RecordOut();
            _own1906.blank_bodies = true;
            _own1906.blank_locs = true;
            _own1906.pending_as_bytes = true;
            _own1906.text(_okey1905);
            _own1906.unsigned(_news1896[_okey1905].count);
            for (var _item1907 in _news1896[_okey1905]) {
                _own1906.text(_item1907);
            }
            base.own("overload_sets", interface_text(_own1906));
        }
    } else {
        out.unsigned(0);
        var _keys1909 = Array<(u8[], u8[], String)>();
        for (var (_key1908, _) in value.overload_sets) {
            var _scratch1910 = out.scratch();
            _scratch1910.text(_key1908);
            var _vscratch1912 = out.scratch();
            _vscratch1912.unsigned(value.overload_sets[_key1908].count);
            for (var _item1913 in value.overload_sets[_key1908]) {
                _vscratch1912.text(_item1913);
            }
            _keys1909.append((_scratch1910.finish(), _vscratch1912.finish(), _key1908));
        }
        _keys1909.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1909.count);
        for (var (_bytes1911, _, _key1908) in _keys1909) {
            out.text(_key1908);
            out.unsigned(value.overload_sets[_key1908].count);
            for (var _item1914 in value.overload_sets[_key1908]) {
                out.text(_item1914);
            }
        }
        for (var (_okey1915, _) in value.overload_sets) {
            var _own1916 = RecordOut();
            _own1916.blank_bodies = true;
            _own1916.blank_locs = true;
            _own1916.pending_as_bytes = true;
            _own1916.text(_okey1915);
            _own1916.unsigned(value.overload_sets[_okey1915].count);
            for (var _item1917 in value.overload_sets[_okey1915]) {
                _own1916.text(_item1917);
            }
            base.own("overload_sets", interface_text(_own1916));
        }
        base.count("overload_sets whole", 0);
    }
    base.stat("overload_sets", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept1935 = 0;
    var _news1936 = Map<String, Array<Array<String>>>();
    for (var (_key1932, _) in value.overload_unions) {
        var _kscratch1933 = base.scratch();
        _kscratch1933.text(_key1932);
        var _vscratch1934 = base.scratch();
        _vscratch1934.unsigned(value.overload_unions[_key1932].count);
        for (var _item1937 in value.overload_unions[_key1932]) {
            _vscratch1934.unsigned(_item1937.count);
            for (var _item1938 in _item1937) {
                _vscratch1934.text(_item1938);
            }
        }
        var _had = base.entry("overload_unions", _kscratch1933, _vscratch1934);
        if (_had >= 0) {
            _kept1935 += 1;
        }
        if (_had != 1) {
            _news1936[_key1932] = value.overload_unions[_key1932];
        }
    }
    if (_kept1935 == base.size("overload_unions")) {
        out.unsigned(1);
        var _keys1940 = Array<(u8[], u8[], String)>();
        for (var (_key1939, _) in _news1936) {
            var _scratch1941 = out.scratch();
            _scratch1941.text(_key1939);
            var _vscratch1943 = out.scratch();
            _vscratch1943.unsigned(_news1936[_key1939].count);
            for (var _item1944 in _news1936[_key1939]) {
                _vscratch1943.unsigned(_item1944.count);
                for (var _item1945 in _item1944) {
                    _vscratch1943.text(_item1945);
                }
            }
            _keys1940.append((_scratch1941.finish(), _vscratch1943.finish(), _key1939));
        }
        _keys1940.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1940.count);
        for (var (_bytes1942, _, _key1939) in _keys1940) {
            out.text(_key1939);
            out.unsigned(_news1936[_key1939].count);
            for (var _item1946 in _news1936[_key1939]) {
                out.unsigned(_item1946.count);
                for (var _item1947 in _item1946) {
                    out.text(_item1947);
                }
            }
        }
        for (var (_okey1948, _) in _news1936) {
            var _own1949 = RecordOut();
            _own1949.blank_bodies = true;
            _own1949.blank_locs = true;
            _own1949.pending_as_bytes = true;
            _own1949.text(_okey1948);
            _own1949.unsigned(_news1936[_okey1948].count);
            for (var _item1950 in _news1936[_okey1948]) {
                _own1949.unsigned(_item1950.count);
                for (var _item1951 in _item1950) {
                    _own1949.text(_item1951);
                }
            }
            base.own("overload_unions", interface_text(_own1949));
        }
    } else {
        out.unsigned(0);
        var _keys1953 = Array<(u8[], u8[], String)>();
        for (var (_key1952, _) in value.overload_unions) {
            var _scratch1954 = out.scratch();
            _scratch1954.text(_key1952);
            var _vscratch1956 = out.scratch();
            _vscratch1956.unsigned(value.overload_unions[_key1952].count);
            for (var _item1957 in value.overload_unions[_key1952]) {
                _vscratch1956.unsigned(_item1957.count);
                for (var _item1958 in _item1957) {
                    _vscratch1956.text(_item1958);
                }
            }
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
            out.text(_key1952);
            out.unsigned(value.overload_unions[_key1952].count);
            for (var _item1959 in value.overload_unions[_key1952]) {
                out.unsigned(_item1959.count);
                for (var _item1960 in _item1959) {
                    out.text(_item1960);
                }
            }
        }
        for (var (_okey1961, _) in value.overload_unions) {
            var _own1962 = RecordOut();
            _own1962.blank_bodies = true;
            _own1962.blank_locs = true;
            _own1962.pending_as_bytes = true;
            _own1962.text(_okey1961);
            _own1962.unsigned(value.overload_unions[_okey1961].count);
            for (var _item1963 in value.overload_unions[_okey1961]) {
                _own1962.unsigned(_item1963.count);
                for (var _item1964 in _item1963) {
                    _own1962.text(_item1964);
                }
            }
            base.own("overload_unions", interface_text(_own1962));
        }
        base.count("overload_unions whole", 0);
    }
    base.stat("overload_unions", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept1987 = 0;
    var _news1988 = Map<String, Map<String, Array<String>>>();
    for (var (_key1984, _) in value.method_overload_sets) {
        var _kscratch1985 = base.scratch();
        _kscratch1985.text(_key1984);
        var _vscratch1986 = base.scratch();
        var _keys1990 = Array<(u8[], u8[], String)>();
        for (var (_key1989, _) in value.method_overload_sets[_key1984]) {
            var _scratch1991 = _vscratch1986.scratch();
            _scratch1991.text(_key1989);
            var _vscratch1993 = _vscratch1986.scratch();
            _vscratch1993.unsigned(value.method_overload_sets[_key1984][_key1989].count);
            for (var _item1994 in value.method_overload_sets[_key1984][_key1989]) {
                _vscratch1993.text(_item1994);
            }
            _keys1990.append((_scratch1991.finish(), _vscratch1993.finish(), _key1989));
        }
        _keys1990.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        _vscratch1986.unsigned(_keys1990.count);
        for (var (_bytes1992, _, _key1989) in _keys1990) {
            _vscratch1986.text(_key1989);
            _vscratch1986.unsigned(value.method_overload_sets[_key1984][_key1989].count);
            for (var _item1995 in value.method_overload_sets[_key1984][_key1989]) {
                _vscratch1986.text(_item1995);
            }
        }
        var _had = base.entry("method_overload_sets", _kscratch1985, _vscratch1986);
        if (_had >= 0) {
            _kept1987 += 1;
        }
        if (_had != 1) {
            _news1988[_key1984] = value.method_overload_sets[_key1984];
        }
    }
    if (_kept1987 == base.size("method_overload_sets")) {
        out.unsigned(1);
        var _keys1997 = Array<(u8[], u8[], String)>();
        for (var (_key1996, _) in _news1988) {
            var _scratch1998 = out.scratch();
            _scratch1998.text(_key1996);
            var _vscratch2000 = out.scratch();
            var _keys2002 = Array<(u8[], u8[], String)>();
            for (var (_key2001, _) in _news1988[_key1996]) {
                var _scratch2003 = _vscratch2000.scratch();
                _scratch2003.text(_key2001);
                var _vscratch2005 = _vscratch2000.scratch();
                _vscratch2005.unsigned(_news1988[_key1996][_key2001].count);
                for (var _item2006 in _news1988[_key1996][_key2001]) {
                    _vscratch2005.text(_item2006);
                }
                _keys2002.append((_scratch2003.finish(), _vscratch2005.finish(), _key2001));
            }
            _keys2002.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            _vscratch2000.unsigned(_keys2002.count);
            for (var (_bytes2004, _, _key2001) in _keys2002) {
                _vscratch2000.text(_key2001);
                _vscratch2000.unsigned(_news1988[_key1996][_key2001].count);
                for (var _item2007 in _news1988[_key1996][_key2001]) {
                    _vscratch2000.text(_item2007);
                }
            }
            _keys1997.append((_scratch1998.finish(), _vscratch2000.finish(), _key1996));
        }
        _keys1997.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1997.count);
        for (var (_bytes1999, _, _key1996) in _keys1997) {
            out.text(_key1996);
            var _keys2009 = Array<(u8[], u8[], String)>();
            for (var (_key2008, _) in _news1988[_key1996]) {
                var _scratch2010 = out.scratch();
                _scratch2010.text(_key2008);
                var _vscratch2012 = out.scratch();
                _vscratch2012.unsigned(_news1988[_key1996][_key2008].count);
                for (var _item2013 in _news1988[_key1996][_key2008]) {
                    _vscratch2012.text(_item2013);
                }
                _keys2009.append((_scratch2010.finish(), _vscratch2012.finish(), _key2008));
            }
            _keys2009.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            out.unsigned(_keys2009.count);
            for (var (_bytes2011, _, _key2008) in _keys2009) {
                out.text(_key2008);
                out.unsigned(_news1988[_key1996][_key2008].count);
                for (var _item2014 in _news1988[_key1996][_key2008]) {
                    out.text(_item2014);
                }
            }
        }
        for (var (_okey2015, _) in _news1988) {
            var _own2016 = RecordOut();
            _own2016.blank_bodies = true;
            _own2016.blank_locs = true;
            _own2016.pending_as_bytes = true;
            _own2016.text(_okey2015);
            var _keys2018 = Array<(u8[], u8[], String)>();
            for (var (_key2017, _) in _news1988[_okey2015]) {
                var _scratch2019 = _own2016.scratch();
                _scratch2019.text(_key2017);
                var _vscratch2021 = _own2016.scratch();
                _vscratch2021.unsigned(_news1988[_okey2015][_key2017].count);
                for (var _item2022 in _news1988[_okey2015][_key2017]) {
                    _vscratch2021.text(_item2022);
                }
                _keys2018.append((_scratch2019.finish(), _vscratch2021.finish(), _key2017));
            }
            _keys2018.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            _own2016.unsigned(_keys2018.count);
            for (var (_bytes2020, _, _key2017) in _keys2018) {
                _own2016.text(_key2017);
                _own2016.unsigned(_news1988[_okey2015][_key2017].count);
                for (var _item2023 in _news1988[_okey2015][_key2017]) {
                    _own2016.text(_item2023);
                }
            }
            base.own("method_overload_sets", interface_text(_own2016));
        }
    } else {
        out.unsigned(0);
        var _keys2025 = Array<(u8[], u8[], String)>();
        for (var (_key2024, _) in value.method_overload_sets) {
            var _scratch2026 = out.scratch();
            _scratch2026.text(_key2024);
            var _vscratch2028 = out.scratch();
            var _keys2030 = Array<(u8[], u8[], String)>();
            for (var (_key2029, _) in value.method_overload_sets[_key2024]) {
                var _scratch2031 = _vscratch2028.scratch();
                _scratch2031.text(_key2029);
                var _vscratch2033 = _vscratch2028.scratch();
                _vscratch2033.unsigned(value.method_overload_sets[_key2024][_key2029].count);
                for (var _item2034 in value.method_overload_sets[_key2024][_key2029]) {
                    _vscratch2033.text(_item2034);
                }
                _keys2030.append((_scratch2031.finish(), _vscratch2033.finish(), _key2029));
            }
            _keys2030.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            _vscratch2028.unsigned(_keys2030.count);
            for (var (_bytes2032, _, _key2029) in _keys2030) {
                _vscratch2028.text(_key2029);
                _vscratch2028.unsigned(value.method_overload_sets[_key2024][_key2029].count);
                for (var _item2035 in value.method_overload_sets[_key2024][_key2029]) {
                    _vscratch2028.text(_item2035);
                }
            }
            _keys2025.append((_scratch2026.finish(), _vscratch2028.finish(), _key2024));
        }
        _keys2025.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2025.count);
        for (var (_bytes2027, _, _key2024) in _keys2025) {
            out.text(_key2024);
            var _keys2037 = Array<(u8[], u8[], String)>();
            for (var (_key2036, _) in value.method_overload_sets[_key2024]) {
                var _scratch2038 = out.scratch();
                _scratch2038.text(_key2036);
                var _vscratch2040 = out.scratch();
                _vscratch2040.unsigned(value.method_overload_sets[_key2024][_key2036].count);
                for (var _item2041 in value.method_overload_sets[_key2024][_key2036]) {
                    _vscratch2040.text(_item2041);
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
                out.unsigned(value.method_overload_sets[_key2024][_key2036].count);
                for (var _item2042 in value.method_overload_sets[_key2024][_key2036]) {
                    out.text(_item2042);
                }
            }
        }
        for (var (_okey2043, _) in value.method_overload_sets) {
            var _own2044 = RecordOut();
            _own2044.blank_bodies = true;
            _own2044.blank_locs = true;
            _own2044.pending_as_bytes = true;
            _own2044.text(_okey2043);
            var _keys2046 = Array<(u8[], u8[], String)>();
            for (var (_key2045, _) in value.method_overload_sets[_okey2043]) {
                var _scratch2047 = _own2044.scratch();
                _scratch2047.text(_key2045);
                var _vscratch2049 = _own2044.scratch();
                _vscratch2049.unsigned(value.method_overload_sets[_okey2043][_key2045].count);
                for (var _item2050 in value.method_overload_sets[_okey2043][_key2045]) {
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
            _own2044.unsigned(_keys2046.count);
            for (var (_bytes2048, _, _key2045) in _keys2046) {
                _own2044.text(_key2045);
                _own2044.unsigned(value.method_overload_sets[_okey2043][_key2045].count);
                for (var _item2051 in value.method_overload_sets[_okey2043][_key2045]) {
                    _own2044.text(_item2051);
                }
            }
            base.own("method_overload_sets", interface_text(_own2044));
        }
        base.count("method_overload_sets whole", 0);
    }
    base.stat("method_overload_sets", out.values.count - _mark);
    _mark = out.values.count;
    _m_ExtensionScopes_write(out, value.extension_scopes);
    base.stat("extension_scopes", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2082 = 0;
    var _news2083 = HashSet<Loc>();
    for (var _key2079 in value.private_functions) {
        var _kscratch2080 = base.scratch();
        _kscratch2080.loc(_key2079);
        var _vscratch2081 = base.scratch();
        var _had = base.entry("private_functions", _kscratch2080, _vscratch2081);
        if (_had >= 0) {
            _kept2082 += 1;
        }
        if (_had != 1) {
            _news2083.insert(_key2079);
        }
    }
    if (_kept2082 == base.size("private_functions")) {
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
            base.own_at("private_functions", _okey2089, interface_text(_own2090));
        }
    } else {
        out.unsigned(0);
        var _keys2092 = Array<(u8[], u8[], Loc)>();
        for (var _key2091 in value.private_functions) {
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
        for (var _okey2096 in value.private_functions) {
            var _own2097 = RecordOut();
            _own2097.blank_bodies = true;
            _own2097.blank_locs = true;
            _own2097.pending_as_bytes = true;
            _own2097.loc(_okey2096);
            base.own_at("private_functions", _okey2096, interface_text(_own2097));
        }
        base.count("private_functions whole", 0);
    }
    base.stat("private_functions", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2108 = 0;
    var _news2109 = HashSet<Loc>();
    for (var _key2105 in value.file_private_functions) {
        var _kscratch2106 = base.scratch();
        _kscratch2106.loc(_key2105);
        var _vscratch2107 = base.scratch();
        var _had = base.entry("file_private_functions", _kscratch2106, _vscratch2107);
        if (_had >= 0) {
            _kept2108 += 1;
        }
        if (_had != 1) {
            _news2109.insert(_key2105);
        }
    }
    if (_kept2108 == base.size("file_private_functions")) {
        out.unsigned(1);
        var _keys2111 = Array<(u8[], u8[], Loc)>();
        for (var _key2110 in _news2109) {
            var _scratch2112 = out.scratch();
            _scratch2112.loc(_key2110);
            var _vscratch2114 = out.scratch();
            _keys2111.append((_scratch2112.finish(), _vscratch2114.finish(), _key2110));
        }
        _keys2111.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2111.count);
        for (var (_bytes2113, _, _key2110) in _keys2111) {
            out.loc(_key2110);
        }
        for (var _okey2115 in _news2109) {
            var _own2116 = RecordOut();
            _own2116.blank_bodies = true;
            _own2116.blank_locs = true;
            _own2116.pending_as_bytes = true;
            _own2116.loc(_okey2115);
            base.own_at("file_private_functions", _okey2115, interface_text(_own2116));
        }
    } else {
        out.unsigned(0);
        var _keys2118 = Array<(u8[], u8[], Loc)>();
        for (var _key2117 in value.file_private_functions) {
            var _scratch2119 = out.scratch();
            _scratch2119.loc(_key2117);
            var _vscratch2121 = out.scratch();
            _keys2118.append((_scratch2119.finish(), _vscratch2121.finish(), _key2117));
        }
        _keys2118.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2118.count);
        for (var (_bytes2120, _, _key2117) in _keys2118) {
            out.loc(_key2117);
        }
        for (var _okey2122 in value.file_private_functions) {
            var _own2123 = RecordOut();
            _own2123.blank_bodies = true;
            _own2123.blank_locs = true;
            _own2123.pending_as_bytes = true;
            _own2123.loc(_okey2122);
            base.own_at("file_private_functions", _okey2122, interface_text(_own2123));
        }
        base.count("file_private_functions whole", 0);
    }
    base.stat("file_private_functions", out.values.count - _mark);
    _mark = out.values.count;
    var _n2133 = base.size("call_targets");
    var _scratch2132 = base.scratch();
    if (value.call_targets.count >= _n2133) {
        for (var _i2134 in 0.._n2133) {
            var (_t2135, _t2136) = value.call_targets[_i2134];
            _scratch2132.loc(_t2135);
            _scratch2132.text(_t2136);
        }
    }
    if (value.call_targets.count >= _n2133 and base.same_list("call_targets", _scratch2132)) {
        out.unsigned(1);
        out.unsigned(_n2133);
        out.unsigned(value.call_targets.count - _n2133);
        for (var _i2134 in _n2133..value.call_targets.count) {
            var (_t2137, _t2138) = value.call_targets[_i2134];
            out.loc(_t2137);
            out.text(_t2138);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.call_targets.count);
        for (var _item2139 in value.call_targets) {
            var (_t2140, _t2141) = _item2139;
            out.loc(_t2140);
            out.text(_t2141);
        }
        base.count("call_targets whole", 0);
    }
    base.stat("call_targets", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2158 = 0;
    var _news2159 = Array<(Loc, String)>();
    for (var _item2156 in value.argument_names) {
        var _escratch2157 = base.scratch();
        var (_t2160, _t2161) = _item2156;
        _escratch2157.loc(_t2160);
        _escratch2157.text(_t2161);
        if (base.entry("argument_names", _escratch2157, base.scratch()) >= 0) {
            _kept2158 += 1;
        } else {
            _news2159.append(_item2156);
        }
    }
    if (_kept2158 == base.size("argument_names")) {
        out.unsigned(1);
        out.unsigned(_news2159.count);
        for (var _item2162 in _news2159) {
            var (_t2163, _t2164) = _item2162;
            out.loc(_t2163);
            out.text(_t2164);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.argument_names.count);
        for (var _item2165 in value.argument_names) {
            var (_t2166, _t2167) = _item2165;
            out.loc(_t2166);
            out.text(_t2167);
        }
        base.count("argument_names whole", 0);
    }
    base.stat("argument_names", out.values.count - _mark);
    _mark = out.values.count;
    var _n2182 = base.size("namespaces");
    var _scratch2181 = base.scratch();
    if (value.namespaces.count >= _n2182) {
        for (var _i2183 in 0.._n2182) {
            _scratch2181.text(value.namespaces[_i2183]);
        }
    }
    if (value.namespaces.count >= _n2182 and base.same_list("namespaces", _scratch2181)) {
        out.unsigned(1);
        out.unsigned(_n2182);
        out.unsigned(value.namespaces.count - _n2182);
        for (var _i2183 in _n2182..value.namespaces.count) {
            out.text(value.namespaces[_i2183]);
            {
                var _own2184 = RecordOut();
                _own2184.blank_bodies = true;
                _own2184.blank_locs = true;
                _own2184.pending_as_bytes = true;
                _own2184.text(value.namespaces[_i2183]);
                base.own("namespaces", interface_text(_own2184));
            }
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.namespaces.count);
        for (var _item2185 in value.namespaces) {
            out.text(_item2185);
        }
        for (var _i2183 in 0..value.namespaces.count) {
            {
                var _own2186 = RecordOut();
                _own2186.blank_bodies = true;
                _own2186.blank_locs = true;
                _own2186.pending_as_bytes = true;
                _own2186.text(value.namespaces[_i2183]);
                base.own("namespaces", interface_text(_own2186));
            }
        }
        base.count("namespaces whole", 0);
    }
    base.stat("namespaces", out.values.count - _mark);
    _mark = out.values.count;
    var _n2197 = base.size("cached_files");
    var _scratch2196 = base.scratch();
    if (value.cached_files.count >= _n2197) {
        for (var _i2198 in 0.._n2197) {
            _scratch2196.flag(value.cached_files[_i2198]);
        }
    }
    if (value.cached_files.count >= _n2197 and base.same_list("cached_files", _scratch2196)) {
        out.unsigned(1);
        out.unsigned(_n2197);
        out.unsigned(value.cached_files.count - _n2197);
        for (var _i2198 in _n2197..value.cached_files.count) {
            out.flag(value.cached_files[_i2198]);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.cached_files.count);
        for (var _item2199 in value.cached_files) {
            out.flag(_item2199);
        }
        base.count("cached_files whole", 0);
    }
    base.stat("cached_files", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2211 = 0;
    var _news2212 = HashMap<Loc, String>();
    for (var (_key2208, _) in value.recorded_summaries) {
        var _kscratch2209 = base.scratch();
        _kscratch2209.loc(_key2208);
        var _vscratch2210 = base.scratch();
        _vscratch2210.text(value.recorded_summaries[_key2208]);
        var _had = base.entry("recorded_summaries", _kscratch2209, _vscratch2210);
        if (_had >= 0) {
            _kept2211 += 1;
        }
        if (_had != 1) {
            _news2212[_key2208] = value.recorded_summaries[_key2208];
        }
    }
    if (_kept2211 == base.size("recorded_summaries")) {
        out.unsigned(1);
        var _keys2214 = Array<(u8[], u8[], Loc)>();
        for (var (_key2213, _) in _news2212) {
            var _scratch2215 = out.scratch();
            _scratch2215.loc(_key2213);
            var _vscratch2217 = out.scratch();
            _vscratch2217.text(_news2212[_key2213]);
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
            out.text(_news2212[_key2213]);
        }
    } else {
        out.unsigned(0);
        var _keys2219 = Array<(u8[], u8[], Loc)>();
        for (var (_key2218, _) in value.recorded_summaries) {
            var _scratch2220 = out.scratch();
            _scratch2220.loc(_key2218);
            var _vscratch2222 = out.scratch();
            _vscratch2222.text(value.recorded_summaries[_key2218]);
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
            out.text(value.recorded_summaries[_key2218]);
        }
        base.count("recorded_summaries whole", 0);
    }
    base.stat("recorded_summaries", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2235 = 0;
    var _news2236 = HashSet<Loc>();
    for (var _key2232 in value.stripped) {
        var _kscratch2233 = base.scratch();
        _kscratch2233.loc(_key2232);
        var _vscratch2234 = base.scratch();
        var _had = base.entry("stripped", _kscratch2233, _vscratch2234);
        if (_had >= 0) {
            _kept2235 += 1;
        }
        if (_had != 1) {
            _news2236.insert(_key2232);
        }
    }
    if (_kept2235 == base.size("stripped")) {
        out.unsigned(1);
        var _keys2238 = Array<(u8[], u8[], Loc)>();
        for (var _key2237 in _news2236) {
            var _scratch2239 = out.scratch();
            _scratch2239.loc(_key2237);
            var _vscratch2241 = out.scratch();
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
            out.loc(_key2237);
        }
    } else {
        out.unsigned(0);
        var _keys2243 = Array<(u8[], u8[], Loc)>();
        for (var _key2242 in value.stripped) {
            var _scratch2244 = out.scratch();
            _scratch2244.loc(_key2242);
            var _vscratch2246 = out.scratch();
            _keys2243.append((_scratch2244.finish(), _vscratch2246.finish(), _key2242));
        }
        _keys2243.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2243.count);
        for (var (_bytes2245, _, _key2242) in _keys2243) {
            out.loc(_key2242);
        }
        base.count("stripped whole", 0);
    }
    base.stat("stripped", out.values.count - _mark);
    _mark = out.values.count;
    out.flag(value.templates.frozen);
    var _seq2256 = base.ref_templates;
    ulong _bj2257 = 0;
    var _news2259 = Array<ulong>();
    var _patches2260 = Array<(ulong, ulong)>();
    for (var _i2261 in 0..value.templates.structs.count) {
        if (_bj2257 < _seq2256.count
            and value.templates.structs[_i2261] === _seq2256[_bj2257]
            and !value.extended_checked.contains(value.templates.structs[_i2261].name)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_StructDef_write(scratch, value.templates.structs[_i2261]);
                base.verify_same("t", _bj2257, scratch, value.templates.structs[_i2261].name);
            }
            _bj2257 += 1;
        } else if (_bj2257 < _seq2256.count
            and !(value.templates.structs[_i2261] === _seq2256[_bj2257])
            and _same_m_StructDef(value.templates.structs[_i2261], _seq2256[_bj2257], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_StructDef_write(scratch, value.templates.structs[_i2261]);
                base.verify_same("t", _bj2257, scratch, value.templates.structs[_i2261].name);
            }
            _bj2257 += 1;
        } else if (_bj2257 < _seq2256.count and value.templates.structs[_i2261].name == _seq2256[_bj2257].name) {
            _patches2260.append((_i2261, _bj2257));
            _bj2257 += 1;
        } else {
            _news2259.append(_i2261);
        }
    }
    if (_bj2257 == _seq2256.count) {
        out.unsigned(2);
        out.unsigned(_patches2260.count);
        for (var (_i2261, _b) in _patches2260) {
            ulong _before = out.values.count;
            out.text(value.templates.structs[_i2261].name);
            out.unsigned(_b);
            _patch_t_write(out, value.templates.structs[_i2261], base, _b);
            base.count("t patched", out.values.count - _before);
            {
                var _own2262 = RecordOut();
                _own2262.blank_bodies = false;
                _own2262.blank_locs = true;
                _own2262.pending_as_bytes = true;
                _m_StructDef_write(_own2262, value.templates.structs[_i2261]);
                base.own("templates structs", interface_text(_own2262));
            }
        }
        out.unsigned(_news2259.count);
        for (var _i2261 in _news2259) {
            ulong _before = out.values.count;
            out.unsigned(_i2261);
            _m_StructDef_write(out, value.templates.structs[_i2261]);
            base.count("t new", out.values.count - _before);
            {
                var _own2263 = RecordOut();
                _own2263.blank_bodies = false;
                _own2263.blank_locs = true;
                _own2263.pending_as_bytes = true;
                _m_StructDef_write(_own2263, value.templates.structs[_i2261]);
                base.own("templates structs", interface_text(_own2263));
            }
        }
        base.count("t merged", 0);
    } else {
        out.unsigned(1);
        base.count("t by place", 0);
        var _struct_hits2255 = HashSet<long>();
        var _slots2258 = HashMap<String, long>();
        for (var _i2261 in 0.._seq2256.count) {
            if (!_slots2258.contains(_seq2256[_i2261].name)) {
                _slots2258[_seq2256[_i2261].name] = _i2261 as long;
            }
        }
        out.unsigned(value.templates.structs.count);
        for (var _i2261 in 0..value.templates.structs.count) {
            var _item2254 = value.templates.structs[_i2261];
            var _slot = _slots2258.try_get(_item2254.name);
            long named = _slot.is_value() ? _slot.value() : -1;
            long at = -1;
            if (named >= 0
                and _seq2256[named as ulong] === _item2254
                and !value.extended_checked.contains(_item2254.name)) {
                at = named;
            }
            ulong _before = out.values.count;
            if (at >= 0) {
                _struct_hits2255.insert(at);
                out.unsigned((at as ulong) * 2 + 1);
            } else if (named >= 0) {
                _struct_hits2255.insert(named);
                out.unsigned(2);
                out.unsigned(named as ulong);
                _patch_t_write(out, _item2254, base, named as ulong);
                base.count("t patched", out.values.count - _before);
            } else {
                out.unsigned(0);
                _m_StructDef_write(out, _item2254);
                base.count("t new", out.values.count - _before);
            }
        }
        base.missed("t", "t", _struct_hits2255.count);
    }
    var _seq2277 = base.ref_template_functions;
    ulong _bj2278 = 0;
    var _news2279 = Array<ulong>();
    var _changed2273 = Array<(ulong, ulong)>();
    for (var _i2280 in 0..value.templates.functions.count) {
        if (_bj2278 < _seq2277.count and value.templates.functions[_i2280] === _seq2277[_bj2278]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.templates.functions[_i2280]);
                base.verify_same("tf", _bj2278, scratch);
            }
            _bj2278 += 1;
        } else if (_bj2278 < _seq2277.count
            and _same_m_FunctionDef(value.templates.functions[_i2280], _seq2277[_bj2278], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.templates.functions[_i2280]);
                base.verify_same("tf", _bj2278, scratch);
            }
            _bj2278 += 1;
        } else if (_bj2278 < _seq2277.count and value.templates.functions[_i2280].name == _seq2277[_bj2278].name) {
            _changed2273.append((_i2280, _bj2278));
            _bj2278 += 1;
        } else {
            _news2279.append(_i2280);
        }
    }
    if (_bj2278 == _seq2277.count) {
        out.unsigned(2);
        out.unsigned(_changed2273.count);
        for (var (_i2280, _b) in _changed2273) {
            out.text(value.templates.functions[_i2280].name);
            out.unsigned(_b);
            _m_FunctionDef_write(out, value.templates.functions[_i2280]);
            {
                var _own2281 = RecordOut();
                _own2281.blank_bodies = false;
                _own2281.blank_locs = true;
                _own2281.pending_as_bytes = true;
                _m_FunctionDef_write(_own2281, value.templates.functions[_i2280]);
                base.own("templates functions", interface_text(_own2281));
            }
        }
        base.count("tf" + " changed", _changed2273.count);
        out.unsigned(_news2279.count);
        for (var _i2280 in _news2279) {
            out.unsigned(_i2280);
            _m_FunctionDef_write(out, value.templates.functions[_i2280]);
            {
                var _own2282 = RecordOut();
                _own2282.blank_bodies = false;
                _own2282.blank_locs = true;
                _own2282.pending_as_bytes = true;
                _m_FunctionDef_write(_own2282, value.templates.functions[_i2280]);
                base.own("templates functions", interface_text(_own2282));
            }
        }
        base.count("tf" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("tf" + " whole", 0);
        out.unsigned(value.templates.functions.count);
        for (var _i2280 in 0..value.templates.functions.count) {
            _m_FunctionDef_write(out, value.templates.functions[_i2280]);
            {
                var _own2283 = RecordOut();
                _own2283.blank_bodies = false;
                _own2283.blank_locs = true;
                _own2283.pending_as_bytes = true;
                _m_FunctionDef_write(_own2283, value.templates.functions[_i2280]);
                base.own("templates functions", interface_text(_own2283));
            }
        }
    }
    base.stat("templates", out.values.count - _mark);
    _mark = out.values.count;
    base.write_checked(out, value.checked);
    base.stat("checked", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2296 = 0;
    var _news2297 = HashMap<String, SpecRequest>();
    for (var (_key2293, _) in value.spec_requests) {
        var _kscratch2294 = base.scratch();
        _kscratch2294.text(_key2293);
        var _vscratch2295 = base.scratch();
        _m_SpecRequest_write(_vscratch2295, value.spec_requests[_key2293]);
        var _had = base.entry("spec_requests", _kscratch2294, _vscratch2295);
        if (_had >= 0) {
            _kept2296 += 1;
        }
        if (_had != 1) {
            _news2297[_key2293] = value.spec_requests[_key2293];
        }
    }
    if (_kept2296 == base.size("spec_requests")) {
        out.unsigned(1);
        var _keys2299 = Array<(u8[], u8[], String)>();
        for (var (_key2298, _) in _news2297) {
            var _scratch2300 = out.scratch();
            _scratch2300.text(_key2298);
            var _vscratch2302 = out.scratch();
            _m_SpecRequest_write(_vscratch2302, _news2297[_key2298]);
            _keys2299.append((_scratch2300.finish(), _vscratch2302.finish(), _key2298));
        }
        _keys2299.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2299.count);
        for (var (_bytes2301, _, _key2298) in _keys2299) {
            out.text(_key2298);
            _m_SpecRequest_write(out, _news2297[_key2298]);
        }
        for (var (_okey2303, _) in _news2297) {
            var _own2304 = RecordOut();
            _own2304.blank_bodies = true;
            _own2304.blank_locs = true;
            _own2304.pending_as_bytes = true;
            _own2304.text(_okey2303);
            _m_SpecRequest_write(_own2304, _news2297[_okey2303]);
            base.own("spec_requests", interface_text(_own2304));
        }
    } else {
        out.unsigned(0);
        var _keys2306 = Array<(u8[], u8[], String)>();
        for (var (_key2305, _) in value.spec_requests) {
            var _scratch2307 = out.scratch();
            _scratch2307.text(_key2305);
            var _vscratch2309 = out.scratch();
            _m_SpecRequest_write(_vscratch2309, value.spec_requests[_key2305]);
            _keys2306.append((_scratch2307.finish(), _vscratch2309.finish(), _key2305));
        }
        _keys2306.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2306.count);
        for (var (_bytes2308, _, _key2305) in _keys2306) {
            out.text(_key2305);
            _m_SpecRequest_write(out, value.spec_requests[_key2305]);
        }
        for (var (_okey2310, _) in value.spec_requests) {
            var _own2311 = RecordOut();
            _own2311.blank_bodies = true;
            _own2311.blank_locs = true;
            _own2311.pending_as_bytes = true;
            _own2311.text(_okey2310);
            _m_SpecRequest_write(_own2311, value.spec_requests[_okey2310]);
            base.own("spec_requests", interface_text(_own2311));
        }
        base.count("spec_requests whole", 0);
    }
    base.stat("spec_requests", out.values.count - _mark);
    _mark = out.values.count;
    out.flag(value.record_summaries);
    base.stat("record_summaries", out.values.count - _mark);
    _mark = out.values.count;
    var _n2324 = base.size("summaries_to_record");
    var _scratch2323 = base.scratch();
    if (value.summaries_to_record.count >= _n2324) {
        for (var _i2325 in 0.._n2324) {
            var (_t2326, _t2327) = value.summaries_to_record[_i2325];
            _scratch2323.loc(_t2326);
            _scratch2323.text(_t2327);
        }
    }
    if (value.summaries_to_record.count >= _n2324 and base.same_list("summaries_to_record", _scratch2323)) {
        out.unsigned(1);
        out.unsigned(_n2324);
        out.unsigned(value.summaries_to_record.count - _n2324);
        for (var _i2325 in _n2324..value.summaries_to_record.count) {
            var (_t2328, _t2329) = value.summaries_to_record[_i2325];
            out.loc(_t2328);
            out.text(_t2329);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.summaries_to_record.count);
        for (var _item2330 in value.summaries_to_record) {
            var (_t2331, _t2332) = _item2330;
            out.loc(_t2331);
            out.text(_t2332);
        }
        base.count("summaries_to_record whole", 0);
    }
    base.stat("summaries_to_record", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2350 = 0;
    var _news2351 = HashMap<String, Array<bool>>();
    for (var (_key2347, _) in value.caller_copies) {
        var _kscratch2348 = base.scratch();
        _kscratch2348.text(_key2347);
        var _vscratch2349 = base.scratch();
        _vscratch2349.unsigned(value.caller_copies[_key2347].count);
        for (var _item2352 in value.caller_copies[_key2347]) {
            _vscratch2349.flag(_item2352);
        }
        var _had = base.entry("caller_copies", _kscratch2348, _vscratch2349);
        if (_had >= 0) {
            _kept2350 += 1;
        }
        if (_had != 1) {
            _news2351[_key2347] = value.caller_copies[_key2347];
        }
    }
    if (_kept2350 == base.size("caller_copies")) {
        out.unsigned(1);
        var _keys2354 = Array<(u8[], u8[], String)>();
        for (var (_key2353, _) in _news2351) {
            var _scratch2355 = out.scratch();
            _scratch2355.text(_key2353);
            var _vscratch2357 = out.scratch();
            _vscratch2357.unsigned(_news2351[_key2353].count);
            for (var _item2358 in _news2351[_key2353]) {
                _vscratch2357.flag(_item2358);
            }
            _keys2354.append((_scratch2355.finish(), _vscratch2357.finish(), _key2353));
        }
        _keys2354.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2354.count);
        for (var (_bytes2356, _, _key2353) in _keys2354) {
            out.text(_key2353);
            out.unsigned(_news2351[_key2353].count);
            for (var _item2359 in _news2351[_key2353]) {
                out.flag(_item2359);
            }
        }
        for (var (_okey2360, _) in _news2351) {
            var _own2361 = RecordOut();
            _own2361.blank_bodies = true;
            _own2361.blank_locs = true;
            _own2361.pending_as_bytes = true;
            _own2361.text(_okey2360);
            _own2361.unsigned(_news2351[_okey2360].count);
            for (var _item2362 in _news2351[_okey2360]) {
                _own2361.flag(_item2362);
            }
            base.own("caller_copies", interface_text(_own2361));
        }
    } else {
        out.unsigned(0);
        var _keys2364 = Array<(u8[], u8[], String)>();
        for (var (_key2363, _) in value.caller_copies) {
            var _scratch2365 = out.scratch();
            _scratch2365.text(_key2363);
            var _vscratch2367 = out.scratch();
            _vscratch2367.unsigned(value.caller_copies[_key2363].count);
            for (var _item2368 in value.caller_copies[_key2363]) {
                _vscratch2367.flag(_item2368);
            }
            _keys2364.append((_scratch2365.finish(), _vscratch2367.finish(), _key2363));
        }
        _keys2364.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2364.count);
        for (var (_bytes2366, _, _key2363) in _keys2364) {
            out.text(_key2363);
            out.unsigned(value.caller_copies[_key2363].count);
            for (var _item2369 in value.caller_copies[_key2363]) {
                out.flag(_item2369);
            }
        }
        for (var (_okey2370, _) in value.caller_copies) {
            var _own2371 = RecordOut();
            _own2371.blank_bodies = true;
            _own2371.blank_locs = true;
            _own2371.pending_as_bytes = true;
            _own2371.text(_okey2370);
            _own2371.unsigned(value.caller_copies[_okey2370].count);
            for (var _item2372 in value.caller_copies[_okey2370]) {
                _own2371.flag(_item2372);
            }
            base.own("caller_copies", interface_text(_own2371));
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
    var _f1519 = Array<ast.Import>();
    var _mode1522 = input.unsigned();
    if (_mode1522 == 2) {
        var _changed1508 = HashMap<ulong, ast.Import>();
        ulong _bi1523 = 0;
        var _n1520 = input.count();
        for (var _ in 0.._n1520) {
            var _at1524 = input.unsigned();
            while (_f1519.count < _at1524 or (input.merging and _bi1523 < base.imports.count)) {
                var _c = _changed1508.try_get(_bi1523);
                _f1519.append(_c.is_value() ? _c.value() : base.imports[_bi1523]);
                _bi1523 += 1;
            }
            _f1519.append(_a_Import_read(input));
        }
        while (_bi1523 < base.imports.count) {
            var _c = _changed1508.try_get(_bi1523);
            _f1519.append(_c.is_value() ? _c.value() : base.imports[_bi1523]);
            _bi1523 += 1;
        }
    } else if (_mode1522 == 3) {
        var _n1520 = input.count();
        for (var _ in 0.._n1520) {
            _f1519.append(_a_Import_read(input));
        }
    } else {
        var _n1520 = input.count();
        if (input.merging) {
            input.error = "imports" + " written by place";
        }
        for (var _ in 0.._n1520) {
            var _tag1521 = input.unsigned();
            if (_tag1521 & 1 == 1) {
                if (!input.merging) {
                    _f1519.append(base.imports[_tag1521 >> 1]);
                }
            } else {
                var _read = _a_Import_read(input);
                if (!input.merging or true) {
                    _f1519.append(_read);
                }
            }
        }
    }
    var _f1552 = Array<StructDef>();
    var _mode1555 = input.unsigned();
    if (_mode1555 == 2) {
        var _patched1558 = HashMap<ulong, StructDef>();
        var _n1553 = input.count();
        for (var _ in 0.._n1553) {
            var _name = input.text();
            var _slot = input.unsigned();
            if (input.merging) {
                _slot = struct_named(base.structs, _name);
            }
            if (_slot >= base.structs.count) {
                input.error = $"no struct {_name} to patch";
                break;
            }
            _patched1558[_slot] = _patch_s_read(input, base.structs[_slot]);
        }
        ulong _bi1556 = 0;
        var _added = input.count();
        for (var _ in 0.._added) {
            var _at1557 = input.unsigned();
            while (_f1552.count < _at1557 or (input.merging and _bi1556 < base.structs.count)) {
                var _p = _patched1558.try_get(_bi1556);
                _f1552.append(_p.is_value() ? _p.value() : base.structs[_bi1556]);
                _bi1556 += 1;
            }
            _f1552.append(_m_StructDef_read_lazy(input));
        }
        while (_bi1556 < base.structs.count) {
            var _p = _patched1558.try_get(_bi1556);
            _f1552.append(_p.is_value() ? _p.value() : base.structs[_bi1556]);
            _bi1556 += 1;
        }
    } else {
        if (input.merging) {
            input.error = "structs written by place";
        }
        var _n1553 = input.count();
        for (var _ in 0.._n1553) {
            var _tag1554 = input.unsigned();
            if (_tag1554 & 1 == 1) {
                _f1552.append(base.structs[(_tag1554 >> 1) < base.structs.count ? _tag1554 >> 1 : 0]);
            } else if (_tag1554 == 2) {
                var _was = base.structs[input.unsigned()];
                _f1552.append(_patch_s_read(input, _was));
            } else {
                _f1552.append(_m_StructDef_read_lazy(input));
            }
        }
    }
    var _f1572 = Array<TraitDef>();
    var _mode1575 = input.unsigned();
    if (_mode1575 == 2) {
        var _changed1561 = HashMap<ulong, TraitDef>();
        ulong _bi1576 = 0;
        var _n1573 = input.count();
        for (var _ in 0.._n1573) {
            var _at1577 = input.unsigned();
            while (_f1572.count < _at1577 or (input.merging and _bi1576 < base.traits.count)) {
                var _c = _changed1561.try_get(_bi1576);
                _f1572.append(_c.is_value() ? _c.value() : base.traits[_bi1576]);
                _bi1576 += 1;
            }
            _f1572.append(_m_TraitDef_read(input));
        }
        while (_bi1576 < base.traits.count) {
            var _c = _changed1561.try_get(_bi1576);
            _f1572.append(_c.is_value() ? _c.value() : base.traits[_bi1576]);
            _bi1576 += 1;
        }
    } else if (_mode1575 == 3) {
        var _n1573 = input.count();
        for (var _ in 0.._n1573) {
            _f1572.append(_m_TraitDef_read(input));
        }
    } else {
        var _n1573 = input.count();
        if (input.merging) {
            input.error = "traits" + " written by place";
        }
        for (var _ in 0.._n1573) {
            var _tag1574 = input.unsigned();
            if (_tag1574 & 1 == 1) {
                if (!input.merging) {
                    _f1572.append(base.traits[_tag1574 >> 1]);
                }
            } else {
                var _read = _m_TraitDef_read(input);
                if (!input.merging or true) {
                    _f1572.append(_read);
                }
            }
        }
    }
    var _f1591 = Array<ExtensionDef>();
    var _mode1594 = input.unsigned();
    if (_mode1594 == 2) {
        var _changed1580 = HashMap<ulong, ExtensionDef>();
        ulong _bi1595 = 0;
        var _n1592 = input.count();
        for (var _ in 0.._n1592) {
            var _at1596 = input.unsigned();
            while (_f1591.count < _at1596 or (input.merging and _bi1595 < base.extensions.count)) {
                var _c = _changed1580.try_get(_bi1595);
                _f1591.append(_c.is_value() ? _c.value() : base.extensions[_bi1595]);
                _bi1595 += 1;
            }
            _f1591.append(_m_ExtensionDef_read(input));
        }
        while (_bi1595 < base.extensions.count) {
            var _c = _changed1580.try_get(_bi1595);
            _f1591.append(_c.is_value() ? _c.value() : base.extensions[_bi1595]);
            _bi1595 += 1;
        }
    } else if (_mode1594 == 3) {
        var _n1592 = input.count();
        for (var _ in 0.._n1592) {
            _f1591.append(_m_ExtensionDef_read(input));
        }
    } else {
        var _n1592 = input.count();
        if (input.merging) {
            input.error = "extensions" + " written by place";
        }
        for (var _ in 0.._n1592) {
            var _tag1593 = input.unsigned();
            if (_tag1593 & 1 == 1) {
                if (!input.merging) {
                    _f1591.append(base.extensions[_tag1593 >> 1]);
                }
            } else {
                var _read = _m_ExtensionDef_read(input);
                if (!input.merging or true) {
                    _f1591.append(_read);
                }
            }
        }
    }
    var _f1610 = Array<FunctionDef>();
    var _mode1613 = input.unsigned();
    if (_mode1613 == 2) {
        var _changed1599 = HashMap<ulong, FunctionDef>();
        var _nc1601 = input.count();
        for (var _ in 0.._nc1601) {
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
                _changed1599[_slot] = _el;
            } else {
                input.error = $"no {_name} to change";
            }
        }
        ulong _bi1614 = 0;
        var _n1611 = input.count();
        for (var _ in 0.._n1611) {
            var _at1615 = input.unsigned();
            while (_f1610.count < _at1615 or (input.merging and _bi1614 < base.functions.count)) {
                var _c = _changed1599.try_get(_bi1614);
                _f1610.append(_c.is_value() ? _c.value() : base.functions[_bi1614]);
                _bi1614 += 1;
            }
            _f1610.append(_m_FunctionDef_read_lazy(input));
        }
        while (_bi1614 < base.functions.count) {
            var _c = _changed1599.try_get(_bi1614);
            _f1610.append(_c.is_value() ? _c.value() : base.functions[_bi1614]);
            _bi1614 += 1;
        }
    } else if (_mode1613 == 3) {
        var _n1611 = input.count();
        for (var _ in 0.._n1611) {
            _f1610.append(_m_FunctionDef_read_lazy(input));
        }
    } else {
        var _n1611 = input.count();
        if (input.merging) {
            input.error = "functions" + " written by place";
        }
        for (var _ in 0.._n1611) {
            var _tag1612 = input.unsigned();
            if (_tag1612 & 1 == 1) {
                if (!input.merging) {
                    _f1610.append(base.functions[_tag1612 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read_lazy(input);
                if (!input.merging or true) {
                    _f1610.append(_read);
                }
            }
        }
    }
    var _f1629 = Array<ExternDef>();
    var _mode1632 = input.unsigned();
    if (_mode1632 == 2) {
        var _changed1618 = HashMap<ulong, ExternDef>();
        ulong _bi1633 = 0;
        var _n1630 = input.count();
        for (var _ in 0.._n1630) {
            var _at1634 = input.unsigned();
            while (_f1629.count < _at1634 or (input.merging and _bi1633 < base.externs.count)) {
                var _c = _changed1618.try_get(_bi1633);
                _f1629.append(_c.is_value() ? _c.value() : base.externs[_bi1633]);
                _bi1633 += 1;
            }
            _f1629.append(_m_ExternDef_read(input));
        }
        while (_bi1633 < base.externs.count) {
            var _c = _changed1618.try_get(_bi1633);
            _f1629.append(_c.is_value() ? _c.value() : base.externs[_bi1633]);
            _bi1633 += 1;
        }
    } else if (_mode1632 == 3) {
        var _n1630 = input.count();
        for (var _ in 0.._n1630) {
            _f1629.append(_m_ExternDef_read(input));
        }
    } else {
        var _n1630 = input.count();
        if (input.merging) {
            input.error = "externs" + " written by place";
        }
        for (var _ in 0.._n1630) {
            var _tag1631 = input.unsigned();
            if (_tag1631 & 1 == 1) {
                if (!input.merging) {
                    _f1629.append(base.externs[_tag1631 >> 1]);
                }
            } else {
                var _read = _m_ExternDef_read(input);
                if (!input.merging or true) {
                    _f1629.append(_read);
                }
            }
        }
    }
    var _f1648 = Array<VariableDef>();
    var _mode1651 = input.unsigned();
    if (_mode1651 == 2) {
        var _changed1637 = HashMap<ulong, VariableDef>();
        ulong _bi1652 = 0;
        var _n1649 = input.count();
        for (var _ in 0.._n1649) {
            var _at1653 = input.unsigned();
            while (_f1648.count < _at1653 or (input.merging and _bi1652 < base.globals.count)) {
                var _c = _changed1637.try_get(_bi1652);
                _f1648.append(_c.is_value() ? _c.value() : base.globals[_bi1652]);
                _bi1652 += 1;
            }
            _f1648.append(_m_VariableDef_read(input));
        }
        while (_bi1652 < base.globals.count) {
            var _c = _changed1637.try_get(_bi1652);
            _f1648.append(_c.is_value() ? _c.value() : base.globals[_bi1652]);
            _bi1652 += 1;
        }
    } else if (_mode1651 == 3) {
        var _n1649 = input.count();
        for (var _ in 0.._n1649) {
            _f1648.append(_m_VariableDef_read(input));
        }
    } else {
        var _n1649 = input.count();
        if (input.merging) {
            input.error = "globals" + " written by place";
        }
        for (var _ in 0.._n1649) {
            var _tag1650 = input.unsigned();
            if (_tag1650 & 1 == 1) {
                if (!input.merging) {
                    _f1648.append(base.globals[_tag1650 >> 1]);
                }
            } else {
                var _read = _m_VariableDef_read(input);
                if (!input.merging or true) {
                    _f1648.append(_read);
                }
            }
        }
    }
    var _f1667 = Array<ModuleStaticBlock>();
    var _mode1670 = input.unsigned();
    if (_mode1670 == 2) {
        var _changed1656 = HashMap<ulong, ModuleStaticBlock>();
        ulong _bi1671 = 0;
        var _n1668 = input.count();
        for (var _ in 0.._n1668) {
            var _at1672 = input.unsigned();
            while (_f1667.count < _at1672 or (input.merging and _bi1671 < base.static_blocks.count)) {
                var _c = _changed1656.try_get(_bi1671);
                _f1667.append(_c.is_value() ? _c.value() : base.static_blocks[_bi1671]);
                _bi1671 += 1;
            }
            _f1667.append(_m_ModuleStaticBlock_read(input));
        }
        while (_bi1671 < base.static_blocks.count) {
            var _c = _changed1656.try_get(_bi1671);
            _f1667.append(_c.is_value() ? _c.value() : base.static_blocks[_bi1671]);
            _bi1671 += 1;
        }
    } else if (_mode1670 == 3) {
        var _n1668 = input.count();
        for (var _ in 0.._n1668) {
            _f1667.append(_m_ModuleStaticBlock_read(input));
        }
    } else {
        var _n1668 = input.count();
        if (input.merging) {
            input.error = "static_blocks" + " written by place";
        }
        for (var _ in 0.._n1668) {
            var _tag1669 = input.unsigned();
            if (_tag1669 & 1 == 1) {
                if (!input.merging) {
                    _f1667.append(base.static_blocks[_tag1669 >> 1]);
                }
            } else {
                var _read = _m_ModuleStaticBlock_read(input);
                if (!input.merging or true) {
                    _f1667.append(_read);
                }
            }
        }
    }
    var _f1686 = Array<EnumDef>();
    var _mode1689 = input.unsigned();
    if (_mode1689 == 2) {
        var _changed1675 = HashMap<ulong, EnumDef>();
        ulong _bi1690 = 0;
        var _n1687 = input.count();
        for (var _ in 0.._n1687) {
            var _at1691 = input.unsigned();
            while (_f1686.count < _at1691 or (input.merging and _bi1690 < base.enums.count)) {
                var _c = _changed1675.try_get(_bi1690);
                _f1686.append(_c.is_value() ? _c.value() : base.enums[_bi1690]);
                _bi1690 += 1;
            }
            _f1686.append(_m_EnumDef_read(input));
        }
        while (_bi1690 < base.enums.count) {
            var _c = _changed1675.try_get(_bi1690);
            _f1686.append(_c.is_value() ? _c.value() : base.enums[_bi1690]);
            _bi1690 += 1;
        }
    } else if (_mode1689 == 3) {
        var _n1687 = input.count();
        for (var _ in 0.._n1687) {
            _f1686.append(_m_EnumDef_read(input));
        }
    } else {
        var _n1687 = input.count();
        if (input.merging) {
            input.error = "enums" + " written by place";
        }
        for (var _ in 0.._n1687) {
            var _tag1688 = input.unsigned();
            if (_tag1688 & 1 == 1) {
                if (!input.merging) {
                    _f1686.append(base.enums[_tag1688 >> 1]);
                }
            } else {
                var _read = _m_EnumDef_read(input);
                if (!input.merging or true) {
                    _f1686.append(_read);
                }
            }
        }
    }
    var _f1705 = Array<TypeName>();
    var _mode1708 = input.unsigned();
    if (_mode1708 == 2) {
        var _changed1694 = HashMap<ulong, TypeName>();
        ulong _bi1709 = 0;
        var _n1706 = input.count();
        for (var _ in 0.._n1706) {
            var _at1710 = input.unsigned();
            while (_f1705.count < _at1710 or (input.merging and _bi1709 < base.struct_specs.count)) {
                var _c = _changed1694.try_get(_bi1709);
                _f1705.append(_c.is_value() ? _c.value() : base.struct_specs[_bi1709]);
                _bi1709 += 1;
            }
            _f1705.append(_m_TypeName_read(input));
        }
        while (_bi1709 < base.struct_specs.count) {
            var _c = _changed1694.try_get(_bi1709);
            _f1705.append(_c.is_value() ? _c.value() : base.struct_specs[_bi1709]);
            _bi1709 += 1;
        }
    } else if (_mode1708 == 3) {
        var _n1706 = input.count();
        for (var _ in 0.._n1706) {
            _f1705.append(_m_TypeName_read(input));
        }
    } else {
        var _n1706 = input.count();
        if (input.merging) {
            input.error = "struct_specs" + " written by place";
        }
        for (var _ in 0.._n1706) {
            var _tag1707 = input.unsigned();
            if (_tag1707 & 1 == 1) {
                if (!input.merging) {
                    _f1705.append(base.struct_specs[_tag1707 >> 1]);
                }
            } else {
                var _read = _m_TypeName_read(input);
                if (!input.merging or true) {
                    _f1705.append(_read);
                }
            }
        }
    }
    var _f1724 = Array<TypeName>();
    var _mode1727 = input.unsigned();
    if (_mode1727 == 2) {
        var _changed1713 = HashMap<ulong, TypeName>();
        ulong _bi1728 = 0;
        var _n1725 = input.count();
        for (var _ in 0.._n1725) {
            var _at1729 = input.unsigned();
            while (_f1724.count < _at1729 or (input.merging and _bi1728 < base.func_specs.count)) {
                var _c = _changed1713.try_get(_bi1728);
                _f1724.append(_c.is_value() ? _c.value() : base.func_specs[_bi1728]);
                _bi1728 += 1;
            }
            _f1724.append(_m_TypeName_read(input));
        }
        while (_bi1728 < base.func_specs.count) {
            var _c = _changed1713.try_get(_bi1728);
            _f1724.append(_c.is_value() ? _c.value() : base.func_specs[_bi1728]);
            _bi1728 += 1;
        }
    } else if (_mode1727 == 3) {
        var _n1725 = input.count();
        for (var _ in 0.._n1725) {
            _f1724.append(_m_TypeName_read(input));
        }
    } else {
        var _n1725 = input.count();
        if (input.merging) {
            input.error = "func_specs" + " written by place";
        }
        for (var _ in 0.._n1725) {
            var _tag1726 = input.unsigned();
            if (_tag1726 & 1 == 1) {
                if (!input.merging) {
                    _f1724.append(base.func_specs[_tag1726 >> 1]);
                }
            } else {
                var _read = _m_TypeName_read(input);
                if (!input.merging or true) {
                    _f1724.append(_read);
                }
            }
        }
    }
    var _f1736 = Array<TypeAliasDef>();
    var _n1737 = input.count();
    if (input.merging) {
        for (var _b in base.type_aliases) {
            _f1736.append(_b);
        }
    }
    for (var _ in 0.._n1737) {
        var _tag1738 = input.unsigned();
        if (_tag1738 & 1 == 1) {
            if (!input.merging) {
                _f1736.append(base.type_aliases[_tag1738 >> 1]);
            }
        } else {
            var _read = _m_TypeAliasDef_read(input);
            if (!input.merging or false) {
                _f1736.append(_read);
            }
        }
    }
    var _f1752 = Array<Withheld>();
    var _mode1755 = input.unsigned();
    if (_mode1755 == 2) {
        var _changed1741 = HashMap<ulong, Withheld>();
        ulong _bi1756 = 0;
        var _n1753 = input.count();
        for (var _ in 0.._n1753) {
            var _at1757 = input.unsigned();
            while (_f1752.count < _at1757 or (input.merging and _bi1756 < base.withheld.count)) {
                var _c = _changed1741.try_get(_bi1756);
                _f1752.append(_c.is_value() ? _c.value() : base.withheld[_bi1756]);
                _bi1756 += 1;
            }
            _f1752.append(_m_Withheld_read(input));
        }
        while (_bi1756 < base.withheld.count) {
            var _c = _changed1741.try_get(_bi1756);
            _f1752.append(_c.is_value() ? _c.value() : base.withheld[_bi1756]);
            _bi1756 += 1;
        }
    } else if (_mode1755 == 3) {
        var _n1753 = input.count();
        for (var _ in 0.._n1753) {
            _f1752.append(_m_Withheld_read(input));
        }
    } else {
        var _n1753 = input.count();
        if (input.merging) {
            input.error = "withheld" + " written by place";
        }
        for (var _ in 0.._n1753) {
            var _tag1754 = input.unsigned();
            if (_tag1754 & 1 == 1) {
                if (!input.merging) {
                    _f1752.append(base.withheld[_tag1754 >> 1]);
                }
            } else {
                var _read = _m_Withheld_read(input);
                if (!input.merging or true) {
                    _f1752.append(_read);
                }
            }
        }
    }
    var _f1771 = Array<PropertyDef>();
    var _mode1774 = input.unsigned();
    if (_mode1774 == 2) {
        var _changed1760 = HashMap<ulong, PropertyDef>();
        ulong _bi1775 = 0;
        var _n1772 = input.count();
        for (var _ in 0.._n1772) {
            var _at1776 = input.unsigned();
            while (_f1771.count < _at1776 or (input.merging and _bi1775 < base.properties.count)) {
                var _c = _changed1760.try_get(_bi1775);
                _f1771.append(_c.is_value() ? _c.value() : base.properties[_bi1775]);
                _bi1775 += 1;
            }
            _f1771.append(_m_PropertyDef_read(input));
        }
        while (_bi1775 < base.properties.count) {
            var _c = _changed1760.try_get(_bi1775);
            _f1771.append(_c.is_value() ? _c.value() : base.properties[_bi1775]);
            _bi1775 += 1;
        }
    } else if (_mode1774 == 3) {
        var _n1772 = input.count();
        for (var _ in 0.._n1772) {
            _f1771.append(_m_PropertyDef_read(input));
        }
    } else {
        var _n1772 = input.count();
        if (input.merging) {
            input.error = "properties" + " written by place";
        }
        for (var _ in 0.._n1772) {
            var _tag1773 = input.unsigned();
            if (_tag1773 & 1 == 1) {
                if (!input.merging) {
                    _f1771.append(base.properties[_tag1773 >> 1]);
                }
            } else {
                var _read = _m_PropertyDef_read(input);
                if (!input.merging or true) {
                    _f1771.append(_read);
                }
            }
        }
    }
    var _f1790 = Array<TypeUse>();
    var _mode1793 = input.unsigned();
    if (_mode1793 == 2) {
        var _changed1779 = HashMap<ulong, TypeUse>();
        ulong _bi1794 = 0;
        var _n1791 = input.count();
        for (var _ in 0.._n1791) {
            var _at1795 = input.unsigned();
            while (_f1790.count < _at1795 or (input.merging and _bi1794 < base.type_uses.count)) {
                var _c = _changed1779.try_get(_bi1794);
                _f1790.append(_c.is_value() ? _c.value() : base.type_uses[_bi1794]);
                _bi1794 += 1;
            }
            _f1790.append(_m_TypeUse_read(input));
        }
        while (_bi1794 < base.type_uses.count) {
            var _c = _changed1779.try_get(_bi1794);
            _f1790.append(_c.is_value() ? _c.value() : base.type_uses[_bi1794]);
            _bi1794 += 1;
        }
    } else if (_mode1793 == 3) {
        var _n1791 = input.count();
        for (var _ in 0.._n1791) {
            _f1790.append(_m_TypeUse_read(input));
        }
    } else {
        var _n1791 = input.count();
        if (input.merging) {
            input.error = "type_uses" + " written by place";
        }
        for (var _ in 0.._n1791) {
            var _tag1792 = input.unsigned();
            if (_tag1792 & 1 == 1) {
                if (!input.merging) {
                    _f1790.append(base.type_uses[_tag1792 >> 1]);
                }
            } else {
                var _read = _m_TypeUse_read(input);
                if (!input.merging or true) {
                    _f1790.append(_read);
                }
            }
        }
    }
    var _f1809 = Array<UseContext>();
    var _mode1812 = input.unsigned();
    if (_mode1812 == 2) {
        var _changed1798 = HashMap<ulong, UseContext>();
        ulong _bi1813 = 0;
        var _n1810 = input.count();
        for (var _ in 0.._n1810) {
            var _at1814 = input.unsigned();
            while (_f1809.count < _at1814 or (input.merging and _bi1813 < base.use_contexts.count)) {
                var _c = _changed1798.try_get(_bi1813);
                _f1809.append(_c.is_value() ? _c.value() : base.use_contexts[_bi1813]);
                _bi1813 += 1;
            }
            _f1809.append(_m_UseContext_read(input));
        }
        while (_bi1813 < base.use_contexts.count) {
            var _c = _changed1798.try_get(_bi1813);
            _f1809.append(_c.is_value() ? _c.value() : base.use_contexts[_bi1813]);
            _bi1813 += 1;
        }
    } else if (_mode1812 == 3) {
        var _n1810 = input.count();
        for (var _ in 0.._n1810) {
            _f1809.append(_m_UseContext_read(input));
        }
    } else {
        var _n1810 = input.count();
        if (input.merging) {
            input.error = "use_contexts" + " written by place";
        }
        for (var _ in 0.._n1810) {
            var _tag1811 = input.unsigned();
            if (_tag1811 & 1 == 1) {
                if (!input.merging) {
                    _f1809.append(base.use_contexts[_tag1811 >> 1]);
                }
            } else {
                var _read = _m_UseContext_read(input);
                if (!input.merging or true) {
                    _f1809.append(_read);
                }
            }
        }
    }
    var _f1830 = Array<(Loc, ulong, Loc)>();
    var _tag1831 = input.unsigned();
    if (_tag1831 == 1) {
        input.unsigned();
        for (var _i1819 in 0..base.literal_args.count) {
            _f1830.append(base.literal_args[_i1819]);
        }
        var _more1833 = input.count();
        for (var _ in 0.._more1833) {
            var _t1834 = input.loc();
            var _t1835 = input.unsigned();
            var _t1836 = input.loc();
            _f1830.append((_t1834, _t1835, _t1836));
        }
    } else {
        var _v1837 = Array<(Loc, ulong, Loc)>();
        var _n1838 = input.count();
        for (var _ in 0.._n1838) {
            var _t1839 = input.loc();
            var _t1840 = input.unsigned();
            var _t1841 = input.loc();
            _v1837.append((_t1839, _t1840, _t1841));
        }
        _f1830 = _v1837;
    }
    var _f1859 = Array<TypeAliasDef>();
    var _mode1862 = input.unsigned();
    if (_mode1862 == 2) {
        var _changed1848 = HashMap<ulong, TypeAliasDef>();
        ulong _bi1863 = 0;
        var _n1860 = input.count();
        for (var _ in 0.._n1860) {
            var _at1864 = input.unsigned();
            while (_f1859.count < _at1864 or (input.merging and _bi1863 < base.constrained_aliases.count)) {
                var _c = _changed1848.try_get(_bi1863);
                _f1859.append(_c.is_value() ? _c.value() : base.constrained_aliases[_bi1863]);
                _bi1863 += 1;
            }
            _f1859.append(_m_TypeAliasDef_read(input));
        }
        while (_bi1863 < base.constrained_aliases.count) {
            var _c = _changed1848.try_get(_bi1863);
            _f1859.append(_c.is_value() ? _c.value() : base.constrained_aliases[_bi1863]);
            _bi1863 += 1;
        }
    } else if (_mode1862 == 3) {
        var _n1860 = input.count();
        for (var _ in 0.._n1860) {
            _f1859.append(_m_TypeAliasDef_read(input));
        }
    } else {
        var _n1860 = input.count();
        if (input.merging) {
            input.error = "constrained_aliases" + " written by place";
        }
        for (var _ in 0.._n1860) {
            var _tag1861 = input.unsigned();
            if (_tag1861 & 1 == 1) {
                if (!input.merging) {
                    _f1859.append(base.constrained_aliases[_tag1861 >> 1]);
                }
            } else {
                var _read = _m_TypeAliasDef_read(input);
                if (!input.merging or true) {
                    _f1859.append(_read);
                }
            }
        }
    }
    var _f1878 = Array<TraitType>();
    var _mode1881 = input.unsigned();
    if (_mode1881 == 2) {
        var _changed1867 = HashMap<ulong, TraitType>();
        ulong _bi1882 = 0;
        var _n1879 = input.count();
        for (var _ in 0.._n1879) {
            var _at1883 = input.unsigned();
            while (_f1878.count < _at1883 or (input.merging and _bi1882 < base.trait_types.count)) {
                var _c = _changed1867.try_get(_bi1882);
                _f1878.append(_c.is_value() ? _c.value() : base.trait_types[_bi1882]);
                _bi1882 += 1;
            }
            _f1878.append(_m_TraitType_read(input));
        }
        while (_bi1882 < base.trait_types.count) {
            var _c = _changed1867.try_get(_bi1882);
            _f1878.append(_c.is_value() ? _c.value() : base.trait_types[_bi1882]);
            _bi1882 += 1;
        }
    } else if (_mode1881 == 3) {
        var _n1879 = input.count();
        for (var _ in 0.._n1879) {
            _f1878.append(_m_TraitType_read(input));
        }
    } else {
        var _n1879 = input.count();
        if (input.merging) {
            input.error = "trait_types" + " written by place";
        }
        for (var _ in 0.._n1879) {
            var _tag1880 = input.unsigned();
            if (_tag1880 & 1 == 1) {
                if (!input.merging) {
                    _f1878.append(base.trait_types[_tag1880 >> 1]);
                }
            } else {
                var _read = _m_TraitType_read(input);
                if (!input.merging or true) {
                    _f1878.append(_read);
                }
            }
        }
    }
    var _v1889 = Array<Conversion>();
    var _n1890 = input.count();
    for (var _ in 0.._n1890) {
        _v1889.append(_m_Conversion_read(input));
    }
    var _f1891 = _v1889;
    var _f1918 = Map<String, Array<String>>();
    var _tag1919 = input.unsigned();
    if (_tag1919 == 1) {
        for (var (_bk1920, _bv) in base.overload_sets) {
            _f1918[_bk1920] = _bv;
        }
        var _v1921 = Map<String, Array<String>>();
        var _n1922 = input.count();
        for (var _ in 0.._n1922) {
            var _k1923 = input.text();
            var _v1924 = Array<String>();
            var _n1925 = input.count();
            for (var _ in 0.._n1925) {
                _v1924.append(input.text());
            }
            _v1921[_k1923] = _v1924;
        }
        for (var (_bk1920, _av) in _v1921) {
            _f1918[_bk1920] = _av;
        }
    } else {
        var _v1926 = Map<String, Array<String>>();
        var _n1927 = input.count();
        for (var _ in 0.._n1927) {
            var _k1928 = input.text();
            var _v1929 = Array<String>();
            var _n1930 = input.count();
            for (var _ in 0.._n1930) {
                _v1929.append(input.text());
            }
            _v1926[_k1928] = _v1929;
        }
        _f1918 = _v1926;
    }
    var _f1965 = Map<String, Array<Array<String>>>();
    var _tag1966 = input.unsigned();
    if (_tag1966 == 1) {
        for (var (_bk1967, _bv) in base.overload_unions) {
            _f1965[_bk1967] = _bv;
        }
        var _v1968 = Map<String, Array<Array<String>>>();
        var _n1969 = input.count();
        for (var _ in 0.._n1969) {
            var _k1970 = input.text();
            var _v1971 = Array<Array<String>>();
            var _n1972 = input.count();
            for (var _ in 0.._n1972) {
                var _v1973 = Array<String>();
                var _n1974 = input.count();
                for (var _ in 0.._n1974) {
                    _v1973.append(input.text());
                }
                _v1971.append(_v1973);
            }
            _v1968[_k1970] = _v1971;
        }
        for (var (_bk1967, _av) in _v1968) {
            _f1965[_bk1967] = _av;
        }
    } else {
        var _v1975 = Map<String, Array<Array<String>>>();
        var _n1976 = input.count();
        for (var _ in 0.._n1976) {
            var _k1977 = input.text();
            var _v1978 = Array<Array<String>>();
            var _n1979 = input.count();
            for (var _ in 0.._n1979) {
                var _v1980 = Array<String>();
                var _n1981 = input.count();
                for (var _ in 0.._n1981) {
                    _v1980.append(input.text());
                }
                _v1978.append(_v1980);
            }
            _v1975[_k1977] = _v1978;
        }
        _f1965 = _v1975;
    }
    var _f2052 = Map<String, Map<String, Array<String>>>();
    var _tag2053 = input.unsigned();
    if (_tag2053 == 1) {
        for (var (_bk2054, _bv) in base.method_overload_sets) {
            _f2052[_bk2054] = _bv;
        }
        var _v2055 = Map<String, Map<String, Array<String>>>();
        var _n2056 = input.count();
        for (var _ in 0.._n2056) {
            var _k2057 = input.text();
            var _v2058 = Map<String, Array<String>>();
            var _n2059 = input.count();
            for (var _ in 0.._n2059) {
                var _k2060 = input.text();
                var _v2061 = Array<String>();
                var _n2062 = input.count();
                for (var _ in 0.._n2062) {
                    _v2061.append(input.text());
                }
                _v2058[_k2060] = _v2061;
            }
            _v2055[_k2057] = _v2058;
        }
        for (var (_bk2054, _av) in _v2055) {
            _f2052[_bk2054] = _av;
        }
    } else {
        var _v2063 = Map<String, Map<String, Array<String>>>();
        var _n2064 = input.count();
        for (var _ in 0.._n2064) {
            var _k2065 = input.text();
            var _v2066 = Map<String, Array<String>>();
            var _n2067 = input.count();
            for (var _ in 0.._n2067) {
                var _k2068 = input.text();
                var _v2069 = Array<String>();
                var _n2070 = input.count();
                for (var _ in 0.._n2070) {
                    _v2069.append(input.text());
                }
                _v2066[_k2068] = _v2069;
            }
            _v2063[_k2065] = _v2066;
        }
        _f2052 = _v2063;
    }
    var _f2078 = _m_ExtensionScopes_read(input);
    var _f2098 = HashSet<Loc>();
    var _tag2099 = input.unsigned();
    if (_tag2099 == 1) {
        for (var _bk2100 in base.private_functions) {
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
    var _f2124 = HashSet<Loc>();
    var _tag2125 = input.unsigned();
    if (_tag2125 == 1) {
        for (var _bk2126 in base.file_private_functions) {
            _f2124.insert(_bk2126);
        }
        var _v2127 = HashSet<Loc>();
        var _n2128 = input.count();
        for (var _ in 0.._n2128) {
            _v2127.insert(input.loc());
        }
        for (var _bk2126 in _v2127) {
            _f2124.insert(_bk2126);
        }
    } else {
        var _v2129 = HashSet<Loc>();
        var _n2130 = input.count();
        for (var _ in 0.._n2130) {
            _v2129.insert(input.loc());
        }
        _f2124 = _v2129;
    }
    var _f2142 = Array<(Loc, String)>();
    var _tag2143 = input.unsigned();
    if (_tag2143 == 1) {
        input.unsigned();
        for (var _i2134 in 0..base.call_targets.count) {
            _f2142.append(base.call_targets[_i2134]);
        }
        var _more2145 = input.count();
        for (var _ in 0.._more2145) {
            var _t2146 = input.loc();
            var _t2147 = input.text();
            _f2142.append((_t2146, _t2147));
        }
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
    var _f2168 = Array<(Loc, String)>();
    var _tag2169 = input.unsigned();
    if (_tag2169 == 1) {
        var _v2170 = Array<(Loc, String)>();
        var _n2171 = input.count();
        for (var _ in 0.._n2171) {
            var _t2172 = input.loc();
            var _t2173 = input.text();
            _v2170.append((_t2172, _t2173));
        }
        _f2168 = merge_by_place(base.argument_names, _v2170);
    } else {
        var _v2174 = Array<(Loc, String)>();
        var _n2175 = input.count();
        for (var _ in 0.._n2175) {
            var _t2176 = input.loc();
            var _t2177 = input.text();
            _v2174.append((_t2176, _t2177));
        }
        _f2168 = _v2174;
    }
    var _f2187 = Array<String>();
    var _tag2188 = input.unsigned();
    if (_tag2188 == 1) {
        input.unsigned();
        for (var _i2183 in 0..base.namespaces.count) {
            _f2187.append(base.namespaces[_i2183]);
        }
        var _more2190 = input.count();
        for (var _ in 0.._more2190) {
            _f2187.append(input.text());
        }
    } else {
        var _v2191 = Array<String>();
        var _n2192 = input.count();
        for (var _ in 0.._n2192) {
            _v2191.append(input.text());
        }
        _f2187 = _v2191;
    }
    var _f2200 = Array<bool>();
    var _tag2201 = input.unsigned();
    if (_tag2201 == 1) {
        input.unsigned();
        for (var _i2198 in 0..base.cached_files.count) {
            _f2200.append(base.cached_files[_i2198]);
        }
        var _more2203 = input.count();
        for (var _ in 0.._more2203) {
            _f2200.append(input.flag());
        }
    } else {
        var _v2204 = Array<bool>();
        var _n2205 = input.count();
        for (var _ in 0.._n2205) {
            _v2204.append(input.flag());
        }
        _f2200 = _v2204;
    }
    var _f2223 = HashMap<Loc, String>();
    var _tag2224 = input.unsigned();
    if (_tag2224 == 1) {
        for (var (_bk2225, _bv) in base.recorded_summaries) {
            _f2223[_bk2225] = _bv;
        }
        var _v2226 = HashMap<Loc, String>();
        var _n2227 = input.count();
        for (var _ in 0.._n2227) {
            var _k2228 = input.loc();
            _v2226[_k2228] = input.text();
        }
        for (var (_bk2225, _av) in _v2226) {
            _f2223[_bk2225] = _av;
        }
    } else {
        var _v2229 = HashMap<Loc, String>();
        var _n2230 = input.count();
        for (var _ in 0.._n2230) {
            var _k2231 = input.loc();
            _v2229[_k2231] = input.text();
        }
        _f2223 = _v2229;
    }
    var _f2247 = HashSet<Loc>();
    var _tag2248 = input.unsigned();
    if (_tag2248 == 1) {
        for (var _bk2249 in base.stripped) {
            _f2247.insert(_bk2249);
        }
        var _v2250 = HashSet<Loc>();
        var _n2251 = input.count();
        for (var _ in 0.._n2251) {
            _v2250.insert(input.loc());
        }
        for (var _bk2249 in _v2250) {
            _f2247.insert(_bk2249);
        }
    } else {
        var _v2252 = HashSet<Loc>();
        var _n2253 = input.count();
        for (var _ in 0.._n2253) {
            _v2252.insert(input.loc());
        }
        _f2247 = _v2252;
    }
    var _frozen = input.flag();
    var _f2264 = Array<StructDef>();
    var _mode2267 = input.unsigned();
    if (_mode2267 == 2) {
        var _patched2270 = HashMap<ulong, StructDef>();
        var _n2265 = input.count();
        for (var _ in 0.._n2265) {
            var _name = input.text();
            var _slot = input.unsigned();
            if (input.merging) {
                _slot = struct_named(base.templates.structs, _name);
            }
            if (_slot >= base.templates.structs.count) {
                input.error = $"no struct {_name} to patch";
                break;
            }
            _patched2270[_slot] = _patch_t_read(input, base.templates.structs[_slot]);
        }
        ulong _bi2268 = 0;
        var _added = input.count();
        for (var _ in 0.._added) {
            var _at2269 = input.unsigned();
            while (_f2264.count < _at2269 or (input.merging and _bi2268 < base.templates.structs.count)) {
                var _p = _patched2270.try_get(_bi2268);
                _f2264.append(_p.is_value() ? _p.value() : base.templates.structs[_bi2268]);
                _bi2268 += 1;
            }
            _f2264.append(_m_StructDef_read(input));
        }
        while (_bi2268 < base.templates.structs.count) {
            var _p = _patched2270.try_get(_bi2268);
            _f2264.append(_p.is_value() ? _p.value() : base.templates.structs[_bi2268]);
            _bi2268 += 1;
        }
    } else {
        if (input.merging) {
            input.error = "structs written by place";
        }
        var _n2265 = input.count();
        for (var _ in 0.._n2265) {
            var _tag2266 = input.unsigned();
            if (_tag2266 & 1 == 1) {
                _f2264.append(
                    base.templates.structs[(_tag2266 >> 1) < base.templates.structs.count ? _tag2266 >> 1 : 0]
                );
            } else if (_tag2266 == 2) {
                var _was = base.templates.structs[input.unsigned()];
                _f2264.append(_patch_t_read(input, _was));
            } else {
                _f2264.append(_m_StructDef_read(input));
            }
        }
    }
    var _f2284 = Array<FunctionDef>();
    var _mode2287 = input.unsigned();
    if (_mode2287 == 2) {
        var _changed2273 = HashMap<ulong, FunctionDef>();
        var _nc2275 = input.count();
        for (var _ in 0.._nc2275) {
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
                _changed2273[_slot] = _el;
            } else {
                input.error = $"no {_name} to change";
            }
        }
        ulong _bi2288 = 0;
        var _n2285 = input.count();
        for (var _ in 0.._n2285) {
            var _at2289 = input.unsigned();
            while (_f2284.count < _at2289 or (input.merging and _bi2288 < base.templates.functions.count)) {
                var _c = _changed2273.try_get(_bi2288);
                _f2284.append(_c.is_value() ? _c.value() : base.templates.functions[_bi2288]);
                _bi2288 += 1;
            }
            _f2284.append(_m_FunctionDef_read(input));
        }
        while (_bi2288 < base.templates.functions.count) {
            var _c = _changed2273.try_get(_bi2288);
            _f2284.append(_c.is_value() ? _c.value() : base.templates.functions[_bi2288]);
            _bi2288 += 1;
        }
    } else if (_mode2287 == 3) {
        var _n2285 = input.count();
        for (var _ in 0.._n2285) {
            _f2284.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2285 = input.count();
        if (input.merging) {
            input.error = "tf" + " written by place";
        }
        for (var _ in 0.._n2285) {
            var _tag2286 = input.unsigned();
            if (_tag2286 & 1 == 1) {
                if (!input.merging) {
                    _f2284.append(base.templates.functions[_tag2286 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2284.append(_read);
                }
            }
        }
    }
    var _f2291 = Templates(_frozen, _f2264, _f2284);
    var _f2292 = DeltaBase.read_checked(input, base.checked);
    var _f2312 = HashMap<String, SpecRequest>();
    var _tag2313 = input.unsigned();
    if (_tag2313 == 1) {
        for (var (_bk2314, _bv) in base.spec_requests) {
            _f2312[_bk2314] = _bv;
        }
        var _v2315 = HashMap<String, SpecRequest>();
        var _n2316 = input.count();
        for (var _ in 0.._n2316) {
            var _k2317 = input.text();
            _v2315[_k2317] = _m_SpecRequest_read(input);
        }
        for (var (_bk2314, _av) in _v2315) {
            _f2312[_bk2314] = _av;
        }
    } else {
        var _v2318 = HashMap<String, SpecRequest>();
        var _n2319 = input.count();
        for (var _ in 0.._n2319) {
            var _k2320 = input.text();
            _v2318[_k2320] = _m_SpecRequest_read(input);
        }
        _f2312 = _v2318;
    }
    var _f2321 = input.flag();
    var _f2333 = Array<(Loc, String)>();
    var _tag2334 = input.unsigned();
    if (_tag2334 == 1) {
        input.unsigned();
        for (var _i2325 in 0..base.summaries_to_record.count) {
            _f2333.append(base.summaries_to_record[_i2325]);
        }
        var _more2336 = input.count();
        for (var _ in 0.._more2336) {
            var _t2337 = input.loc();
            var _t2338 = input.text();
            _f2333.append((_t2337, _t2338));
        }
    } else {
        var _v2339 = Array<(Loc, String)>();
        var _n2340 = input.count();
        for (var _ in 0.._n2340) {
            var _t2341 = input.loc();
            var _t2342 = input.text();
            _v2339.append((_t2341, _t2342));
        }
        _f2333 = _v2339;
    }
    var _f2373 = HashMap<String, Array<bool>>();
    var _tag2374 = input.unsigned();
    if (_tag2374 == 1) {
        for (var (_bk2375, _bv) in base.caller_copies) {
            _f2373[_bk2375] = _bv;
        }
        var _v2376 = HashMap<String, Array<bool>>();
        var _n2377 = input.count();
        for (var _ in 0.._n2377) {
            var _k2378 = input.text();
            var _v2379 = Array<bool>();
            var _n2380 = input.count();
            for (var _ in 0.._n2380) {
                _v2379.append(input.flag());
            }
            _v2376[_k2378] = _v2379;
        }
        for (var (_bk2375, _av) in _v2376) {
            _f2373[_bk2375] = _av;
        }
    } else {
        var _v2381 = HashMap<String, Array<bool>>();
        var _n2382 = input.count();
        for (var _ in 0.._n2382) {
            var _k2383 = input.text();
            var _v2384 = Array<bool>();
            var _n2385 = input.count();
            for (var _ in 0.._n2385) {
                _v2384.append(input.flag());
            }
            _v2381[_k2383] = _v2384;
        }
        _f2373 = _v2381;
    }
    var _f2387 = input.flag();
    return Module(
        _f1519,
        _f1552,
        _f1572,
        _f1591,
        _f1610,
        _f1629,
        _f1648,
        _f1667,
        _f1686,
        _f1705,
        _f1724,
        _f1736,
        _f1752,
        _f1771,
        _f1790,
        _f1809,
        _f1830,
        _f1859,
        _f1878,
        _f1891,
        _f1918,
        _f1965,
        _f2052,
        _f2078,
        _f2098,
        _f2124,
        _f2142,
        _f2168,
        _f2187,
        _f2200,
        _f2223,
        _f2247,
        _f2291,
        _f2292,
        _f2312,
        _f2321,
        _f2333,
        _f2373,
        _f2387
    );
}

_m_Module_index(value: Module, base: DeltaBase) {
    ulong _j1525 = 0;
    for (var _item1507 in value.imports) {
        var scratch = base.scratch();
        _a_Import_write(scratch, _item1507);
        base.add("imports", scratch, _j1525);
        _j1525 += 1;
    }
    if (base.verifying) {
        ulong _j1559 = 0;
        for (var _item1526 in value.structs) {
            var scratch = base.scratch();
            _m_StructDef_write(scratch, _item1526);
            base.add("s", scratch, _j1559);
            base.name("s", _item1526.name, _j1559);
            _patch_s_index(_item1526, base, _j1559);
            _j1559 += 1;
        }
    }
    base.ref_structs = value.structs.clone();
    base.ref_struct_parts = Array<StructDef>();
    for (var _item1526 in value.structs) {
        base.ref_struct_parts.append(_m_StructDef_shallow(_item1526));
    }
    ulong _j1578 = 0;
    for (var _item1560 in value.traits) {
        var scratch = base.scratch();
        _m_TraitDef_write(scratch, _item1560);
        base.add("traits", scratch, _j1578);
        _j1578 += 1;
    }
    ulong _j1597 = 0;
    for (var _item1579 in value.extensions) {
        var scratch = base.scratch();
        _m_ExtensionDef_write(scratch, _item1579);
        base.add("extensions", scratch, _j1597);
        _j1597 += 1;
    }
    if (base.verifying) {
        ulong _j1616 = 0;
        for (var _item1598 in value.functions) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item1598);
            base.add("functions", scratch, _j1616);
            base.name("functions", _item1598.name, _j1616);
            _j1616 += 1;
        }
    }
    base.ref_functions = value.functions.clone();
    ulong _j1635 = 0;
    for (var _item1617 in value.externs) {
        var scratch = base.scratch();
        _m_ExternDef_write(scratch, _item1617);
        base.add("externs", scratch, _j1635);
        _j1635 += 1;
    }
    ulong _j1654 = 0;
    for (var _item1636 in value.globals) {
        var scratch = base.scratch();
        _m_VariableDef_write(scratch, _item1636);
        base.add("globals", scratch, _j1654);
        _j1654 += 1;
    }
    ulong _j1673 = 0;
    for (var _item1655 in value.static_blocks) {
        var scratch = base.scratch();
        _m_ModuleStaticBlock_write(scratch, _item1655);
        base.add("static_blocks", scratch, _j1673);
        _j1673 += 1;
    }
    ulong _j1692 = 0;
    for (var _item1674 in value.enums) {
        var scratch = base.scratch();
        _m_EnumDef_write(scratch, _item1674);
        base.add("enums", scratch, _j1692);
        _j1692 += 1;
    }
    ulong _j1711 = 0;
    for (var _item1693 in value.struct_specs) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item1693);
        base.add("struct_specs", scratch, _j1711);
        _j1711 += 1;
    }
    ulong _j1730 = 0;
    for (var _item1712 in value.func_specs) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item1712);
        base.add("func_specs", scratch, _j1730);
        _j1730 += 1;
    }
    ulong _j1739 = 0;
    for (var _item1731 in value.type_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1731);
        base.add("type_aliases", scratch, _j1739);
        _j1739 += 1;
    }
    ulong _j1758 = 0;
    for (var _item1740 in value.withheld) {
        var scratch = base.scratch();
        _m_Withheld_write(scratch, _item1740);
        base.add("withheld", scratch, _j1758);
        _j1758 += 1;
    }
    ulong _j1777 = 0;
    for (var _item1759 in value.properties) {
        var scratch = base.scratch();
        _m_PropertyDef_write(scratch, _item1759);
        base.add("properties", scratch, _j1777);
        _j1777 += 1;
    }
    ulong _j1796 = 0;
    for (var _item1778 in value.type_uses) {
        var scratch = base.scratch();
        _m_TypeUse_write(scratch, _item1778);
        base.add("type_uses", scratch, _j1796);
        _j1796 += 1;
    }
    ulong _j1815 = 0;
    for (var _item1797 in value.use_contexts) {
        var scratch = base.scratch();
        _m_UseContext_write(scratch, _item1797);
        base.add("use_contexts", scratch, _j1815);
        _j1815 += 1;
    }
    var _xscratch1842 = base.scratch();
    for (var _xitem1843 in value.literal_args) {
        var (_t1844, _t1845, _t1846) = _xitem1843;
        _xscratch1842.loc(_t1844);
        _xscratch1842.unsigned(_t1845);
        _xscratch1842.loc(_t1846);
    }
    base.keep_list("literal_args", value.literal_args.count, _xscratch1842);
    ulong _j1865 = 0;
    for (var _item1847 in value.constrained_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1847);
        base.add("constrained_aliases", scratch, _j1865);
        _j1865 += 1;
    }
    ulong _j1884 = 0;
    for (var _item1866 in value.trait_types) {
        var scratch = base.scratch();
        _m_TraitType_write(scratch, _item1866);
        base.add("trait_types", scratch, _j1884);
        _j1884 += 1;
    }
    ulong _cj1888 = 0;
    for (var _conv1886 in value.conversions) {
        var _own1887 = RecordOut();
        _own1887.blank_locs = true;
        _m_Conversion_write(_own1887, _conv1886);
        base.add_hashed("conversions", interface_text(_own1887), _cj1888);
        _cj1888 += 1;
    }
    for (var (_key1892, _) in value.overload_sets) {
        var _kscratch1893 = base.scratch();
        _kscratch1893.text(_key1892);
        var _vscratch1894 = base.scratch();
        _vscratch1894.unsigned(value.overload_sets[_key1892].count);
        for (var _item1931 in value.overload_sets[_key1892]) {
            _vscratch1894.text(_item1931);
        }
        base.keep_entry("overload_sets", _kscratch1893, _vscratch1894);
    }
    for (var (_key1932, _) in value.overload_unions) {
        var _kscratch1933 = base.scratch();
        _kscratch1933.text(_key1932);
        var _vscratch1934 = base.scratch();
        _vscratch1934.unsigned(value.overload_unions[_key1932].count);
        for (var _item1982 in value.overload_unions[_key1932]) {
            _vscratch1934.unsigned(_item1982.count);
            for (var _item1983 in _item1982) {
                _vscratch1934.text(_item1983);
            }
        }
        base.keep_entry("overload_unions", _kscratch1933, _vscratch1934);
    }
    for (var (_key1984, _) in value.method_overload_sets) {
        var _kscratch1985 = base.scratch();
        _kscratch1985.text(_key1984);
        var _vscratch1986 = base.scratch();
        var _keys2072 = Array<(u8[], u8[], String)>();
        for (var (_key2071, _) in value.method_overload_sets[_key1984]) {
            var _scratch2073 = _vscratch1986.scratch();
            _scratch2073.text(_key2071);
            var _vscratch2075 = _vscratch1986.scratch();
            _vscratch2075.unsigned(value.method_overload_sets[_key1984][_key2071].count);
            for (var _item2076 in value.method_overload_sets[_key1984][_key2071]) {
                _vscratch2075.text(_item2076);
            }
            _keys2072.append((_scratch2073.finish(), _vscratch2075.finish(), _key2071));
        }
        _keys2072.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        _vscratch1986.unsigned(_keys2072.count);
        for (var (_bytes2074, _, _key2071) in _keys2072) {
            _vscratch1986.text(_key2071);
            _vscratch1986.unsigned(value.method_overload_sets[_key1984][_key2071].count);
            for (var _item2077 in value.method_overload_sets[_key1984][_key2071]) {
                _vscratch1986.text(_item2077);
            }
        }
        base.keep_entry("method_overload_sets", _kscratch1985, _vscratch1986);
    }
    for (var _key2079 in value.private_functions) {
        var _kscratch2080 = base.scratch();
        _kscratch2080.loc(_key2079);
        var _vscratch2081 = base.scratch();
        base.keep_entry("private_functions", _kscratch2080, _vscratch2081);
    }
    for (var _key2105 in value.file_private_functions) {
        var _kscratch2106 = base.scratch();
        _kscratch2106.loc(_key2105);
        var _vscratch2107 = base.scratch();
        base.keep_entry("file_private_functions", _kscratch2106, _vscratch2107);
    }
    var _xscratch2152 = base.scratch();
    for (var _xitem2153 in value.call_targets) {
        var (_t2154, _t2155) = _xitem2153;
        _xscratch2152.loc(_t2154);
        _xscratch2152.text(_t2155);
    }
    base.keep_list("call_targets", value.call_targets.count, _xscratch2152);
    for (var _item2156 in value.argument_names) {
        var _escratch2157 = base.scratch();
        var (_t2178, _t2179) = _item2156;
        _escratch2157.loc(_t2178);
        _escratch2157.text(_t2179);
        base.keep_entry("argument_names", _escratch2157, base.scratch());
    }
    var _xscratch2193 = base.scratch();
    for (var _xitem2194 in value.namespaces) {
        _xscratch2193.text(_xitem2194);
    }
    base.keep_list("namespaces", value.namespaces.count, _xscratch2193);
    var _xscratch2206 = base.scratch();
    for (var _xitem2207 in value.cached_files) {
        _xscratch2206.flag(_xitem2207);
    }
    base.keep_list("cached_files", value.cached_files.count, _xscratch2206);
    for (var (_key2208, _) in value.recorded_summaries) {
        var _kscratch2209 = base.scratch();
        _kscratch2209.loc(_key2208);
        var _vscratch2210 = base.scratch();
        _vscratch2210.text(value.recorded_summaries[_key2208]);
        base.keep_entry("recorded_summaries", _kscratch2209, _vscratch2210);
    }
    for (var _key2232 in value.stripped) {
        var _kscratch2233 = base.scratch();
        _kscratch2233.loc(_key2232);
        var _vscratch2234 = base.scratch();
        base.keep_entry("stripped", _kscratch2233, _vscratch2234);
    }
    if (base.verifying) {
        ulong _j2271 = 0;
        for (var _item2254 in value.templates.structs) {
            var scratch = base.scratch();
            _m_StructDef_write(scratch, _item2254);
            base.add("t", scratch, _j2271);
            base.name("t", _item2254.name, _j2271);
            _patch_t_index(_item2254, base, _j2271);
            _j2271 += 1;
        }
    }
    base.ref_templates = value.templates.structs.clone();
    base.ref_template_parts = Array<StructDef>();
    for (var _item2254 in value.templates.structs) {
        base.ref_template_parts.append(_m_StructDef_shallow(_item2254));
    }
    if (base.verifying) {
        ulong _j2290 = 0;
        for (var _item2272 in value.templates.functions) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2272);
            base.add("tf", scratch, _j2290);
            base.name("tf", _item2272.name, _j2290);
            _j2290 += 1;
        }
    }
    base.ref_template_functions = value.templates.functions.clone();
    base.keep_checked(value.checked);
    for (var (_key2293, _) in value.spec_requests) {
        var _kscratch2294 = base.scratch();
        _kscratch2294.text(_key2293);
        var _vscratch2295 = base.scratch();
        _m_SpecRequest_write(_vscratch2295, value.spec_requests[_key2293]);
        base.keep_entry("spec_requests", _kscratch2294, _vscratch2295);
    }
    var _xscratch2343 = base.scratch();
    for (var _xitem2344 in value.summaries_to_record) {
        var (_t2345, _t2346) = _xitem2344;
        _xscratch2343.loc(_t2345);
        _xscratch2343.text(_t2346);
    }
    base.keep_list("summaries_to_record", value.summaries_to_record.count, _xscratch2343);
    for (var (_key2347, _) in value.caller_copies) {
        var _kscratch2348 = base.scratch();
        _kscratch2348.text(_key2347);
        var _vscratch2349 = base.scratch();
        _vscratch2349.unsigned(value.caller_copies[_key2347].count);
        for (var _item2386 in value.caller_copies[_key2347]) {
            _vscratch2349.flag(_item2386);
        }
        base.keep_entry("caller_copies", _kscratch2348, _vscratch2349);
    }
}

_m_Module_index_resumed(value: Module, base: DeltaBase) {
    ulong _j1739 = 0;
    for (var _item1731 in value.type_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1731);
        base.add("type_aliases", scratch, _j1739);
        _j1739 += 1;
    }
    for (var (_key2208, _) in value.recorded_summaries) {
        var _kscratch2209 = base.scratch();
        _kscratch2209.loc(_key2208);
        var _vscratch2210 = base.scratch();
        _vscratch2210.text(value.recorded_summaries[_key2208]);
        base.keep_entry("recorded_summaries", _kscratch2209, _vscratch2210);
    }
    var _xscratch2343 = base.scratch();
    for (var _xitem2344 in value.summaries_to_record) {
        var (_t2345, _t2346) = _xitem2344;
        _xscratch2343.loc(_t2345);
        _xscratch2343.text(_t2346);
    }
    base.keep_list("summaries_to_record", value.summaries_to_record.count, _xscratch2343);
}

_patch_s_write(out: RecordOut, value: StructDef, base: DeltaBase, slot: ulong) {
    out.text(value.name);
    _m_TypeName_write(out, value.ty);
    var _seq2395 = base.ref_struct_parts[slot].generic_params;
    ulong _bj2396 = 0;
    var _news2397 = Array<ulong>();
    for (var _i2398 in 0..value.generic_params.count) {
        if (_bj2396 < _seq2395.count and value.generic_params[_i2398] === _seq2395[_bj2396]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_GenericParam_write(scratch, value.generic_params[_i2398]);
                base.verify_same($"s.{slot}.generic_params", _bj2396, scratch);
            }
            _bj2396 += 1;
        } else if (_bj2396 < _seq2395.count
            and _same_m_GenericParam(value.generic_params[_i2398], _seq2395[_bj2396], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_GenericParam_write(scratch, value.generic_params[_i2398]);
                base.verify_same($"s.{slot}.generic_params", _bj2396, scratch);
            }
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
            _m_GenericParam_write(out, value.generic_params[_i2398]);
        }
        base.count("s.*.generic_params" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.generic_params" + " whole", 0);
        out.unsigned(value.generic_params.count);
        for (var _i2398 in 0..value.generic_params.count) {
            _m_GenericParam_write(out, value.generic_params[_i2398]);
        }
    }
    var _seq2411 = base.ref_struct_parts[slot].field_members;
    ulong _bj2412 = 0;
    var _news2413 = Array<ulong>();
    for (var _i2414 in 0..value.field_members.count) {
        if (_bj2412 < _seq2411.count and value.field_members[_i2414] === _seq2411[_bj2412]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_VariableDef_write(scratch, value.field_members[_i2414]);
                base.verify_same($"s.{slot}.field_members", _bj2412, scratch);
            }
            _bj2412 += 1;
        } else if (_bj2412 < _seq2411.count
            and _same_m_VariableDef(value.field_members[_i2414], _seq2411[_bj2412], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_VariableDef_write(scratch, value.field_members[_i2414]);
                base.verify_same($"s.{slot}.field_members", _bj2412, scratch);
            }
            _bj2412 += 1;
        } else {
            _news2413.append(_i2414);
        }
    }
    if (_bj2412 == _seq2411.count) {
        out.unsigned(2);
        out.unsigned(_news2413.count);
        for (var _i2414 in _news2413) {
            out.unsigned(_i2414);
            _m_VariableDef_write(out, value.field_members[_i2414]);
        }
        base.count("s.*.field_members" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.field_members" + " whole", 0);
        out.unsigned(value.field_members.count);
        for (var _i2414 in 0..value.field_members.count) {
            _m_VariableDef_write(out, value.field_members[_i2414]);
        }
    }
    var _seq2427 = base.ref_struct_parts[slot].method_members;
    ulong _bj2428 = 0;
    var _news2429 = Array<ulong>();
    for (var _i2430 in 0..value.method_members.count) {
        if (_bj2428 < _seq2427.count and value.method_members[_i2430] === _seq2427[_bj2428]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.method_members[_i2430]);
                base.verify_same($"s.{slot}.method_members", _bj2428, scratch);
            }
            _bj2428 += 1;
        } else if (_bj2428 < _seq2427.count
            and _same_m_FunctionDef(value.method_members[_i2430], _seq2427[_bj2428], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.method_members[_i2430]);
                base.verify_same($"s.{slot}.method_members", _bj2428, scratch);
            }
            _bj2428 += 1;
        } else {
            _news2429.append(_i2430);
        }
    }
    if (_bj2428 == _seq2427.count) {
        out.unsigned(2);
        out.unsigned(_news2429.count);
        for (var _i2430 in _news2429) {
            out.unsigned(_i2430);
            _m_FunctionDef_write(out, value.method_members[_i2430]);
        }
        base.count("s.*.method_members" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.method_members" + " whole", 0);
        out.unsigned(value.method_members.count);
        for (var _i2430 in 0..value.method_members.count) {
            _m_FunctionDef_write(out, value.method_members[_i2430]);
        }
    }
    var _seq2443 = base.ref_struct_parts[slot].generic_methods;
    ulong _bj2444 = 0;
    var _news2445 = Array<ulong>();
    for (var _i2446 in 0..value.generic_methods.count) {
        if (_bj2444 < _seq2443.count and value.generic_methods[_i2446] === _seq2443[_bj2444]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.generic_methods[_i2446]);
                base.verify_same($"s.{slot}.generic_methods", _bj2444, scratch);
            }
            _bj2444 += 1;
        } else if (_bj2444 < _seq2443.count
            and _same_m_FunctionDef(value.generic_methods[_i2446], _seq2443[_bj2444], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.generic_methods[_i2446]);
                base.verify_same($"s.{slot}.generic_methods", _bj2444, scratch);
            }
            _bj2444 += 1;
        } else {
            _news2445.append(_i2446);
        }
    }
    if (_bj2444 == _seq2443.count) {
        out.unsigned(2);
        out.unsigned(_news2445.count);
        for (var _i2446 in _news2445) {
            out.unsigned(_i2446);
            _m_FunctionDef_write(out, value.generic_methods[_i2446]);
        }
        base.count("s.*.generic_methods" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.generic_methods" + " whole", 0);
        out.unsigned(value.generic_methods.count);
        for (var _i2446 in 0..value.generic_methods.count) {
            _m_FunctionDef_write(out, value.generic_methods[_i2446]);
        }
    }
    var _seq2459 = base.ref_struct_parts[slot].constructors;
    ulong _bj2460 = 0;
    var _news2461 = Array<ulong>();
    for (var _i2462 in 0..value.constructors.count) {
        if (_bj2460 < _seq2459.count and value.constructors[_i2462] === _seq2459[_bj2460]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.constructors[_i2462]);
                base.verify_same($"s.{slot}.constructors", _bj2460, scratch);
            }
            _bj2460 += 1;
        } else if (_bj2460 < _seq2459.count
            and _same_m_FunctionDef(value.constructors[_i2462], _seq2459[_bj2460], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.constructors[_i2462]);
                base.verify_same($"s.{slot}.constructors", _bj2460, scratch);
            }
            _bj2460 += 1;
        } else {
            _news2461.append(_i2462);
        }
    }
    if (_bj2460 == _seq2459.count) {
        out.unsigned(2);
        out.unsigned(_news2461.count);
        for (var _i2462 in _news2461) {
            out.unsigned(_i2462);
            _m_FunctionDef_write(out, value.constructors[_i2462]);
        }
        base.count("s.*.constructors" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.constructors" + " whole", 0);
        out.unsigned(value.constructors.count);
        for (var _i2462 in 0..value.constructors.count) {
            _m_FunctionDef_write(out, value.constructors[_i2462]);
        }
    }
    _m_FunctionDef_write(out, value.destructor);
    _m_FunctionDef_write(out, value.acquire);
    _m_FunctionDef_write(out, value.release);
    var _seq2478 = base.ref_struct_parts[slot].traits;
    ulong _bj2479 = 0;
    var _news2480 = Array<ulong>();
    for (var _i2481 in 0..value.traits.count) {
        if (_bj2479 < _seq2478.count and value.traits[_i2481] === _seq2478[_bj2479]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_TypeName_write(scratch, value.traits[_i2481]);
                base.verify_same($"s.{slot}.traits", _bj2479, scratch);
            }
            _bj2479 += 1;
        } else if (_bj2479 < _seq2478.count and _same_m_TypeName(value.traits[_i2481], _seq2478[_bj2479], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_TypeName_write(scratch, value.traits[_i2481]);
                base.verify_same($"s.{slot}.traits", _bj2479, scratch);
            }
            _bj2479 += 1;
        } else {
            _news2480.append(_i2481);
        }
    }
    if (_bj2479 == _seq2478.count) {
        out.unsigned(2);
        out.unsigned(_news2480.count);
        for (var _i2481 in _news2480) {
            out.unsigned(_i2481);
            _m_TypeName_write(out, value.traits[_i2481]);
        }
        base.count("s.*.traits" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.traits" + " whole", 0);
        out.unsigned(value.traits.count);
        for (var _i2481 in 0..value.traits.count) {
            _m_TypeName_write(out, value.traits[_i2481]);
        }
    }
    var _seq2494 = base.ref_struct_parts[slot].attributes;
    ulong _bj2495 = 0;
    var _news2496 = Array<ulong>();
    for (var _i2497 in 0..value.attributes.count) {
        if (_bj2495 < _seq2494.count and value.attributes[_i2497] === _seq2494[_bj2495]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _a_Attribute_write(scratch, value.attributes[_i2497]);
                base.verify_same($"s.{slot}.attributes", _bj2495, scratch);
            }
            _bj2495 += 1;
        } else if (_bj2495 < _seq2494.count and _same_a_Attribute(value.attributes[_i2497], _seq2494[_bj2495], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _a_Attribute_write(scratch, value.attributes[_i2497]);
                base.verify_same($"s.{slot}.attributes", _bj2495, scratch);
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
            _a_Attribute_write(out, value.attributes[_i2497]);
        }
        base.count("s.*.attributes" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.attributes" + " whole", 0);
        out.unsigned(value.attributes.count);
        for (var _i2497 in 0..value.attributes.count) {
            _a_Attribute_write(out, value.attributes[_i2497]);
        }
    }
    out.loc(value.loc);
    if (value.enum_cases.is_value()) {
        out.unsigned(1);
        out.unsigned(value.enum_cases.value().count);
        for (var _item2506 in value.enum_cases.value()) {
            _m_EnumCaseDef_write(out, _item2506);
        }
    } else {
        out.unsigned(0);
    }
}

_patch_s_read(input: RecordIn, was: StructDef): StructDef {
    var _f2388 = input.text();
    var _f2389 = _m_TypeName_read(input);
    var _f2399 = Array<GenericParam>();
    var _mode2402 = input.unsigned();
    if (_mode2402 == 2) {
        var _changed2391 = HashMap<ulong, GenericParam>();
        ulong _bi2403 = 0;
        var _n2400 = input.count();
        for (var _ in 0.._n2400) {
            var _at2404 = input.unsigned();
            while (_f2399.count < _at2404 or (input.merging and _bi2403 < was.generic_params.count)) {
                var _c = _changed2391.try_get(_bi2403);
                _f2399.append(_c.is_value() ? _c.value() : was.generic_params[_bi2403]);
                _bi2403 += 1;
            }
            _f2399.append(_m_GenericParam_read(input));
        }
        while (_bi2403 < was.generic_params.count) {
            var _c = _changed2391.try_get(_bi2403);
            _f2399.append(_c.is_value() ? _c.value() : was.generic_params[_bi2403]);
            _bi2403 += 1;
        }
    } else if (_mode2402 == 3) {
        var _n2400 = input.count();
        for (var _ in 0.._n2400) {
            _f2399.append(_m_GenericParam_read(input));
        }
    } else {
        var _n2400 = input.count();
        if (input.merging) {
            input.error = "s.*.generic_params" + " written by place";
        }
        for (var _ in 0.._n2400) {
            var _tag2401 = input.unsigned();
            if (_tag2401 & 1 == 1) {
                if (!input.merging) {
                    _f2399.append(was.generic_params[_tag2401 >> 1]);
                }
            } else {
                var _read = _m_GenericParam_read(input);
                if (!input.merging or true) {
                    _f2399.append(_read);
                }
            }
        }
    }
    var _f2415 = Array<VariableDef>();
    var _mode2418 = input.unsigned();
    if (_mode2418 == 2) {
        var _changed2407 = HashMap<ulong, VariableDef>();
        ulong _bi2419 = 0;
        var _n2416 = input.count();
        for (var _ in 0.._n2416) {
            var _at2420 = input.unsigned();
            while (_f2415.count < _at2420 or (input.merging and _bi2419 < was.field_members.count)) {
                var _c = _changed2407.try_get(_bi2419);
                _f2415.append(_c.is_value() ? _c.value() : was.field_members[_bi2419]);
                _bi2419 += 1;
            }
            _f2415.append(_m_VariableDef_read(input));
        }
        while (_bi2419 < was.field_members.count) {
            var _c = _changed2407.try_get(_bi2419);
            _f2415.append(_c.is_value() ? _c.value() : was.field_members[_bi2419]);
            _bi2419 += 1;
        }
    } else if (_mode2418 == 3) {
        var _n2416 = input.count();
        for (var _ in 0.._n2416) {
            _f2415.append(_m_VariableDef_read(input));
        }
    } else {
        var _n2416 = input.count();
        if (input.merging) {
            input.error = "s.*.field_members" + " written by place";
        }
        for (var _ in 0.._n2416) {
            var _tag2417 = input.unsigned();
            if (_tag2417 & 1 == 1) {
                if (!input.merging) {
                    _f2415.append(was.field_members[_tag2417 >> 1]);
                }
            } else {
                var _read = _m_VariableDef_read(input);
                if (!input.merging or true) {
                    _f2415.append(_read);
                }
            }
        }
    }
    var _f2431 = Array<FunctionDef>();
    var _mode2434 = input.unsigned();
    if (_mode2434 == 2) {
        var _changed2423 = HashMap<ulong, FunctionDef>();
        ulong _bi2435 = 0;
        var _n2432 = input.count();
        for (var _ in 0.._n2432) {
            var _at2436 = input.unsigned();
            while (_f2431.count < _at2436 or (input.merging and _bi2435 < was.method_members.count)) {
                var _c = _changed2423.try_get(_bi2435);
                _f2431.append(_c.is_value() ? _c.value() : was.method_members[_bi2435]);
                _bi2435 += 1;
            }
            _f2431.append(_m_FunctionDef_read(input));
        }
        while (_bi2435 < was.method_members.count) {
            var _c = _changed2423.try_get(_bi2435);
            _f2431.append(_c.is_value() ? _c.value() : was.method_members[_bi2435]);
            _bi2435 += 1;
        }
    } else if (_mode2434 == 3) {
        var _n2432 = input.count();
        for (var _ in 0.._n2432) {
            _f2431.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2432 = input.count();
        if (input.merging) {
            input.error = "s.*.method_members" + " written by place";
        }
        for (var _ in 0.._n2432) {
            var _tag2433 = input.unsigned();
            if (_tag2433 & 1 == 1) {
                if (!input.merging) {
                    _f2431.append(was.method_members[_tag2433 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2431.append(_read);
                }
            }
        }
    }
    var _f2447 = Array<FunctionDef>();
    var _mode2450 = input.unsigned();
    if (_mode2450 == 2) {
        var _changed2439 = HashMap<ulong, FunctionDef>();
        ulong _bi2451 = 0;
        var _n2448 = input.count();
        for (var _ in 0.._n2448) {
            var _at2452 = input.unsigned();
            while (_f2447.count < _at2452 or (input.merging and _bi2451 < was.generic_methods.count)) {
                var _c = _changed2439.try_get(_bi2451);
                _f2447.append(_c.is_value() ? _c.value() : was.generic_methods[_bi2451]);
                _bi2451 += 1;
            }
            _f2447.append(_m_FunctionDef_read(input));
        }
        while (_bi2451 < was.generic_methods.count) {
            var _c = _changed2439.try_get(_bi2451);
            _f2447.append(_c.is_value() ? _c.value() : was.generic_methods[_bi2451]);
            _bi2451 += 1;
        }
    } else if (_mode2450 == 3) {
        var _n2448 = input.count();
        for (var _ in 0.._n2448) {
            _f2447.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2448 = input.count();
        if (input.merging) {
            input.error = "s.*.generic_methods" + " written by place";
        }
        for (var _ in 0.._n2448) {
            var _tag2449 = input.unsigned();
            if (_tag2449 & 1 == 1) {
                if (!input.merging) {
                    _f2447.append(was.generic_methods[_tag2449 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2447.append(_read);
                }
            }
        }
    }
    var _f2463 = Array<FunctionDef>();
    var _mode2466 = input.unsigned();
    if (_mode2466 == 2) {
        var _changed2455 = HashMap<ulong, FunctionDef>();
        ulong _bi2467 = 0;
        var _n2464 = input.count();
        for (var _ in 0.._n2464) {
            var _at2468 = input.unsigned();
            while (_f2463.count < _at2468 or (input.merging and _bi2467 < was.constructors.count)) {
                var _c = _changed2455.try_get(_bi2467);
                _f2463.append(_c.is_value() ? _c.value() : was.constructors[_bi2467]);
                _bi2467 += 1;
            }
            _f2463.append(_m_FunctionDef_read(input));
        }
        while (_bi2467 < was.constructors.count) {
            var _c = _changed2455.try_get(_bi2467);
            _f2463.append(_c.is_value() ? _c.value() : was.constructors[_bi2467]);
            _bi2467 += 1;
        }
    } else if (_mode2466 == 3) {
        var _n2464 = input.count();
        for (var _ in 0.._n2464) {
            _f2463.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2464 = input.count();
        if (input.merging) {
            input.error = "s.*.constructors" + " written by place";
        }
        for (var _ in 0.._n2464) {
            var _tag2465 = input.unsigned();
            if (_tag2465 & 1 == 1) {
                if (!input.merging) {
                    _f2463.append(was.constructors[_tag2465 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2463.append(_read);
                }
            }
        }
    }
    var _f2470 = _m_FunctionDef_read(input);
    var _f2471 = _m_FunctionDef_read(input);
    var _f2472 = _m_FunctionDef_read(input);
    var _f2482 = Array<TypeName>();
    var _mode2485 = input.unsigned();
    if (_mode2485 == 2) {
        var _changed2474 = HashMap<ulong, TypeName>();
        ulong _bi2486 = 0;
        var _n2483 = input.count();
        for (var _ in 0.._n2483) {
            var _at2487 = input.unsigned();
            while (_f2482.count < _at2487 or (input.merging and _bi2486 < was.traits.count)) {
                var _c = _changed2474.try_get(_bi2486);
                _f2482.append(_c.is_value() ? _c.value() : was.traits[_bi2486]);
                _bi2486 += 1;
            }
            _f2482.append(_m_TypeName_read(input));
        }
        while (_bi2486 < was.traits.count) {
            var _c = _changed2474.try_get(_bi2486);
            _f2482.append(_c.is_value() ? _c.value() : was.traits[_bi2486]);
            _bi2486 += 1;
        }
    } else if (_mode2485 == 3) {
        var _n2483 = input.count();
        for (var _ in 0.._n2483) {
            _f2482.append(_m_TypeName_read(input));
        }
    } else {
        var _n2483 = input.count();
        if (input.merging) {
            input.error = "s.*.traits" + " written by place";
        }
        for (var _ in 0.._n2483) {
            var _tag2484 = input.unsigned();
            if (_tag2484 & 1 == 1) {
                if (!input.merging) {
                    _f2482.append(was.traits[_tag2484 >> 1]);
                }
            } else {
                var _read = _m_TypeName_read(input);
                if (!input.merging or true) {
                    _f2482.append(_read);
                }
            }
        }
    }
    var _f2498 = Array<ast.Attribute>();
    var _mode2501 = input.unsigned();
    if (_mode2501 == 2) {
        var _changed2490 = HashMap<ulong, ast.Attribute>();
        ulong _bi2502 = 0;
        var _n2499 = input.count();
        for (var _ in 0.._n2499) {
            var _at2503 = input.unsigned();
            while (_f2498.count < _at2503 or (input.merging and _bi2502 < was.attributes.count)) {
                var _c = _changed2490.try_get(_bi2502);
                _f2498.append(_c.is_value() ? _c.value() : was.attributes[_bi2502]);
                _bi2502 += 1;
            }
            _f2498.append(_a_Attribute_read(input));
        }
        while (_bi2502 < was.attributes.count) {
            var _c = _changed2490.try_get(_bi2502);
            _f2498.append(_c.is_value() ? _c.value() : was.attributes[_bi2502]);
            _bi2502 += 1;
        }
    } else if (_mode2501 == 3) {
        var _n2499 = input.count();
        for (var _ in 0.._n2499) {
            _f2498.append(_a_Attribute_read(input));
        }
    } else {
        var _n2499 = input.count();
        if (input.merging) {
            input.error = "s.*.attributes" + " written by place";
        }
        for (var _ in 0.._n2499) {
            var _tag2500 = input.unsigned();
            if (_tag2500 & 1 == 1) {
                if (!input.merging) {
                    _f2498.append(was.attributes[_tag2500 >> 1]);
                }
            } else {
                var _read = _a_Attribute_read(input);
                if (!input.merging or true) {
                    _f2498.append(_read);
                }
            }
        }
    }
    var _f2505 = input.loc();
    var _o2507 = Optional<Array<EnumCaseDef>>.Empty;
    if (input.unsigned() == 1) {
        var _v2508 = Array<EnumCaseDef>();
        var _n2509 = input.count();
        for (var _ in 0.._n2509) {
            _v2508.append(_m_EnumCaseDef_read(input));
        }
        _o2507 = Optional<Array<EnumCaseDef>>.Value(_v2508);
    }
    var _f2510 = _o2507;
    return StructDef(
        _f2388, _f2389, _f2399, _f2415, _f2431, _f2447, _f2463, _f2470, _f2471, _f2472, _f2482, _f2498, _f2505, _f2510
    );
}

_patch_s_index(value: StructDef, base: DeltaBase, slot: ulong) {
    if (base.verifying) {
        ulong _j2405 = 0;
        for (var _item2390 in value.generic_params) {
            var scratch = base.scratch();
            _m_GenericParam_write(scratch, _item2390);
            base.add($"s.{slot}.generic_params", scratch, _j2405);
            _j2405 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2421 = 0;
        for (var _item2406 in value.field_members) {
            var scratch = base.scratch();
            _m_VariableDef_write(scratch, _item2406);
            base.add($"s.{slot}.field_members", scratch, _j2421);
            _j2421 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2437 = 0;
        for (var _item2422 in value.method_members) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2422);
            base.add($"s.{slot}.method_members", scratch, _j2437);
            _j2437 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2453 = 0;
        for (var _item2438 in value.generic_methods) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2438);
            base.add($"s.{slot}.generic_methods", scratch, _j2453);
            _j2453 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2469 = 0;
        for (var _item2454 in value.constructors) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2454);
            base.add($"s.{slot}.constructors", scratch, _j2469);
            _j2469 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2488 = 0;
        for (var _item2473 in value.traits) {
            var scratch = base.scratch();
            _m_TypeName_write(scratch, _item2473);
            base.add($"s.{slot}.traits", scratch, _j2488);
            _j2488 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2504 = 0;
        for (var _item2489 in value.attributes) {
            var scratch = base.scratch();
            _a_Attribute_write(scratch, _item2489);
            base.add($"s.{slot}.attributes", scratch, _j2504);
            _j2504 += 1;
        }
    }
}

_patch_t_write(out: RecordOut, value: StructDef, base: DeltaBase, slot: ulong) {
    out.text(value.name);
    _m_TypeName_write(out, value.ty);
    var _seq2518 = base.ref_template_parts[slot].generic_params;
    ulong _bj2519 = 0;
    var _news2520 = Array<ulong>();
    for (var _i2521 in 0..value.generic_params.count) {
        if (_bj2519 < _seq2518.count and value.generic_params[_i2521] === _seq2518[_bj2519]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_GenericParam_write(scratch, value.generic_params[_i2521]);
                base.verify_same($"t.{slot}.generic_params", _bj2519, scratch);
            }
            _bj2519 += 1;
        } else if (_bj2519 < _seq2518.count
            and _same_m_GenericParam(value.generic_params[_i2521], _seq2518[_bj2519], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_GenericParam_write(scratch, value.generic_params[_i2521]);
                base.verify_same($"t.{slot}.generic_params", _bj2519, scratch);
            }
            _bj2519 += 1;
        } else {
            _news2520.append(_i2521);
        }
    }
    if (_bj2519 == _seq2518.count) {
        out.unsigned(2);
        out.unsigned(_news2520.count);
        for (var _i2521 in _news2520) {
            out.unsigned(_i2521);
            _m_GenericParam_write(out, value.generic_params[_i2521]);
        }
        base.count("t.*.generic_params" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.generic_params" + " whole", 0);
        out.unsigned(value.generic_params.count);
        for (var _i2521 in 0..value.generic_params.count) {
            _m_GenericParam_write(out, value.generic_params[_i2521]);
        }
    }
    var _seq2534 = base.ref_template_parts[slot].field_members;
    ulong _bj2535 = 0;
    var _news2536 = Array<ulong>();
    for (var _i2537 in 0..value.field_members.count) {
        if (_bj2535 < _seq2534.count and value.field_members[_i2537] === _seq2534[_bj2535]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_VariableDef_write(scratch, value.field_members[_i2537]);
                base.verify_same($"t.{slot}.field_members", _bj2535, scratch);
            }
            _bj2535 += 1;
        } else if (_bj2535 < _seq2534.count
            and _same_m_VariableDef(value.field_members[_i2537], _seq2534[_bj2535], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_VariableDef_write(scratch, value.field_members[_i2537]);
                base.verify_same($"t.{slot}.field_members", _bj2535, scratch);
            }
            _bj2535 += 1;
        } else {
            _news2536.append(_i2537);
        }
    }
    if (_bj2535 == _seq2534.count) {
        out.unsigned(2);
        out.unsigned(_news2536.count);
        for (var _i2537 in _news2536) {
            out.unsigned(_i2537);
            _m_VariableDef_write(out, value.field_members[_i2537]);
        }
        base.count("t.*.field_members" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.field_members" + " whole", 0);
        out.unsigned(value.field_members.count);
        for (var _i2537 in 0..value.field_members.count) {
            _m_VariableDef_write(out, value.field_members[_i2537]);
        }
    }
    var _seq2550 = base.ref_template_parts[slot].method_members;
    ulong _bj2551 = 0;
    var _news2552 = Array<ulong>();
    for (var _i2553 in 0..value.method_members.count) {
        if (_bj2551 < _seq2550.count and value.method_members[_i2553] === _seq2550[_bj2551]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.method_members[_i2553]);
                base.verify_same($"t.{slot}.method_members", _bj2551, scratch);
            }
            _bj2551 += 1;
        } else if (_bj2551 < _seq2550.count
            and _same_m_FunctionDef(value.method_members[_i2553], _seq2550[_bj2551], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.method_members[_i2553]);
                base.verify_same($"t.{slot}.method_members", _bj2551, scratch);
            }
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
    var _seq2566 = base.ref_template_parts[slot].generic_methods;
    ulong _bj2567 = 0;
    var _news2568 = Array<ulong>();
    for (var _i2569 in 0..value.generic_methods.count) {
        if (_bj2567 < _seq2566.count and value.generic_methods[_i2569] === _seq2566[_bj2567]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.generic_methods[_i2569]);
                base.verify_same($"t.{slot}.generic_methods", _bj2567, scratch);
            }
            _bj2567 += 1;
        } else if (_bj2567 < _seq2566.count
            and _same_m_FunctionDef(value.generic_methods[_i2569], _seq2566[_bj2567], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.generic_methods[_i2569]);
                base.verify_same($"t.{slot}.generic_methods", _bj2567, scratch);
            }
            _bj2567 += 1;
        } else {
            _news2568.append(_i2569);
        }
    }
    if (_bj2567 == _seq2566.count) {
        out.unsigned(2);
        out.unsigned(_news2568.count);
        for (var _i2569 in _news2568) {
            out.unsigned(_i2569);
            _m_FunctionDef_write(out, value.generic_methods[_i2569]);
        }
        base.count("t.*.generic_methods" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.generic_methods" + " whole", 0);
        out.unsigned(value.generic_methods.count);
        for (var _i2569 in 0..value.generic_methods.count) {
            _m_FunctionDef_write(out, value.generic_methods[_i2569]);
        }
    }
    var _seq2582 = base.ref_template_parts[slot].constructors;
    ulong _bj2583 = 0;
    var _news2584 = Array<ulong>();
    for (var _i2585 in 0..value.constructors.count) {
        if (_bj2583 < _seq2582.count and value.constructors[_i2585] === _seq2582[_bj2583]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.constructors[_i2585]);
                base.verify_same($"t.{slot}.constructors", _bj2583, scratch);
            }
            _bj2583 += 1;
        } else if (_bj2583 < _seq2582.count
            and _same_m_FunctionDef(value.constructors[_i2585], _seq2582[_bj2583], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.constructors[_i2585]);
                base.verify_same($"t.{slot}.constructors", _bj2583, scratch);
            }
            _bj2583 += 1;
        } else {
            _news2584.append(_i2585);
        }
    }
    if (_bj2583 == _seq2582.count) {
        out.unsigned(2);
        out.unsigned(_news2584.count);
        for (var _i2585 in _news2584) {
            out.unsigned(_i2585);
            _m_FunctionDef_write(out, value.constructors[_i2585]);
        }
        base.count("t.*.constructors" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.constructors" + " whole", 0);
        out.unsigned(value.constructors.count);
        for (var _i2585 in 0..value.constructors.count) {
            _m_FunctionDef_write(out, value.constructors[_i2585]);
        }
    }
    _m_FunctionDef_write(out, value.destructor);
    _m_FunctionDef_write(out, value.acquire);
    _m_FunctionDef_write(out, value.release);
    var _seq2601 = base.ref_template_parts[slot].traits;
    ulong _bj2602 = 0;
    var _news2603 = Array<ulong>();
    for (var _i2604 in 0..value.traits.count) {
        if (_bj2602 < _seq2601.count and value.traits[_i2604] === _seq2601[_bj2602]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_TypeName_write(scratch, value.traits[_i2604]);
                base.verify_same($"t.{slot}.traits", _bj2602, scratch);
            }
            _bj2602 += 1;
        } else if (_bj2602 < _seq2601.count and _same_m_TypeName(value.traits[_i2604], _seq2601[_bj2602], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_TypeName_write(scratch, value.traits[_i2604]);
                base.verify_same($"t.{slot}.traits", _bj2602, scratch);
            }
            _bj2602 += 1;
        } else {
            _news2603.append(_i2604);
        }
    }
    if (_bj2602 == _seq2601.count) {
        out.unsigned(2);
        out.unsigned(_news2603.count);
        for (var _i2604 in _news2603) {
            out.unsigned(_i2604);
            _m_TypeName_write(out, value.traits[_i2604]);
        }
        base.count("t.*.traits" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.traits" + " whole", 0);
        out.unsigned(value.traits.count);
        for (var _i2604 in 0..value.traits.count) {
            _m_TypeName_write(out, value.traits[_i2604]);
        }
    }
    var _seq2617 = base.ref_template_parts[slot].attributes;
    ulong _bj2618 = 0;
    var _news2619 = Array<ulong>();
    for (var _i2620 in 0..value.attributes.count) {
        if (_bj2618 < _seq2617.count and value.attributes[_i2620] === _seq2617[_bj2618]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _a_Attribute_write(scratch, value.attributes[_i2620]);
                base.verify_same($"t.{slot}.attributes", _bj2618, scratch);
            }
            _bj2618 += 1;
        } else if (_bj2618 < _seq2617.count and _same_a_Attribute(value.attributes[_i2620], _seq2617[_bj2618], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _a_Attribute_write(scratch, value.attributes[_i2620]);
                base.verify_same($"t.{slot}.attributes", _bj2618, scratch);
            }
            _bj2618 += 1;
        } else {
            _news2619.append(_i2620);
        }
    }
    if (_bj2618 == _seq2617.count) {
        out.unsigned(2);
        out.unsigned(_news2619.count);
        for (var _i2620 in _news2619) {
            out.unsigned(_i2620);
            _a_Attribute_write(out, value.attributes[_i2620]);
        }
        base.count("t.*.attributes" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.attributes" + " whole", 0);
        out.unsigned(value.attributes.count);
        for (var _i2620 in 0..value.attributes.count) {
            _a_Attribute_write(out, value.attributes[_i2620]);
        }
    }
    out.loc(value.loc);
    if (value.enum_cases.is_value()) {
        out.unsigned(1);
        out.unsigned(value.enum_cases.value().count);
        for (var _item2629 in value.enum_cases.value()) {
            _m_EnumCaseDef_write(out, _item2629);
        }
    } else {
        out.unsigned(0);
    }
}

_patch_t_read(input: RecordIn, was: StructDef): StructDef {
    var _f2511 = input.text();
    var _f2512 = _m_TypeName_read(input);
    var _f2522 = Array<GenericParam>();
    var _mode2525 = input.unsigned();
    if (_mode2525 == 2) {
        var _changed2514 = HashMap<ulong, GenericParam>();
        ulong _bi2526 = 0;
        var _n2523 = input.count();
        for (var _ in 0.._n2523) {
            var _at2527 = input.unsigned();
            while (_f2522.count < _at2527 or (input.merging and _bi2526 < was.generic_params.count)) {
                var _c = _changed2514.try_get(_bi2526);
                _f2522.append(_c.is_value() ? _c.value() : was.generic_params[_bi2526]);
                _bi2526 += 1;
            }
            _f2522.append(_m_GenericParam_read(input));
        }
        while (_bi2526 < was.generic_params.count) {
            var _c = _changed2514.try_get(_bi2526);
            _f2522.append(_c.is_value() ? _c.value() : was.generic_params[_bi2526]);
            _bi2526 += 1;
        }
    } else if (_mode2525 == 3) {
        var _n2523 = input.count();
        for (var _ in 0.._n2523) {
            _f2522.append(_m_GenericParam_read(input));
        }
    } else {
        var _n2523 = input.count();
        if (input.merging) {
            input.error = "t.*.generic_params" + " written by place";
        }
        for (var _ in 0.._n2523) {
            var _tag2524 = input.unsigned();
            if (_tag2524 & 1 == 1) {
                if (!input.merging) {
                    _f2522.append(was.generic_params[_tag2524 >> 1]);
                }
            } else {
                var _read = _m_GenericParam_read(input);
                if (!input.merging or true) {
                    _f2522.append(_read);
                }
            }
        }
    }
    var _f2538 = Array<VariableDef>();
    var _mode2541 = input.unsigned();
    if (_mode2541 == 2) {
        var _changed2530 = HashMap<ulong, VariableDef>();
        ulong _bi2542 = 0;
        var _n2539 = input.count();
        for (var _ in 0.._n2539) {
            var _at2543 = input.unsigned();
            while (_f2538.count < _at2543 or (input.merging and _bi2542 < was.field_members.count)) {
                var _c = _changed2530.try_get(_bi2542);
                _f2538.append(_c.is_value() ? _c.value() : was.field_members[_bi2542]);
                _bi2542 += 1;
            }
            _f2538.append(_m_VariableDef_read(input));
        }
        while (_bi2542 < was.field_members.count) {
            var _c = _changed2530.try_get(_bi2542);
            _f2538.append(_c.is_value() ? _c.value() : was.field_members[_bi2542]);
            _bi2542 += 1;
        }
    } else if (_mode2541 == 3) {
        var _n2539 = input.count();
        for (var _ in 0.._n2539) {
            _f2538.append(_m_VariableDef_read(input));
        }
    } else {
        var _n2539 = input.count();
        if (input.merging) {
            input.error = "t.*.field_members" + " written by place";
        }
        for (var _ in 0.._n2539) {
            var _tag2540 = input.unsigned();
            if (_tag2540 & 1 == 1) {
                if (!input.merging) {
                    _f2538.append(was.field_members[_tag2540 >> 1]);
                }
            } else {
                var _read = _m_VariableDef_read(input);
                if (!input.merging or true) {
                    _f2538.append(_read);
                }
            }
        }
    }
    var _f2554 = Array<FunctionDef>();
    var _mode2557 = input.unsigned();
    if (_mode2557 == 2) {
        var _changed2546 = HashMap<ulong, FunctionDef>();
        ulong _bi2558 = 0;
        var _n2555 = input.count();
        for (var _ in 0.._n2555) {
            var _at2559 = input.unsigned();
            while (_f2554.count < _at2559 or (input.merging and _bi2558 < was.method_members.count)) {
                var _c = _changed2546.try_get(_bi2558);
                _f2554.append(_c.is_value() ? _c.value() : was.method_members[_bi2558]);
                _bi2558 += 1;
            }
            _f2554.append(_m_FunctionDef_read(input));
        }
        while (_bi2558 < was.method_members.count) {
            var _c = _changed2546.try_get(_bi2558);
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
    var _f2570 = Array<FunctionDef>();
    var _mode2573 = input.unsigned();
    if (_mode2573 == 2) {
        var _changed2562 = HashMap<ulong, FunctionDef>();
        ulong _bi2574 = 0;
        var _n2571 = input.count();
        for (var _ in 0.._n2571) {
            var _at2575 = input.unsigned();
            while (_f2570.count < _at2575 or (input.merging and _bi2574 < was.generic_methods.count)) {
                var _c = _changed2562.try_get(_bi2574);
                _f2570.append(_c.is_value() ? _c.value() : was.generic_methods[_bi2574]);
                _bi2574 += 1;
            }
            _f2570.append(_m_FunctionDef_read(input));
        }
        while (_bi2574 < was.generic_methods.count) {
            var _c = _changed2562.try_get(_bi2574);
            _f2570.append(_c.is_value() ? _c.value() : was.generic_methods[_bi2574]);
            _bi2574 += 1;
        }
    } else if (_mode2573 == 3) {
        var _n2571 = input.count();
        for (var _ in 0.._n2571) {
            _f2570.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2571 = input.count();
        if (input.merging) {
            input.error = "t.*.generic_methods" + " written by place";
        }
        for (var _ in 0.._n2571) {
            var _tag2572 = input.unsigned();
            if (_tag2572 & 1 == 1) {
                if (!input.merging) {
                    _f2570.append(was.generic_methods[_tag2572 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2570.append(_read);
                }
            }
        }
    }
    var _f2586 = Array<FunctionDef>();
    var _mode2589 = input.unsigned();
    if (_mode2589 == 2) {
        var _changed2578 = HashMap<ulong, FunctionDef>();
        ulong _bi2590 = 0;
        var _n2587 = input.count();
        for (var _ in 0.._n2587) {
            var _at2591 = input.unsigned();
            while (_f2586.count < _at2591 or (input.merging and _bi2590 < was.constructors.count)) {
                var _c = _changed2578.try_get(_bi2590);
                _f2586.append(_c.is_value() ? _c.value() : was.constructors[_bi2590]);
                _bi2590 += 1;
            }
            _f2586.append(_m_FunctionDef_read(input));
        }
        while (_bi2590 < was.constructors.count) {
            var _c = _changed2578.try_get(_bi2590);
            _f2586.append(_c.is_value() ? _c.value() : was.constructors[_bi2590]);
            _bi2590 += 1;
        }
    } else if (_mode2589 == 3) {
        var _n2587 = input.count();
        for (var _ in 0.._n2587) {
            _f2586.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2587 = input.count();
        if (input.merging) {
            input.error = "t.*.constructors" + " written by place";
        }
        for (var _ in 0.._n2587) {
            var _tag2588 = input.unsigned();
            if (_tag2588 & 1 == 1) {
                if (!input.merging) {
                    _f2586.append(was.constructors[_tag2588 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2586.append(_read);
                }
            }
        }
    }
    var _f2593 = _m_FunctionDef_read(input);
    var _f2594 = _m_FunctionDef_read(input);
    var _f2595 = _m_FunctionDef_read(input);
    var _f2605 = Array<TypeName>();
    var _mode2608 = input.unsigned();
    if (_mode2608 == 2) {
        var _changed2597 = HashMap<ulong, TypeName>();
        ulong _bi2609 = 0;
        var _n2606 = input.count();
        for (var _ in 0.._n2606) {
            var _at2610 = input.unsigned();
            while (_f2605.count < _at2610 or (input.merging and _bi2609 < was.traits.count)) {
                var _c = _changed2597.try_get(_bi2609);
                _f2605.append(_c.is_value() ? _c.value() : was.traits[_bi2609]);
                _bi2609 += 1;
            }
            _f2605.append(_m_TypeName_read(input));
        }
        while (_bi2609 < was.traits.count) {
            var _c = _changed2597.try_get(_bi2609);
            _f2605.append(_c.is_value() ? _c.value() : was.traits[_bi2609]);
            _bi2609 += 1;
        }
    } else if (_mode2608 == 3) {
        var _n2606 = input.count();
        for (var _ in 0.._n2606) {
            _f2605.append(_m_TypeName_read(input));
        }
    } else {
        var _n2606 = input.count();
        if (input.merging) {
            input.error = "t.*.traits" + " written by place";
        }
        for (var _ in 0.._n2606) {
            var _tag2607 = input.unsigned();
            if (_tag2607 & 1 == 1) {
                if (!input.merging) {
                    _f2605.append(was.traits[_tag2607 >> 1]);
                }
            } else {
                var _read = _m_TypeName_read(input);
                if (!input.merging or true) {
                    _f2605.append(_read);
                }
            }
        }
    }
    var _f2621 = Array<ast.Attribute>();
    var _mode2624 = input.unsigned();
    if (_mode2624 == 2) {
        var _changed2613 = HashMap<ulong, ast.Attribute>();
        ulong _bi2625 = 0;
        var _n2622 = input.count();
        for (var _ in 0.._n2622) {
            var _at2626 = input.unsigned();
            while (_f2621.count < _at2626 or (input.merging and _bi2625 < was.attributes.count)) {
                var _c = _changed2613.try_get(_bi2625);
                _f2621.append(_c.is_value() ? _c.value() : was.attributes[_bi2625]);
                _bi2625 += 1;
            }
            _f2621.append(_a_Attribute_read(input));
        }
        while (_bi2625 < was.attributes.count) {
            var _c = _changed2613.try_get(_bi2625);
            _f2621.append(_c.is_value() ? _c.value() : was.attributes[_bi2625]);
            _bi2625 += 1;
        }
    } else if (_mode2624 == 3) {
        var _n2622 = input.count();
        for (var _ in 0.._n2622) {
            _f2621.append(_a_Attribute_read(input));
        }
    } else {
        var _n2622 = input.count();
        if (input.merging) {
            input.error = "t.*.attributes" + " written by place";
        }
        for (var _ in 0.._n2622) {
            var _tag2623 = input.unsigned();
            if (_tag2623 & 1 == 1) {
                if (!input.merging) {
                    _f2621.append(was.attributes[_tag2623 >> 1]);
                }
            } else {
                var _read = _a_Attribute_read(input);
                if (!input.merging or true) {
                    _f2621.append(_read);
                }
            }
        }
    }
    var _f2628 = input.loc();
    var _o2630 = Optional<Array<EnumCaseDef>>.Empty;
    if (input.unsigned() == 1) {
        var _v2631 = Array<EnumCaseDef>();
        var _n2632 = input.count();
        for (var _ in 0.._n2632) {
            _v2631.append(_m_EnumCaseDef_read(input));
        }
        _o2630 = Optional<Array<EnumCaseDef>>.Value(_v2631);
    }
    var _f2633 = _o2630;
    return StructDef(
        _f2511, _f2512, _f2522, _f2538, _f2554, _f2570, _f2586, _f2593, _f2594, _f2595, _f2605, _f2621, _f2628, _f2633
    );
}

_patch_t_index(value: StructDef, base: DeltaBase, slot: ulong) {
    if (base.verifying) {
        ulong _j2528 = 0;
        for (var _item2513 in value.generic_params) {
            var scratch = base.scratch();
            _m_GenericParam_write(scratch, _item2513);
            base.add($"t.{slot}.generic_params", scratch, _j2528);
            _j2528 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2544 = 0;
        for (var _item2529 in value.field_members) {
            var scratch = base.scratch();
            _m_VariableDef_write(scratch, _item2529);
            base.add($"t.{slot}.field_members", scratch, _j2544);
            _j2544 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2560 = 0;
        for (var _item2545 in value.method_members) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2545);
            base.add($"t.{slot}.method_members", scratch, _j2560);
            _j2560 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2576 = 0;
        for (var _item2561 in value.generic_methods) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2561);
            base.add($"t.{slot}.generic_methods", scratch, _j2576);
            _j2576 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2592 = 0;
        for (var _item2577 in value.constructors) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2577);
            base.add($"t.{slot}.constructors", scratch, _j2592);
            _j2592 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2611 = 0;
        for (var _item2596 in value.traits) {
            var scratch = base.scratch();
            _m_TypeName_write(scratch, _item2596);
            base.add($"t.{slot}.traits", scratch, _j2611);
            _j2611 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2627 = 0;
        for (var _item2612 in value.attributes) {
            var scratch = base.scratch();
            _a_Attribute_write(scratch, _item2612);
            base.add($"t.{slot}.attributes", scratch, _j2627);
            _j2627 += 1;
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
        for (var _item2634 in value.imports) {
            _a_Import_write(out, _item2634);
        }
        found.append(("imports", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.structs.count);
        for (var _item2635 in value.structs) {
            _m_StructDef_write(out, _item2635);
        }
        found.append(("structs", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.blank_bodies = false;
        out.unsigned(value.traits.count);
        for (var _item2636 in value.traits) {
            _m_TraitDef_write(out, _item2636);
        }
        found.append(("traits", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.extensions.count);
        for (var _item2637 in value.extensions) {
            _m_ExtensionDef_write(out, _item2637);
        }
        found.append(("extensions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.functions.count);
        for (var _item2638 in value.functions) {
            _m_FunctionDef_write(out, _item2638);
        }
        found.append(("functions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.externs.count);
        for (var _item2639 in value.externs) {
            _m_ExternDef_write(out, _item2639);
        }
        found.append(("externs", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.globals.count);
        for (var _item2640 in value.globals) {
            _m_VariableDef_write(out, _item2640);
        }
        found.append(("globals", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.static_blocks.count);
        for (var _item2641 in value.static_blocks) {
            _m_ModuleStaticBlock_write(out, _item2641);
        }
        found.append(("static_blocks", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.enums.count);
        for (var _item2642 in value.enums) {
            _m_EnumDef_write(out, _item2642);
        }
        found.append(("enums", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.struct_specs.count);
        for (var _item2643 in value.struct_specs) {
            _m_TypeName_write(out, _item2643);
        }
        found.append(("struct_specs", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.func_specs.count);
        for (var _item2644 in value.func_specs) {
            _m_TypeName_write(out, _item2644);
        }
        found.append(("func_specs", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.type_aliases.count);
        for (var _item2645 in value.type_aliases) {
            _m_TypeAliasDef_write(out, _item2645);
        }
        found.append(("type_aliases", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.withheld.count);
        for (var _item2646 in value.withheld) {
            _m_Withheld_write(out, _item2646);
        }
        found.append(("withheld", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.properties.count);
        for (var _item2647 in value.properties) {
            _m_PropertyDef_write(out, _item2647);
        }
        found.append(("properties", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.type_uses.count);
        for (var _item2648 in value.type_uses) {
            _m_TypeUse_write(out, _item2648);
        }
        found.append(("type_uses", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.use_contexts.count);
        for (var _item2649 in value.use_contexts) {
            _m_UseContext_write(out, _item2649);
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
            for (var _item2650 in value.literal_args) {
                var (_t2651, _t2652, _t2653) = _item2650;
                out.loc(_t2651);
                out.unsigned(_t2652);
                out.loc(_t2653);
            }
        }
        found.append(("literal_args", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.constrained_aliases.count);
        for (var _item2654 in value.constrained_aliases) {
            _m_TypeAliasDef_write(out, _item2654);
        }
        found.append(("constrained_aliases", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.trait_types.count);
        for (var _item2655 in value.trait_types) {
            _m_TraitType_write(out, _item2655);
        }
        found.append(("trait_types", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.conversions.count);
        for (var _item2656 in value.conversions) {
            _m_Conversion_write(out, _item2656);
        }
        found.append(("conversions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2658 = Array<(u8[], u8[], String)>();
        for (var (_key2657, _) in value.overload_sets) {
            var _scratch2659 = out.scratch();
            _scratch2659.text(_key2657);
            var _vscratch2661 = out.scratch();
            _vscratch2661.unsigned(value.overload_sets[_key2657].count);
            for (var _item2662 in value.overload_sets[_key2657]) {
                _vscratch2661.text(_item2662);
            }
            _keys2658.append((_scratch2659.finish(), _vscratch2661.finish(), _key2657));
        }
        _keys2658.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2658.count);
        for (var (_bytes2660, _, _key2657) in _keys2658) {
            out.text(_key2657);
            out.unsigned(value.overload_sets[_key2657].count);
            for (var _item2663 in value.overload_sets[_key2657]) {
                out.text(_item2663);
            }
        }
        found.append(("overload_sets", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2665 = Array<(u8[], u8[], String)>();
        for (var (_key2664, _) in value.overload_unions) {
            var _scratch2666 = out.scratch();
            _scratch2666.text(_key2664);
            var _vscratch2668 = out.scratch();
            _vscratch2668.unsigned(value.overload_unions[_key2664].count);
            for (var _item2669 in value.overload_unions[_key2664]) {
                _vscratch2668.unsigned(_item2669.count);
                for (var _item2670 in _item2669) {
                    _vscratch2668.text(_item2670);
                }
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
            out.unsigned(value.overload_unions[_key2664].count);
            for (var _item2671 in value.overload_unions[_key2664]) {
                out.unsigned(_item2671.count);
                for (var _item2672 in _item2671) {
                    out.text(_item2672);
                }
            }
        }
        found.append(("overload_unions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2674 = Array<(u8[], u8[], String)>();
        for (var (_key2673, _) in value.method_overload_sets) {
            var _scratch2675 = out.scratch();
            _scratch2675.text(_key2673);
            var _vscratch2677 = out.scratch();
            var _keys2679 = Array<(u8[], u8[], String)>();
            for (var (_key2678, _) in value.method_overload_sets[_key2673]) {
                var _scratch2680 = _vscratch2677.scratch();
                _scratch2680.text(_key2678);
                var _vscratch2682 = _vscratch2677.scratch();
                _vscratch2682.unsigned(value.method_overload_sets[_key2673][_key2678].count);
                for (var _item2683 in value.method_overload_sets[_key2673][_key2678]) {
                    _vscratch2682.text(_item2683);
                }
                _keys2679.append((_scratch2680.finish(), _vscratch2682.finish(), _key2678));
            }
            _keys2679.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            _vscratch2677.unsigned(_keys2679.count);
            for (var (_bytes2681, _, _key2678) in _keys2679) {
                _vscratch2677.text(_key2678);
                _vscratch2677.unsigned(value.method_overload_sets[_key2673][_key2678].count);
                for (var _item2684 in value.method_overload_sets[_key2673][_key2678]) {
                    _vscratch2677.text(_item2684);
                }
            }
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
            out.text(_key2673);
            var _keys2686 = Array<(u8[], u8[], String)>();
            for (var (_key2685, _) in value.method_overload_sets[_key2673]) {
                var _scratch2687 = out.scratch();
                _scratch2687.text(_key2685);
                var _vscratch2689 = out.scratch();
                _vscratch2689.unsigned(value.method_overload_sets[_key2673][_key2685].count);
                for (var _item2690 in value.method_overload_sets[_key2673][_key2685]) {
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
            out.unsigned(_keys2686.count);
            for (var (_bytes2688, _, _key2685) in _keys2686) {
                out.text(_key2685);
                out.unsigned(value.method_overload_sets[_key2673][_key2685].count);
                for (var _item2691 in value.method_overload_sets[_key2673][_key2685]) {
                    out.text(_item2691);
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
        var _keys2693 = Array<(u8[], u8[], Loc)>();
        for (var _key2692 in value.private_functions) {
            var _scratch2694 = out.scratch();
            _scratch2694.loc(_key2692);
            var _vscratch2696 = out.scratch();
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
            out.loc(_key2692);
        }
        found.append(("private_functions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2698 = Array<(u8[], u8[], Loc)>();
        for (var _key2697 in value.file_private_functions) {
            var _scratch2699 = out.scratch();
            _scratch2699.loc(_key2697);
            var _vscratch2701 = out.scratch();
            _keys2698.append((_scratch2699.finish(), _vscratch2701.finish(), _key2697));
        }
        _keys2698.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2698.count);
        for (var (_bytes2700, _, _key2697) in _keys2698) {
            out.loc(_key2697);
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
            for (var _item2702 in value.call_targets) {
                var (_t2703, _t2704) = _item2702;
                out.loc(_t2703);
                out.text(_t2704);
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
            for (var _item2705 in value.argument_names) {
                var (_t2706, _t2707) = _item2705;
                out.loc(_t2706);
                out.text(_t2707);
            }
        }
        found.append(("argument_names", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.namespaces.count);
        for (var _item2708 in value.namespaces) {
            out.text(_item2708);
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
            for (var _item2709 in value.cached_files) {
                out.flag(_item2709);
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
            var _keys2711 = Array<(u8[], u8[], Loc)>();
            for (var (_key2710, _) in value.recorded_summaries) {
                var _scratch2712 = out.scratch();
                _scratch2712.loc(_key2710);
                var _vscratch2714 = out.scratch();
                _vscratch2714.text(value.recorded_summaries[_key2710]);
                _keys2711.append((_scratch2712.finish(), _vscratch2714.finish(), _key2710));
            }
            _keys2711.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            out.unsigned(_keys2711.count);
            for (var (_bytes2713, _, _key2710) in _keys2711) {
                out.loc(_key2710);
                out.text(value.recorded_summaries[_key2710]);
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
            var _keys2716 = Array<(u8[], u8[], Loc)>();
            for (var _key2715 in value.stripped) {
                var _scratch2717 = out.scratch();
                _scratch2717.loc(_key2715);
                var _vscratch2719 = out.scratch();
                _keys2716.append((_scratch2717.finish(), _vscratch2719.finish(), _key2715));
            }
            _keys2716.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            out.unsigned(_keys2716.count);
            for (var (_bytes2718, _, _key2715) in _keys2716) {
                out.loc(_key2715);
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
        var _keys2721 = Array<(u8[], u8[], String)>();
        for (var (_key2720, _) in value.spec_requests) {
            var _scratch2722 = out.scratch();
            _scratch2722.text(_key2720);
            var _vscratch2724 = out.scratch();
            _m_SpecRequest_write(_vscratch2724, value.spec_requests[_key2720]);
            _keys2721.append((_scratch2722.finish(), _vscratch2724.finish(), _key2720));
        }
        _keys2721.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2721.count);
        for (var (_bytes2723, _, _key2720) in _keys2721) {
            out.text(_key2720);
            _m_SpecRequest_write(out, value.spec_requests[_key2720]);
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
            for (var _item2725 in value.summaries_to_record) {
                var (_t2726, _t2727) = _item2725;
                out.loc(_t2726);
                out.text(_t2727);
            }
        }
        found.append(("summaries_to_record", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2729 = Array<(u8[], u8[], String)>();
        for (var (_key2728, _) in value.caller_copies) {
            var _scratch2730 = out.scratch();
            _scratch2730.text(_key2728);
            var _vscratch2732 = out.scratch();
            _vscratch2732.unsigned(value.caller_copies[_key2728].count);
            for (var _item2733 in value.caller_copies[_key2728]) {
                _vscratch2732.flag(_item2733);
            }
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
            out.unsigned(value.caller_copies[_key2728].count);
            for (var _item2734 in value.caller_copies[_key2728]) {
                out.flag(_item2734);
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
    for (var _item2735 in value.structs) {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        _m_StructDef_write(out, _item2735);
        found.append(("structs " + _item2735.name, interface_text(out)));
    }
    for (var _item2736 in value.functions) {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        _m_FunctionDef_write(out, _item2736);
        found.append(("functions " + _item2736.name, interface_text(out)));
    }
    return found;
}
