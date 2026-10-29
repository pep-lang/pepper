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
        var _f1269 = _m_Expression_read(input);
        return Statement.Expression(_f1269);
    }
    if (tag == 1) {
        var _f1270 = _m_Block_read(input);
        return Statement.Block(_f1270);
    }
    if (tag == 2) {
        var _f1271 = _m_Declaration_read(input);
        return Statement.Declaration(_f1271);
    }
    if (tag == 3) {
        var _f1272 = _m_Branch_read(input);
        return Statement.Branch(_f1272);
    }
    if (tag == 4) {
        var _f1273 = _m_While_read(input);
        return Statement.While(_f1273);
    }
    if (tag == 5) {
        var _f1274 = _m_ReturnStatement_read(input);
        return Statement.Return(_f1274);
    }
    if (tag == 6) {
        var _f1275 = _m_LoopBreak_read(input);
        return Statement.LoopBreak(_f1275);
    }
    if (tag == 7) {
        var _f1276 = _m_StaticBlock_read(input);
        return Statement.Static(_f1276);
    }
    if (tag == 8) {
        var _f1277 = _m_StaticPass_read(input);
        return Statement.StaticPass(_f1277);
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
    for (var _item1282 in value.fields) {
        var (_t1283, _t1284) = _item1282;
        out.text(_t1283);
        _m_StaticConstant_write(out, _t1284);
    }
}

_m_RecordStaticConstant_read(input: RecordIn): RecordStaticConstant {
    var _f1285 = input.text();
    var _v1286 = Array<(String, StaticConstant)>();
    var _n1287 = input.count();
    for (var _ in 0.._n1287) {
        var _t1288 = input.text();
        var _t1289 = _m_StaticConstant_read(input);
        _v1286.append((_t1288, _t1289));
    }
    var _f1290 = _v1286;
    return RecordStaticConstant(_f1285, _f1290);
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
        var _f1278 = input.signed();
        return StaticConstant.Int(_f1278);
    }
    if (tag == 1) {
        var _f1279 = input.number();
        return StaticConstant.Float(_f1279);
    }
    if (tag == 2) {
        var _f1280 = input.flag();
        return StaticConstant.Bool(_f1280);
    }
    if (tag == 3) {
        var _f1281 = input.text();
        return StaticConstant.String(_f1281);
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
    for (var _item1291 in value.body) {
        _m_StaticItem_write(out, _item1291);
    }
    out.loc(value.loc);
}

_m_ForStaticItem_read(input: RecordIn): ForStaticItem {
    var _f1292 = input.text();
    var _f1293 = _a_Expression_read(input);
    var _v1294 = Array<StaticItem>();
    var _n1295 = input.count();
    for (var _ in 0.._n1295) {
        _v1294.append(_m_StaticItem_read(input));
    }
    var _f1296 = _v1294;
    var _f1297 = input.loc();
    return ForStaticItem(_f1293, _f1292, _f1296, _f1297);
}

_m_WhileStaticItem_write(out: RecordOut, value: WhileStaticItem) {
    _a_Expression_write(out, value.condition);
    out.unsigned(value.body.count);
    for (var _item1298 in value.body) {
        _m_StaticItem_write(out, _item1298);
    }
    out.loc(value.loc);
}

_m_WhileStaticItem_read(input: RecordIn): WhileStaticItem {
    var _f1299 = _a_Expression_read(input);
    var _v1300 = Array<StaticItem>();
    var _n1301 = input.count();
    for (var _ in 0.._n1301) {
        _v1300.append(_m_StaticItem_read(input));
    }
    var _f1302 = _v1300;
    var _f1303 = input.loc();
    return WhileStaticItem(_f1299, _f1302, _f1303);
}

_m_JumpStaticItem_write(out: RecordOut, value: JumpStaticItem) {
    _m_LoopBreakKind_write(out, value.kind);
    out.loc(value.loc);
}

_m_JumpStaticItem_read(input: RecordIn): JumpStaticItem {
    var _f1304 = _m_LoopBreakKind_read(input);
    var _f1305 = input.loc();
    return JumpStaticItem(_f1304, _f1305);
}

_m_IfStaticItem_write(out: RecordOut, value: IfStaticItem) {
    _a_Expression_write(out, value.condition);
    out.unsigned(value.then_items.count);
    for (var _item1306 in value.then_items) {
        _m_StaticItem_write(out, _item1306);
    }
    out.unsigned(value.else_items.count);
    for (var _item1307 in value.else_items) {
        _m_StaticItem_write(out, _item1307);
    }
    out.loc(value.loc);
}

_m_IfStaticItem_read(input: RecordIn): IfStaticItem {
    var _f1308 = _a_Expression_read(input);
    var _v1309 = Array<StaticItem>();
    var _n1310 = input.count();
    for (var _ in 0.._n1310) {
        _v1309.append(_m_StaticItem_read(input));
    }
    var _f1311 = _v1309;
    var _v1312 = Array<StaticItem>();
    var _n1313 = input.count();
    for (var _ in 0.._n1313) {
        _v1312.append(_m_StaticItem_read(input));
    }
    var _f1314 = _v1312;
    var _f1315 = input.loc();
    return IfStaticItem(_f1308, _f1311, _f1314, _f1315);
}

_m_EmitIfStaticItem_write(out: RecordOut, value: EmitIfStaticItem) {
    _m_Expression_write(out, value.condition);
    out.unsigned(value.then_items.count);
    for (var _item1316 in value.then_items) {
        _m_StaticItem_write(out, _item1316);
    }
    out.unsigned(value.else_items.count);
    for (var _item1317 in value.else_items) {
        _m_StaticItem_write(out, _item1317);
    }
    out.unsigned(out.blank_locs ? 0 : value.span.start);
    out.unsigned(out.blank_locs ? 0 : value.span.end);
}

_m_EmitIfStaticItem_read(input: RecordIn): EmitIfStaticItem {
    var _f1318 = _m_Expression_read(input);
    var _v1319 = Array<StaticItem>();
    var _n1320 = input.count();
    for (var _ in 0.._n1320) {
        _v1319.append(_m_StaticItem_read(input));
    }
    var _f1321 = _v1319;
    var _v1322 = Array<StaticItem>();
    var _n1323 = input.count();
    for (var _ in 0.._n1323) {
        _v1322.append(_m_StaticItem_read(input));
    }
    var _f1324 = _v1322;
    var _s1325 = input.unsigned();
    var _f1326 = ast.Span(_s1325, input.unsigned());
    return EmitIfStaticItem(_f1318, _f1321, _f1324, _f1326);
}

_m_VarStaticItem_write(out: RecordOut, value: VarStaticItem) {
    out.text(value.name);
    _a_Expression_write(out, value.value);
    out.loc(value.loc);
}

_m_VarStaticItem_read(input: RecordIn): VarStaticItem {
    var _f1331 = input.text();
    var _f1332 = _a_Expression_read(input);
    var _f1333 = input.loc();
    return VarStaticItem(_f1332, _f1331, _f1333);
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
            for (var _item1327 in v) {
                _m_StaticItem_write(out, _item1327);
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
        var _v1328 = Array<StaticItem>();
        var _n1329 = input.count();
        for (var _ in 0.._n1329) {
            _v1328.append(_m_StaticItem_read(input));
        }
        var _f1330 = _v1328;
        return StaticItem.Block(_f1330);
    }
    if (tag == 6) {
        return StaticItem.Var(_m_VarStaticItem_read(input));
    }
    if (tag == 7) {
        var _f1334 = _a_Expression_read(input);
        return StaticItem.Evaluate(_f1334);
    }
    if (tag == 8) {
        var _f1335 = _m_Statement_read(input);
        var _s1336 = input.unsigned();
        var _f1337 = ast.Span(_s1336, input.unsigned());
        return StaticItem.Emit(_f1335, _f1337);
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
    var _f1338 = input.text();
    var _f1339 = _m_TypeName_read(input);
    var _f1340 = input.loc();
    return SymbolRefExpression(_f1338, _f1339, _f1340);
}

_m_MemberRefExpression_write(out: RecordOut, value: MemberRefExpression) {
    _m_Expression_write(out, value.lhs);
    out.text(value.name);
    out.loc(value.loc);
}

_m_MemberRefExpression_read(input: RecordIn): MemberRefExpression {
    var _f1341 = _m_Expression_read(input);
    var _f1342 = input.text();
    var _f1343 = input.loc();
    return MemberRefExpression(_f1341, _f1342, _f1343);
}

_m_StringLiteralExpression_write(out: RecordOut, value: StringLiteralExpression) {
    out.text(value.value);
    out.flag(value.is_raw);
    out.loc(value.loc);
}

_m_StringLiteralExpression_read(input: RecordIn): StringLiteralExpression {
    var _f1347 = input.text();
    var _f1348 = input.flag();
    var _f1349 = input.loc();
    return StringLiteralExpression(_f1347, _f1348, _f1349);
}

_m_BinaryExpression_write(out: RecordOut, value: BinaryExpression) {
    _m_BinaryOp_write(out, value.op);
    _m_Expression_write(out, value.lhs);
    _m_Expression_write(out, value.rhs);
    out.loc(value.loc);
}

_m_BinaryExpression_read(input: RecordIn): BinaryExpression {
    var _f1350 = _m_BinaryOp_read(input);
    var _f1351 = _m_Expression_read(input);
    var _f1352 = _m_Expression_read(input);
    var _f1353 = input.loc();
    return BinaryExpression(_f1351, _f1352, _f1350, _f1353);
}

_m_UnaryExpression_write(out: RecordOut, value: UnaryExpression) {
    _m_UnaryOp_write(out, value.op);
    _m_Expression_write(out, value.operand);
    out.loc(value.loc);
}

_m_UnaryExpression_read(input: RecordIn): UnaryExpression {
    var _f1354 = _m_UnaryOp_read(input);
    var _f1355 = _m_Expression_read(input);
    var _f1356 = input.loc();
    return UnaryExpression(_f1355, _f1354, _f1356);
}

_m_CastExpression_write(out: RecordOut, value: CastExpression) {
    _m_Expression_write(out, value.expr);
    _m_TypeName_write(out, value.ty);
    out.loc(value.loc);
    _m_CastKind_write(out, value.kind);
}

_m_CastExpression_read(input: RecordIn): CastExpression {
    var _f1357 = _m_Expression_read(input);
    var _f1358 = _m_TypeName_read(input);
    var _f1359 = input.loc();
    var _f1360 = _m_CastKind_read(input);
    return CastExpression(_f1357, _f1358, _f1359, _f1360);
}

_m_TernaryExpression_write(out: RecordOut, value: TernaryExpression) {
    _m_Expression_write(out, value.condition);
    _m_Expression_write(out, value.true_expr);
    _m_Expression_write(out, value.false_expr);
}

_m_TernaryExpression_read(input: RecordIn): TernaryExpression {
    var _f1361 = _m_Expression_read(input);
    var _f1362 = _m_Expression_read(input);
    var _f1363 = _m_Expression_read(input);
    return TernaryExpression(_f1361, _f1362, _f1363);
}

_m_IndexExpression_write(out: RecordOut, value: IndexExpression) {
    _m_Expression_write(out, value.lhs);
    _m_Expression_write(out, value.rhs);
    out.loc(value.loc);
}

_m_IndexExpression_read(input: RecordIn): IndexExpression {
    var _f1364 = _m_Expression_read(input);
    var _f1365 = _m_Expression_read(input);
    var _f1366 = input.loc();
    return IndexExpression(_f1364, _f1365, _f1366);
}

_m_ArrayIndexExpression_write(out: RecordOut, value: ArrayIndexExpression) {
    _m_TypeName_write(out, value.ty);
    _m_Expression_write(out, value.lhs);
    _m_Expression_write(out, value.rhs);
    out.loc(value.loc);
}

_m_ArrayIndexExpression_read(input: RecordIn): ArrayIndexExpression {
    var _f1367 = _m_TypeName_read(input);
    var _f1368 = _m_Expression_read(input);
    var _f1369 = _m_Expression_read(input);
    var _f1370 = input.loc();
    return ArrayIndexExpression(_f1368, _f1369, _f1367, _f1370);
}

_m_SimdExpression_write(out: RecordOut, value: SimdExpression) {
    _m_SimdOp_write(out, value.op);
    _m_TypeName_write(out, value.ty);
    out.unsigned(value.args.count);
    for (var _item1394 in value.args) {
        _m_Expression_write(out, _item1394);
    }
    out.loc(value.loc);
}

_m_SimdExpression_read(input: RecordIn): SimdExpression {
    var _f1395 = _m_SimdOp_read(input);
    var _f1396 = _m_TypeName_read(input);
    var _v1397 = Array<Expression>();
    var _n1398 = input.count();
    for (var _ in 0.._n1398) {
        _v1397.append(_m_Expression_read(input));
    }
    var _f1399 = _v1397;
    var _f1400 = input.loc();
    return SimdExpression(_f1395, _f1396, _f1399, _f1400);
}

_m_CountStepExpression_write(out: RecordOut, value: CountStepExpression) {
    _m_CountField_write(out, value.field);
    out.flag(value.increment);
    out.flag(value.atomic);
}

_m_CountStepExpression_read(input: RecordIn): CountStepExpression {
    var _f1404 = _m_CountField_read(input);
    var _f1405 = input.flag();
    var _f1406 = input.flag();
    return CountStepExpression(_f1404, _f1405, _f1406);
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
    var _o1407 = Optional<TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o1407 = Optional<TypeName>.Value(_m_TypeName_read(input));
    }
    var _f1408 = _o1407;
    var _f1409 = input.text();
    var _f1410 = input.loc();
    return FunctionPointerExpression(_f1408, _f1409, _f1410);
}

_m_FunctionCallExpression_write(out: RecordOut, value: FunctionCallExpression) {
    out.text(value.function);
    out.unsigned(value.args.count);
    for (var _item1411 in value.args) {
        _m_Expression_write(out, _item1411);
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
    var _f1412 = input.text();
    var _v1413 = Array<Expression>();
    var _n1414 = input.count();
    for (var _ in 0.._n1414) {
        _v1413.append(_m_Expression_read(input));
    }
    var _f1415 = _v1413;
    var _f1416 = input.loc();
    var _o1417 = Optional<TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o1417 = Optional<TypeName>.Value(_m_TypeName_read(input));
    }
    var _f1418 = _o1417;
    var _f1419 = input.flag();
    return FunctionCallExpression(_f1412, _f1415, _f1416, _f1418, _f1419);
}

_m_NamedArgumentExpression_write(out: RecordOut, value: NamedArgumentExpression) {
    out.text(value.name);
    _m_Expression_write(out, value.value);
    out.loc(value.loc);
}

_m_NamedArgumentExpression_read(input: RecordIn): NamedArgumentExpression {
    var _f1420 = input.text();
    var _f1421 = _m_Expression_read(input);
    var _f1422 = input.loc();
    return NamedArgumentExpression(_f1421, _f1420, _f1422);
}

_m_DefaultArgumentExpression_write(out: RecordOut, value: DefaultArgumentExpression) {
    _m_TypeName_write(out, value.ty);
}

_m_DefaultArgumentExpression_read(input: RecordIn): DefaultArgumentExpression {
    var _f1423 = _m_TypeName_read(input);
    return DefaultArgumentExpression(_f1423);
}

_m_MethodCallExpression_write(out: RecordOut, value: MethodCallExpression) {
    _m_Expression_write(out, value.this_value);
    out.text(value.method);
    out.unsigned(value.args.count);
    for (var _item1424 in value.args) {
        _m_Expression_write(out, _item1424);
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
    var _f1425 = _m_Expression_read(input);
    var _f1426 = input.text();
    var _v1427 = Array<Expression>();
    var _n1428 = input.count();
    for (var _ in 0.._n1428) {
        _v1427.append(_m_Expression_read(input));
    }
    var _f1429 = _v1427;
    var _f1430 = input.loc();
    var _o1431 = Optional<TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o1431 = Optional<TypeName>.Value(_m_TypeName_read(input));
    }
    var _f1432 = _o1431;
    return MethodCallExpression(_f1425, _f1426, _f1429, _f1430, _f1432);
}

_m_FunctionRefExpression_write(out: RecordOut, value: FunctionRefExpression) {
    out.text(value.function);
    _m_TypeName_write(out, value.ty);
    out.loc(value.loc);
}

_m_FunctionRefExpression_read(input: RecordIn): FunctionRefExpression {
    var _f1433 = input.text();
    var _f1434 = _m_TypeName_read(input);
    var _f1435 = input.loc();
    return FunctionRefExpression(_f1433, _f1434, _f1435);
}

_m_InvokeExpression_write(out: RecordOut, value: InvokeExpression) {
    _m_Expression_write(out, value.callee);
    out.unsigned(value.args.count);
    for (var _item1436 in value.args) {
        _m_Expression_write(out, _item1436);
    }
}

_m_InvokeExpression_read(input: RecordIn): InvokeExpression {
    var _f1437 = _m_Expression_read(input);
    var _v1438 = Array<Expression>();
    var _n1439 = input.count();
    for (var _ in 0.._n1439) {
        _v1438.append(_m_Expression_read(input));
    }
    var _f1440 = _v1438;
    return InvokeExpression(_f1437, _f1440);
}

_m_MakeClosureExpression_write(out: RecordOut, value: MakeClosureExpression) {
    _m_Expression_write(out, value.value);
    out.text(value.closure);
    _m_TypeName_write(out, value.ty);
    out.loc(value.loc);
}

_m_MakeClosureExpression_read(input: RecordIn): MakeClosureExpression {
    var _f1442 = _m_Expression_read(input);
    var _f1443 = input.text();
    var _f1444 = _m_TypeName_read(input);
    var _f1445 = input.loc();
    return MakeClosureExpression(_f1442, _f1443, _f1444, _f1445);
}

_m_CallPointerExpression_write(out: RecordOut, value: CallPointerExpression) {
    _m_Expression_write(out, value.pointer);
    out.unsigned(value.args.count);
    for (var _item1447 in value.args) {
        _m_Expression_write(out, _item1447);
    }
}

_m_CallPointerExpression_read(input: RecordIn): CallPointerExpression {
    var _f1448 = _m_Expression_read(input);
    var _v1449 = Array<Expression>();
    var _n1450 = input.count();
    for (var _ in 0.._n1450) {
        _v1449.append(_m_Expression_read(input));
    }
    var _f1451 = _v1449;
    return CallPointerExpression(_f1448, _f1451);
}

_m_MoveExpression_write(out: RecordOut, value: MoveExpression) {
    _m_Expression_write(out, value.value);
    out.loc(value.loc);
}

_m_MoveExpression_read(input: RecordIn): MoveExpression {
    var _f1454 = _m_Expression_read(input);
    var _f1455 = input.loc();
    return MoveExpression(_f1454, _f1455);
}

_m_DestructureExpression_write(out: RecordOut, value: DestructureExpression) {
    _m_Expression_write(out, value.value);
    out.unsigned(value.count);
    out.loc(value.loc);
}

_m_DestructureExpression_read(input: RecordIn): DestructureExpression {
    var _f1456 = _m_Expression_read(input);
    var _f1457 = input.unsigned();
    var _f1458 = input.loc();
    return DestructureExpression(_f1456, _f1457, _f1458);
}

_m_StaticCaseExpression_write(out: RecordOut, value: StaticCaseExpression) {
    _m_TypeName_write(out, value.ty);
    out.signed(value.tag as long);
}

_m_StaticCaseExpression_read(input: RecordIn): StaticCaseExpression {
    var _f1461 = _m_TypeName_read(input);
    var _f1462 = input.signed();
    return StaticCaseExpression(_f1461, _f1462);
}

_m_StaticStringExpression_write(out: RecordOut, value: StaticStringExpression) {
    out.text(value.value);
    out.loc(value.loc);
}

_m_StaticStringExpression_read(input: RecordIn): StaticStringExpression {
    var _f1463 = input.text();
    var _f1464 = input.loc();
    return StaticStringExpression(_f1463, _f1464);
}

_m_SubjectExpression_write(out: RecordOut, value: SubjectExpression) {
    out.unsigned(value.id);
    _m_TypeName_write(out, value.ty);
    out.loc(value.loc);
}

_m_SubjectExpression_read(input: RecordIn): SubjectExpression {
    var _f1466 = input.unsigned();
    var _f1467 = _m_TypeName_read(input);
    var _f1468 = input.loc();
    return SubjectExpression(_f1466, _f1467, _f1468);
}

_m_ToTraitExpression_write(out: RecordOut, value: ToTraitExpression) {
    _m_Expression_write(out, value.value);
    _m_TypeName_write(out, value.from);
    _m_TypeName_write(out, value.to);
    out.loc(value.loc);
}

_m_ToTraitExpression_read(input: RecordIn): ToTraitExpression {
    var _f1469 = _m_Expression_read(input);
    var _f1470 = _m_TypeName_read(input);
    var _f1471 = _m_TypeName_read(input);
    var _f1472 = input.loc();
    return ToTraitExpression(_f1469, _f1470, _f1471, _f1472);
}

_m_FromTraitExpression_write(out: RecordOut, value: FromTraitExpression) {
    _m_Expression_write(out, value.value);
    _m_TypeName_write(out, value.from);
    _m_TypeName_write(out, value.to);
    out.unsigned(value.candidates.count);
    for (var _item1473 in value.candidates) {
        _m_TypeName_write(out, _item1473);
    }
    out.flag(value.test);
    out.loc(value.loc);
}

_m_FromTraitExpression_read(input: RecordIn): FromTraitExpression {
    var _f1474 = _m_Expression_read(input);
    var _f1475 = _m_TypeName_read(input);
    var _f1476 = _m_TypeName_read(input);
    var _v1477 = Array<TypeName>();
    var _n1478 = input.count();
    for (var _ in 0.._n1478) {
        _v1477.append(_m_TypeName_read(input));
    }
    var _f1479 = _v1477;
    var _f1480 = input.flag();
    var _f1481 = input.loc();
    return FromTraitExpression(_f1474, _f1475, _f1476, _f1479, _f1480, _f1481);
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
        var _f1344 = input.flag();
        return Expression.BoolLiteral(_f1344);
    }
    if (tag == 4) {
        var _f1345 = input.signed();
        return Expression.IntLiteral(_f1345);
    }
    if (tag == 5) {
        var _f1346 = input.number();
        return Expression.FloatLiteral(_f1346);
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
        var _f1371 = _m_TypeName_read(input);
        return Expression.SizeOf(_f1371);
    }
    if (tag == 15) {
        var _f1372 = _m_TypeName_read(input);
        return Expression.IsPod(_f1372);
    }
    if (tag == 16) {
        var _f1373 = _m_TypeName_read(input);
        return Expression.Default(_f1373);
    }
    if (tag == 17) {
        var _f1374 = _m_TypeName_read(input);
        return Expression.Allocate(_f1374);
    }
    if (tag == 18) {
        var _f1375 = _m_TypeName_read(input);
        var _f1376 = _m_Expression_read(input);
        return Expression.RefCount(_f1375, _f1376);
    }
    if (tag == 19) {
        var _f1377 = _m_TypeName_read(input);
        var _f1378 = _m_Expression_read(input);
        return Expression.Address(_f1377, _f1378);
    }
    if (tag == 20) {
        var _f1379 = _m_TypeName_read(input);
        var _f1380 = _m_Expression_read(input);
        return Expression.AtomicLoad(_f1379, _f1380);
    }
    if (tag == 21) {
        var _f1381 = _m_TypeName_read(input);
        var _f1382 = _m_Expression_read(input);
        var _f1383 = _m_Expression_read(input);
        return Expression.AtomicStore(_f1381, _f1382, _f1383);
    }
    if (tag == 22) {
        var _f1384 = _m_Expression_read(input);
        var _f1385 = _m_Expression_read(input);
        return Expression.ConstructAt(_f1384, _f1385);
    }
    if (tag == 23) {
        var _f1386 = _m_TypeName_read(input);
        var _f1387 = _m_Expression_read(input);
        var _f1388 = _m_Expression_read(input);
        var _f1389 = _m_Expression_read(input);
        return Expression.AtomicCmpXchg(_f1386, _f1387, _f1388, _f1389);
    }
    if (tag == 24) {
        var _f1390 = _m_AtomicFetchOp_read(input);
        var _f1391 = _m_TypeName_read(input);
        var _f1392 = _m_Expression_read(input);
        var _f1393 = _m_Expression_read(input);
        return Expression.AtomicFetch(_f1390, _f1391, _f1392, _f1393);
    }
    if (tag == 25) {
        return Expression.Simd(_m_SimdExpression_read(input));
    }
    if (tag == 26) {
        var _f1401 = _m_WeakOp_read(input);
        var _f1402 = _m_TypeName_read(input);
        var _f1403 = _m_Expression_read(input);
        return Expression.Weak(_f1401, _f1402, _f1403);
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
        var _f1441 = _m_ClosureLiteral_read(input);
        return Expression.ClosureLiteral(_f1441);
    }
    if (tag == 36) {
        return Expression.MakeClosure(_m_MakeClosureExpression_read(input));
    }
    if (tag == 37) {
        var _f1446 = input.text();
        return Expression.MethodAddress(_f1446);
    }
    if (tag == 38) {
        return Expression.CallPointer(_m_CallPointerExpression_read(input));
    }
    if (tag == 39) {
        var _f1452 = _m_Expression_read(input);
        return Expression.ForIterator(_f1452);
    }
    if (tag == 40) {
        var _f1453 = _m_Expression_read(input);
        return Expression.WithEntered(_f1453);
    }
    if (tag == 41) {
        return Expression.Move(_m_MoveExpression_read(input));
    }
    if (tag == 42) {
        return Expression.Destructure(_m_DestructureExpression_read(input));
    }
    if (tag == 43) {
        var _f1459 = _m_MatchArmTest_read(input);
        return Expression.MatchArm(_f1459);
    }
    if (tag == 44) {
        var _f1460 = _m_CaseValue_read(input);
        return Expression.CaseValue(_f1460);
    }
    if (tag == 45) {
        return Expression.StaticCase(_m_StaticCaseExpression_read(input));
    }
    if (tag == 46) {
        return Expression.StaticString(_m_StaticStringExpression_read(input));
    }
    if (tag == 47) {
        var _f1465 = _m_WithSubject_read(input);
        return Expression.WithSubject(_f1465);
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
        var _f1482 = _m_StaticValue_read(input);
        return Expression.StaticValue(_f1482);
    }
    if (tag == 53) {
        var _f1483 = _m_StaticMember_read(input);
        return Expression.StaticMember(_f1483);
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
        var _f1484 = _m_VariableDef_read(input);
        return Declaration.Variable(_f1484);
    }
    if (tag == 1) {
        var _f1485 = _m_FunctionDef_read(input);
        return Declaration.Function(_f1485);
    }
    if (tag == 2) {
        var _f1486 = _m_StructDef_read(input);
        return Declaration.Struct(_f1486);
    }
    if (tag == 3) {
        var _f1487 = _m_TraitDef_read(input);
        return Declaration.Trait(_f1487);
    }
    if (tag == 4) {
        var _f1488 = _m_ExtensionDef_read(input);
        return Declaration.Extension(_f1488);
    }
    if (tag == 5) {
        var _f1489 = _m_ExternDef_read(input);
        return Declaration.Extern(_f1489);
    }
    if (tag == 6) {
        var _f1490 = _m_TypeAliasDef_read(input);
        return Declaration.TypeAlias(_f1490);
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
    out.unsigned(value.trait_locs.count);
    for (var _item1060 in value.trait_locs) {
        out.loc(_item1060);
    }
    out.unsigned(value.restated.count);
    for (var _item1061 in value.restated) {
        var (_t1062, _t1063) = _item1061;
        out.unsigned(_t1062);
        _m_Bound_write(out, _t1063);
    }
    out.unsigned(value.methods.count);
    for (var _item1064 in value.methods) {
        _m_FunctionDef_write(out, _item1064);
    }
    out.unsigned(value.attributes.count);
    for (var _item1065 in value.attributes) {
        _a_Attribute_write(out, _item1065);
    }
    out.loc(value.loc);
    out.flag(value.is_exported);
    out.flag(value.is_private);
}

_m_ExtensionDef_read(input: RecordIn): ExtensionDef {
    var _f1066 = _m_TypeName_read(input);
    var _o1067 = Optional<String>.Empty;
    if (input.unsigned() == 1) {
        _o1067 = Optional<String>.Value(input.text());
    }
    var _f1068 = _o1067;
    var _v1069 = Array<TypeName>();
    var _n1070 = input.count();
    for (var _ in 0.._n1070) {
        _v1069.append(_m_TypeName_read(input));
    }
    var _f1071 = _v1069;
    var _v1072 = Array<Loc>();
    var _n1073 = input.count();
    for (var _ in 0.._n1073) {
        _v1072.append(input.loc());
    }
    var _f1074 = _v1072;
    var _v1075 = Array<(ulong, Bound)>();
    var _n1076 = input.count();
    for (var _ in 0.._n1076) {
        var _t1077 = input.unsigned();
        var _t1078 = _m_Bound_read(input);
        _v1075.append((_t1077, _t1078));
    }
    var _f1079 = _v1075;
    var _v1080 = Array<FunctionDef>();
    var _n1081 = input.count();
    for (var _ in 0.._n1081) {
        _v1080.append(_m_FunctionDef_read(input));
    }
    var _f1082 = _v1080;
    var _v1083 = Array<ast.Attribute>();
    var _n1084 = input.count();
    for (var _ in 0.._n1084) {
        _v1083.append(_a_Attribute_read(input));
    }
    var _f1085 = _v1083;
    var _f1086 = input.loc();
    var _f1087 = input.flag();
    var _f1088 = input.flag();
    return ExtensionDef(_f1066, _f1068, _f1071, _f1074, _f1079, _f1082, _f1085, _f1086, _f1087, _f1088);
}

_m_TraitDef_write(out: RecordOut, value: TraitDef) {
    out.text(value.name);
    out.unsigned(value.generic_params.count);
    for (var _item1089 in value.generic_params) {
        _m_GenericParam_write(out, _item1089);
    }
    out.unsigned(value.methods.count);
    for (var _item1090 in value.methods) {
        _m_FunctionDef_write(out, _item1090);
    }
    out.unsigned(value.attributes.count);
    for (var _item1091 in value.attributes) {
        _a_Attribute_write(out, _item1091);
    }
    out.loc(value.loc);
}

_m_TraitDef_read(input: RecordIn): TraitDef {
    var _f1092 = input.text();
    var _v1093 = Array<GenericParam>();
    var _n1094 = input.count();
    for (var _ in 0.._n1094) {
        _v1093.append(_m_GenericParam_read(input));
    }
    var _f1095 = _v1093;
    var _v1096 = Array<FunctionDef>();
    var _n1097 = input.count();
    for (var _ in 0.._n1097) {
        _v1096.append(_m_FunctionDef_read(input));
    }
    var _f1098 = _v1096;
    var _v1099 = Array<ast.Attribute>();
    var _n1100 = input.count();
    for (var _ in 0.._n1100) {
        _v1099.append(_a_Attribute_read(input));
    }
    var _f1101 = _v1099;
    var _f1102 = input.loc();
    return TraitDef(_f1092, _f1095, _f1098, _f1101, _f1102);
}

_m_StructDef_write(out: RecordOut, value: StructDef) {
    out.text(value.name);
    _m_TypeName_write(out, value.ty);
    out.unsigned(value.generic_params.count);
    for (var _item1103 in value.generic_params) {
        _m_GenericParam_write(out, _item1103);
    }
    out.unsigned(value.field_members.count);
    for (var _item1104 in value.field_members) {
        _m_VariableDef_write(out, _item1104);
    }
    out.unsigned(value.method_members.count);
    for (var _item1105 in value.method_members) {
        _m_FunctionDef_write(out, _item1105);
    }
    out.unsigned(value.generic_methods.count);
    for (var _item1106 in value.generic_methods) {
        _m_FunctionDef_write(out, _item1106);
    }
    out.unsigned(value.constructors.count);
    for (var _item1107 in value.constructors) {
        _m_FunctionDef_write(out, _item1107);
    }
    _m_FunctionDef_write(out, value.destructor);
    _m_FunctionDef_write(out, value.acquire);
    _m_FunctionDef_write(out, value.release);
    out.unsigned(value.traits.count);
    for (var _item1108 in value.traits) {
        _m_TypeName_write(out, _item1108);
    }
    out.unsigned(value.attributes.count);
    for (var _item1109 in value.attributes) {
        _a_Attribute_write(out, _item1109);
    }
    out.loc(value.loc);
    if (value.enum_cases.is_value()) {
        out.unsigned(1);
        out.unsigned(value.enum_cases.value().count);
        for (var _item1110 in value.enum_cases.value()) {
            _m_EnumCaseDef_write(out, _item1110);
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
    var _f1111 = input.text();
    var _f1112 = _m_TypeName_read(input);
    var _v1113 = Array<GenericParam>();
    var _n1114 = input.count();
    for (var _ in 0.._n1114) {
        _v1113.append(_m_GenericParam_read(input));
    }
    var _f1115 = _v1113;
    var _v1116 = Array<VariableDef>();
    var _n1117 = input.count();
    for (var _ in 0.._n1117) {
        _v1116.append(_m_VariableDef_read(input));
    }
    var _f1118 = _v1116;
    var _v1119 = Array<FunctionDef>();
    var _n1120 = input.count();
    for (var _ in 0.._n1120) {
        _v1119.append(_m_FunctionDef_read_with(input, lazy));
    }
    var _f1121 = _v1119;
    var _v1122 = Array<FunctionDef>();
    var _n1123 = input.count();
    for (var _ in 0.._n1123) {
        _v1122.append(_m_FunctionDef_read(input));
    }
    var _f1124 = _v1122;
    var _v1125 = Array<FunctionDef>();
    var _n1126 = input.count();
    for (var _ in 0.._n1126) {
        _v1125.append(_m_FunctionDef_read_with(input, lazy));
    }
    var _f1127 = _v1125;
    var _f1128 = _m_FunctionDef_read_with(input, lazy);
    var _f1129 = _m_FunctionDef_read_with(input, lazy);
    var _f1130 = _m_FunctionDef_read_with(input, lazy);
    var _v1131 = Array<TypeName>();
    var _n1132 = input.count();
    for (var _ in 0.._n1132) {
        _v1131.append(_m_TypeName_read(input));
    }
    var _f1133 = _v1131;
    var _v1134 = Array<ast.Attribute>();
    var _n1135 = input.count();
    for (var _ in 0.._n1135) {
        _v1134.append(_a_Attribute_read(input));
    }
    var _f1136 = _v1134;
    var _f1137 = input.loc();
    var _o1138 = Optional<Array<EnumCaseDef>>.Empty;
    if (input.unsigned() == 1) {
        var _v1139 = Array<EnumCaseDef>();
        var _n1140 = input.count();
        for (var _ in 0.._n1140) {
            _v1139.append(_m_EnumCaseDef_read(input));
        }
        _o1138 = Optional<Array<EnumCaseDef>>.Value(_v1139);
    }
    var _f1141 = _o1138;
    return StructDef(
        _f1111, _f1112, _f1115, _f1118, _f1121, _f1124, _f1127, _f1128, _f1129, _f1130, _f1133, _f1136, _f1137, _f1141
    );
}

_m_EnumCaseDef_write(out: RecordOut, value: EnumCaseDef) {
    out.text(value.name);
    out.signed(value.value as long);
    out.unsigned(value.payload.count);
    for (var _item1142 in value.payload) {
        var (_t1143, _t1144) = _item1142;
        out.text(_t1143);
        out.loc(_t1144);
    }
    out.unsigned(value.attributes.count);
    for (var _item1145 in value.attributes) {
        _a_Attribute_write(out, _item1145);
    }
    out.loc(value.loc);
}

_m_EnumCaseDef_read(input: RecordIn): EnumCaseDef {
    var _f1146 = input.text();
    var _f1147 = input.signed();
    var _v1148 = Array<(String, Loc)>();
    var _n1149 = input.count();
    for (var _ in 0.._n1149) {
        var _t1150 = input.text();
        var _t1151 = input.loc();
        _v1148.append((_t1150, _t1151));
    }
    var _f1152 = _v1148;
    var _v1153 = Array<ast.Attribute>();
    var _n1154 = input.count();
    for (var _ in 0.._n1154) {
        _v1153.append(_a_Attribute_read(input));
    }
    var _f1155 = _v1153;
    var _f1156 = input.loc();
    return EnumCaseDef(_f1146, _f1147, _f1152, _f1155, _f1156);
}

_m_ExtensionScopes_write(out: RecordOut, value: ExtensionScopes) {
    var _keys1158 = Array<(u8[], u8[], uint)>();
    for (var _key1157 in value.prelude) {
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
    out.unsigned(value.visible.count);
    for (var _item1162 in value.visible) {
        var _keys1164 = Array<(u8[], u8[], uint)>();
        for (var _key1163 in _item1162) {
            var _scratch1165 = out.scratch();
            _scratch1165.unsigned(_key1163 as ulong);
            var _vscratch1167 = out.scratch();
            _keys1164.append((_scratch1165.finish(), _vscratch1167.finish(), _key1163));
        }
        _keys1164.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1164.count);
        for (var (_bytes1166, _, _key1163) in _keys1164) {
            out.unsigned(_key1163 as ulong);
        }
    }
    out.unsigned(value.module.count);
    for (var _item1168 in value.module) {
        if (_item1168.is_value()) {
            out.unsigned(1);
            out.unsigned(_item1168.value() as ulong);
        } else {
            out.unsigned(0);
        }
    }
}

_m_ExtensionScopes_read(input: RecordIn): ExtensionScopes {
    var _v1169 = HashSet<uint>();
    var _n1170 = input.count();
    for (var _ in 0.._n1170) {
        _v1169.insert(input.unsigned() as uint);
    }
    var _f1171 = _v1169;
    var _v1172 = Array<HashSet<uint>>();
    var _n1173 = input.count();
    for (var _ in 0.._n1173) {
        var _v1174 = HashSet<uint>();
        var _n1175 = input.count();
        for (var _ in 0.._n1175) {
            _v1174.insert(input.unsigned() as uint);
        }
        _v1172.append(_v1174);
    }
    var _f1176 = _v1172;
    var _v1177 = Array<Optional<uint>>();
    var _n1178 = input.count();
    for (var _ in 0.._n1178) {
        var _o1179 = Optional<uint>.Empty;
        if (input.unsigned() == 1) {
            _o1179 = Optional<uint>.Value(input.unsigned() as uint);
        }
        _v1177.append(_o1179);
    }
    var _f1180 = _v1177;
    return ExtensionScopes(_f1171, _f1176, _f1180);
}

_m_Conversion_write(out: RecordOut, value: Conversion) {
    out.loc(value.at);
    _m_TypeName_write(out, value.from);
    _m_TypeName_write(out, value.to);
    out.loc(value.constructor);
}

_m_Conversion_read(input: RecordIn): Conversion {
    var _f1181 = input.loc();
    var _f1182 = _m_TypeName_read(input);
    var _f1183 = _m_TypeName_read(input);
    var _f1184 = input.loc();
    return Conversion(_f1181, _f1182, _f1183, _f1184);
}

_m_TraitType_write(out: RecordOut, value: TraitType) {
    _m_TypeName_write(out, value.ty);
    out.unsigned(value.methods.count);
    for (var _item1185 in value.methods) {
        _m_FunctionDef_write(out, _item1185);
    }
}

_m_TraitType_read(input: RecordIn): TraitType {
    var _f1186 = _m_TypeName_read(input);
    var _v1187 = Array<FunctionDef>();
    var _n1188 = input.count();
    for (var _ in 0.._n1188) {
        _v1187.append(_m_FunctionDef_read(input));
    }
    var _f1189 = _v1187;
    return TraitType(_f1186, _f1189);
}

_m_UseContext_write(out: RecordOut, value: UseContext) {
    out.unsigned(value.scope.count);
    for (var _item1190 in value.scope) {
        _m_GenericParam_write(out, _item1190);
    }
    if (value.extension.is_value()) {
        out.unsigned(1);
        _m_TypeName_write(out, value.extension.value());
    } else {
        out.unsigned(0);
    }
    out.unsigned(value.conditions.count);
    for (var _item1191 in value.conditions) {
        _a_Attribute_write(out, _item1191);
    }
}

_m_UseContext_read(input: RecordIn): UseContext {
    var _v1192 = Array<GenericParam>();
    var _n1193 = input.count();
    for (var _ in 0.._n1193) {
        _v1192.append(_m_GenericParam_read(input));
    }
    var _f1194 = _v1192;
    var _o1195 = Optional<TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o1195 = Optional<TypeName>.Value(_m_TypeName_read(input));
    }
    var _f1196 = _o1195;
    var _v1197 = Array<ast.Attribute>();
    var _n1198 = input.count();
    for (var _ in 0.._n1198) {
        _v1197.append(_a_Attribute_read(input));
    }
    var _f1199 = _v1197;
    return UseContext(_f1194, _f1196, _f1199);
}

_m_TypeUse_write(out: RecordOut, value: TypeUse) {
    _m_TypeName_write(out, value.ty);
    out.unsigned(value.args.count);
    for (var _item1200 in value.args) {
        out.loc(_item1200);
    }
    out.unsigned(value.context);
}

_m_TypeUse_read(input: RecordIn): TypeUse {
    var _f1201 = _m_TypeName_read(input);
    var _v1202 = Array<Loc>();
    var _n1203 = input.count();
    for (var _ in 0.._n1203) {
        _v1202.append(input.loc());
    }
    var _f1204 = _v1202;
    var _f1205 = input.unsigned();
    return TypeUse(_f1201, _f1204, _f1205);
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
    var _f1206 = input.text();
    var _f1207 = input.text();
    var _f1208 = input.flag();
    var _f1209 = input.loc();
    var _f1210 = _m_AccessorKind_read(input);
    var _o1211 = Optional<AccessorKind>.Empty;
    if (input.unsigned() == 1) {
        _o1211 = Optional<AccessorKind>.Value(_m_AccessorKind_read(input));
    }
    var _f1212 = _o1211;
    var _f1213 = input.loc();
    var _o1214 = Optional<String>.Empty;
    if (input.unsigned() == 1) {
        _o1214 = Optional<String>.Value(input.text());
    }
    var _f1215 = _o1214;
    var _f1216 = input.flag();
    return PropertyDef(_f1206, _f1207, _f1208, _f1209, _f1210, _f1212, _f1213, _f1215, _f1216);
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
    var _f1217 = input.text();
    var _f1218 = input.text();
    var _f1219 = input.text();
    var _f1220 = input.unsigned();
    var _f1221 = _m_TypeName_read(input);
    var _f1222 = _m_TypeName_read(input);
    var _f1223 = input.loc();
    return Withheld(_f1217, _f1218, _f1219, _f1220, _f1221, _f1222, _f1223);
}

_m_EnumDef_write(out: RecordOut, value: EnumDef) {
    out.text(value.name);
    _m_TypeName_write(out, value.representation);
    out.unsigned(value.cases.count);
    for (var _item1224 in value.cases) {
        _m_EnumCaseDef_write(out, _item1224);
    }
    out.unsigned(value.attributes.count);
    for (var _item1225 in value.attributes) {
        _a_Attribute_write(out, _item1225);
    }
    out.loc(value.loc);
}

_m_EnumDef_read(input: RecordIn): EnumDef {
    var _f1226 = input.text();
    var _f1227 = _m_TypeName_read(input);
    var _v1228 = Array<EnumCaseDef>();
    var _n1229 = input.count();
    for (var _ in 0.._n1229) {
        _v1228.append(_m_EnumCaseDef_read(input));
    }
    var _f1230 = _v1228;
    var _v1231 = Array<ast.Attribute>();
    var _n1232 = input.count();
    for (var _ in 0.._n1232) {
        _v1231.append(_a_Attribute_read(input));
    }
    var _f1233 = _v1231;
    var _f1234 = input.loc();
    return EnumDef(_f1226, _f1227, _f1230, _f1233, _f1234);
}

_m_ModuleStaticBlock_write(out: RecordOut, value: ModuleStaticBlock) {
    _m_StaticBlock_write(out, value.block);
    out.unsigned(value.constants.count);
    for (var _item1235 in value.constants) {
        var (_t1236, _t1237) = _item1235;
        out.text(_t1236);
        out.loc(_t1237);
    }
}

_m_ModuleStaticBlock_read(input: RecordIn): ModuleStaticBlock {
    var _f1238 = _m_StaticBlock_read(input);
    var _v1239 = Array<(String, Loc)>();
    var _n1240 = input.count();
    for (var _ in 0.._n1240) {
        var _t1241 = input.text();
        var _t1242 = input.loc();
        _v1239.append((_t1241, _t1242));
    }
    var _f1243 = _v1239;
    return ModuleStaticBlock(_f1238, _f1243);
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
        for (var _item1244 in value.symbols.value()) {
            _a_ImportedSymbol_write(out, _item1244);
        }
    } else {
        out.unsigned(0);
    }
    out.flag(value.reexport);
    out.unsigned(value.attributes.count);
    for (var _item1245 in value.attributes) {
        _a_Attribute_write(out, _item1245);
    }
    out.unsigned(out.blank_locs ? 0 : value.span.start);
    out.unsigned(out.blank_locs ? 0 : value.span.end);
}

_a_Import_read(input: RecordIn): ast.Import {
    var _f1246 = input.text();
    var _s1247 = input.unsigned();
    var _f1248 = ast.Span(_s1247, input.unsigned());
    var _o1249 = Optional<String>.Empty;
    if (input.unsigned() == 1) {
        _o1249 = Optional<String>.Value(input.text());
    }
    var _f1250 = _o1249;
    var _f1251 = input.flag();
    var _o1252 = Optional<Array<ast.ImportedSymbol>>.Empty;
    if (input.unsigned() == 1) {
        var _v1253 = Array<ast.ImportedSymbol>();
        var _n1254 = input.count();
        for (var _ in 0.._n1254) {
            _v1253.append(_a_ImportedSymbol_read(input));
        }
        _o1252 = Optional<Array<ast.ImportedSymbol>>.Value(_v1253);
    }
    var _f1255 = _o1252;
    var _f1256 = input.flag();
    var _v1257 = Array<ast.Attribute>();
    var _n1258 = input.count();
    for (var _ in 0.._n1258) {
        _v1257.append(_a_Attribute_read(input));
    }
    var _f1259 = _v1257;
    var _s1260 = input.unsigned();
    var _f1261 = ast.Span(_s1260, input.unsigned());
    var value = ast.Import();
    value.name = _f1246;
    value.name_span = _f1248;
    value.alias = _f1250;
    value.is_local = _f1251;
    value.symbols = _f1255;
    value.reexport = _f1256;
    value.attributes = _f1259;
    value.span = _f1261;
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
    var _f1262 = input.text();
    var _s1263 = input.unsigned();
    var _f1264 = ast.Span(_s1263, input.unsigned());
    var _o1265 = Optional<String>.Empty;
    if (input.unsigned() == 1) {
        _o1265 = Optional<String>.Value(input.text());
    }
    var _f1266 = _o1265;
    var _s1267 = input.unsigned();
    var _f1268 = ast.Span(_s1267, input.unsigned());
    var value = ast.ImportedSymbol();
    value.name = _f1262;
    value.name_span = _f1264;
    value.alias = _f1266;
    value.span = _f1268;
    return value;
}

_m_Module_write_delta(out: RecordOut, value: Module, base: DeltaBase) {
    ulong _mark = out.values.count;
    var _hs1496 = Array<String>();
    for (var _item1491 in value.imports) {
        var scratch = base.scratch();
        _a_Import_write(scratch, _item1491);
        _hs1496.append(base.hash_of(scratch));
    }
    var _seq1497 = base.sequence("imports");
    ulong _bj1498 = 0;
    var _news1499 = Array<ulong>();
    for (var _i1500 in 0.._hs1496.count) {
        if (_bj1498 < _seq1497.count and _hs1496[_i1500] == _seq1497[_bj1498]) {
            _bj1498 += 1;
        } else {
            _news1499.append(_i1500);
        }
    }
    if (_bj1498 == _seq1497.count) {
        out.unsigned(2);
        out.unsigned(_news1499.count);
        for (var _i1500 in _news1499) {
            out.unsigned(_i1500);
            _a_Import_write(out, value.imports[_i1500]);
            {
                var _own1501 = RecordOut();
                _own1501.blank_bodies = true;
                _own1501.blank_locs = true;
                _own1501.pending_as_bytes = true;
                _a_Import_write(_own1501, value.imports[_i1500]);
                base.own("imports", interface_text(_own1501));
            }
        }
        base.count("imports" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("imports" + " whole", 0);
        out.unsigned(value.imports.count);
        for (var _i1500 in 0..value.imports.count) {
            _a_Import_write(out, value.imports[_i1500]);
            {
                var _own1502 = RecordOut();
                _own1502.blank_bodies = true;
                _own1502.blank_locs = true;
                _own1502.pending_as_bytes = true;
                _a_Import_write(_own1502, value.imports[_i1500]);
                base.own("imports", interface_text(_own1502));
            }
        }
    }
    base.stat("imports", out.values.count - _mark);
    _mark = out.values.count;
    var _seq1512 = base.ref_structs;
    ulong _bj1513 = 0;
    var _news1515 = Array<ulong>();
    var _patches1516 = Array<(ulong, ulong)>();
    for (var _i1517 in 0..value.structs.count) {
        if (_bj1513 < _seq1512.count
            and value.structs[_i1517] === _seq1512[_bj1513]
            and !value.extended_checked.contains(value.structs[_i1517].name)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_StructDef_write(scratch, value.structs[_i1517]);
                base.verify_same("s", _bj1513, scratch, value.structs[_i1517].name);
            }
            _bj1513 += 1;
        } else if (_bj1513 < _seq1512.count
            and !(value.structs[_i1517] === _seq1512[_bj1513])
            and _same_m_StructDef(value.structs[_i1517], _seq1512[_bj1513], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_StructDef_write(scratch, value.structs[_i1517]);
                base.verify_same("s", _bj1513, scratch, value.structs[_i1517].name);
            }
            _bj1513 += 1;
        } else if (_bj1513 < _seq1512.count and value.structs[_i1517].name == _seq1512[_bj1513].name) {
            _patches1516.append((_i1517, _bj1513));
            _bj1513 += 1;
        } else {
            _news1515.append(_i1517);
        }
    }
    if (_bj1513 == _seq1512.count) {
        out.unsigned(2);
        out.unsigned(_patches1516.count);
        for (var (_i1517, _b) in _patches1516) {
            ulong _before = out.values.count;
            out.text(value.structs[_i1517].name);
            out.unsigned(_b);
            _patch_s_write(out, value.structs[_i1517], base, _b);
            base.count("s patched", out.values.count - _before);
            {
                var _own1518 = RecordOut();
                _own1518.blank_bodies = true;
                _own1518.blank_locs = true;
                _own1518.pending_as_bytes = true;
                var _s1519 = value.structs[_i1517];
                var _methods1520 = _s1519.method_members;
                _s1519.method_members = Array<FunctionDef>();
                var _fields1521 = _s1519.field_members;
                var split__fields1521 = splits_fields(_s1519);
                if (split__fields1521) {
                    _s1519.field_members = Array<VariableDef>();
                }
                _m_StructDef_write(_own1518, _s1519);
                _s1519.method_members = _methods1520;
                _s1519.field_members = _fields1521;
                base.own_named("structs", _s1519.name, interface_text(_own1518));
                for (var _m1522 in _methods1520) {
                    var _own1523 = RecordOut();
                    _own1523.blank_bodies = true;
                    _own1523.blank_locs = true;
                    _own1523.pending_as_bytes = true;
                    _m_FunctionDef_write(_own1523, _m1522);
                    base.own_method("structs", _s1519.name, _m1522.name, interface_text(_own1523));
                }
                if (_s1519.is_value()) {
                    for (var _m1522 in _s1519.constructors) {
                        var _own1523 = RecordOut();
                        _own1523.blank_locs = true;
                        _own1523.pending_as_bytes = true;
                        _m_FunctionDef_write(_own1523, _m1522);
                        base.own_method("structs", _s1519.name, "__ctor", interface_text(_own1523));
                    }
                }
                if (split__fields1521) {
                    var _order1525 = StringBuilder();
                    for (var _f1524 in _fields1521) {
                        var _own1526 = RecordOut();
                        _own1526.blank_locs = true;
                        _m_VariableDef_write(_own1526, _f1524);
                        base.own_method("structs", _s1519.name, "." + _f1524.name, interface_text(_own1526));
                        _order1525.append(_f1524.name);
                        _order1525.append(",");
                    }
                    base.own_method("structs", _s1519.name, ".#order", _order1525.to_string());
                }
            }
        }
        out.unsigned(_news1515.count);
        for (var _i1517 in _news1515) {
            ulong _before = out.values.count;
            out.unsigned(_i1517);
            _m_StructDef_write(out, value.structs[_i1517]);
            base.count("s new", out.values.count - _before);
            {
                var _own1527 = RecordOut();
                _own1527.blank_bodies = true;
                _own1527.blank_locs = true;
                _own1527.pending_as_bytes = true;
                var _s1528 = value.structs[_i1517];
                var _methods1529 = _s1528.method_members;
                _s1528.method_members = Array<FunctionDef>();
                var _fields1530 = _s1528.field_members;
                var split__fields1530 = splits_fields(_s1528);
                if (split__fields1530) {
                    _s1528.field_members = Array<VariableDef>();
                }
                _m_StructDef_write(_own1527, _s1528);
                _s1528.method_members = _methods1529;
                _s1528.field_members = _fields1530;
                base.own_named("structs", _s1528.name, interface_text(_own1527));
                for (var _m1531 in _methods1529) {
                    var _own1532 = RecordOut();
                    _own1532.blank_bodies = true;
                    _own1532.blank_locs = true;
                    _own1532.pending_as_bytes = true;
                    _m_FunctionDef_write(_own1532, _m1531);
                    base.own_method("structs", _s1528.name, _m1531.name, interface_text(_own1532));
                }
                if (_s1528.is_value()) {
                    for (var _m1531 in _s1528.constructors) {
                        var _own1532 = RecordOut();
                        _own1532.blank_locs = true;
                        _own1532.pending_as_bytes = true;
                        _m_FunctionDef_write(_own1532, _m1531);
                        base.own_method("structs", _s1528.name, "__ctor", interface_text(_own1532));
                    }
                }
                if (split__fields1530) {
                    var _order1534 = StringBuilder();
                    for (var _f1533 in _fields1530) {
                        var _own1535 = RecordOut();
                        _own1535.blank_locs = true;
                        _m_VariableDef_write(_own1535, _f1533);
                        base.own_method("structs", _s1528.name, "." + _f1533.name, interface_text(_own1535));
                        _order1534.append(_f1533.name);
                        _order1534.append(",");
                    }
                    base.own_method("structs", _s1528.name, ".#order", _order1534.to_string());
                }
            }
        }
        base.count("s merged", 0);
    } else {
        out.unsigned(1);
        base.count("s by place", 0);
        var _struct_hits1511 = HashSet<long>();
        var _slots1514 = HashMap<String, long>();
        for (var _i1517 in 0.._seq1512.count) {
            if (!_slots1514.contains(_seq1512[_i1517].name)) {
                _slots1514[_seq1512[_i1517].name] = _i1517 as long;
            }
        }
        out.unsigned(value.structs.count);
        for (var _i1517 in 0..value.structs.count) {
            var _item1510 = value.structs[_i1517];
            var _slot = _slots1514.try_get(_item1510.name);
            long named = _slot.is_value() ? _slot.value() : -1;
            long at = -1;
            if (named >= 0
                and _seq1512[named as ulong] === _item1510
                and !value.extended_checked.contains(_item1510.name)) {
                at = named;
            }
            ulong _before = out.values.count;
            if (at >= 0) {
                _struct_hits1511.insert(at);
                out.unsigned((at as ulong) * 2 + 1);
            } else if (named >= 0) {
                _struct_hits1511.insert(named);
                out.unsigned(2);
                out.unsigned(named as ulong);
                _patch_s_write(out, _item1510, base, named as ulong);
                base.count("s patched", out.values.count - _before);
            } else {
                out.unsigned(0);
                _m_StructDef_write(out, _item1510);
                base.count("s new", out.values.count - _before);
            }
        }
        base.missed("s", "s", _struct_hits1511.count);
    }
    base.stat("structs", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1549 = Array<String>();
    for (var _item1544 in value.traits) {
        var scratch = base.scratch();
        _m_TraitDef_write(scratch, _item1544);
        _hs1549.append(base.hash_of(scratch));
    }
    var _seq1550 = base.sequence("traits");
    ulong _bj1551 = 0;
    var _news1552 = Array<ulong>();
    for (var _i1553 in 0.._hs1549.count) {
        if (_bj1551 < _seq1550.count and _hs1549[_i1553] == _seq1550[_bj1551]) {
            _bj1551 += 1;
        } else {
            _news1552.append(_i1553);
        }
    }
    if (_bj1551 == _seq1550.count) {
        out.unsigned(2);
        out.unsigned(_news1552.count);
        for (var _i1553 in _news1552) {
            out.unsigned(_i1553);
            _m_TraitDef_write(out, value.traits[_i1553]);
            {
                var _own1554 = RecordOut();
                _own1554.blank_bodies = false;
                _own1554.blank_locs = true;
                _own1554.pending_as_bytes = true;
                _m_TraitDef_write(_own1554, value.traits[_i1553]);
                base.own("traits", interface_text(_own1554));
            }
        }
        base.count("traits" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("traits" + " whole", 0);
        out.unsigned(value.traits.count);
        for (var _i1553 in 0..value.traits.count) {
            _m_TraitDef_write(out, value.traits[_i1553]);
            {
                var _own1555 = RecordOut();
                _own1555.blank_bodies = false;
                _own1555.blank_locs = true;
                _own1555.pending_as_bytes = true;
                _m_TraitDef_write(_own1555, value.traits[_i1553]);
                base.own("traits", interface_text(_own1555));
            }
        }
    }
    base.stat("traits", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1568 = Array<String>();
    for (var _item1563 in value.extensions) {
        var scratch = base.scratch();
        _m_ExtensionDef_write(scratch, _item1563);
        _hs1568.append(base.hash_of(scratch));
    }
    var _seq1569 = base.sequence("extensions");
    ulong _bj1570 = 0;
    var _news1571 = Array<ulong>();
    for (var _i1572 in 0.._hs1568.count) {
        if (_bj1570 < _seq1569.count and _hs1568[_i1572] == _seq1569[_bj1570]) {
            _bj1570 += 1;
        } else {
            _news1571.append(_i1572);
        }
    }
    if (_bj1570 == _seq1569.count) {
        out.unsigned(2);
        out.unsigned(_news1571.count);
        for (var _i1572 in _news1571) {
            out.unsigned(_i1572);
            _m_ExtensionDef_write(out, value.extensions[_i1572]);
            {
                var _own1573 = RecordOut();
                _own1573.blank_bodies = true;
                _own1573.blank_locs = true;
                _own1573.pending_as_bytes = true;
                _m_ExtensionDef_write(_own1573, value.extensions[_i1572]);
                base.own("extensions", interface_text(_own1573));
            }
        }
        base.count("extensions" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("extensions" + " whole", 0);
        out.unsigned(value.extensions.count);
        for (var _i1572 in 0..value.extensions.count) {
            _m_ExtensionDef_write(out, value.extensions[_i1572]);
            {
                var _own1574 = RecordOut();
                _own1574.blank_bodies = true;
                _own1574.blank_locs = true;
                _own1574.pending_as_bytes = true;
                _m_ExtensionDef_write(_own1574, value.extensions[_i1572]);
                base.own("extensions", interface_text(_own1574));
            }
        }
    }
    base.stat("extensions", out.values.count - _mark);
    _mark = out.values.count;
    var _seq1587 = base.ref_functions;
    ulong _bj1588 = 0;
    var _news1589 = Array<ulong>();
    var _changed1583 = Array<(ulong, ulong)>();
    for (var _i1590 in 0..value.functions.count) {
        if (_bj1588 < _seq1587.count and value.functions[_i1590] === _seq1587[_bj1588]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.functions[_i1590]);
                base.verify_same("functions", _bj1588, scratch);
            }
            _bj1588 += 1;
        } else if (_bj1588 < _seq1587.count and _same_m_FunctionDef(value.functions[_i1590], _seq1587[_bj1588], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.functions[_i1590]);
                base.verify_same("functions", _bj1588, scratch);
            }
            _bj1588 += 1;
        } else if (_bj1588 < _seq1587.count and value.functions[_i1590].name == _seq1587[_bj1588].name) {
            _changed1583.append((_i1590, _bj1588));
            _bj1588 += 1;
        } else {
            _news1589.append(_i1590);
        }
    }
    if (_bj1588 == _seq1587.count) {
        out.unsigned(2);
        out.unsigned(_changed1583.count);
        for (var (_i1590, _b) in _changed1583) {
            out.text(value.functions[_i1590].name);
            out.unsigned(_b);
            _m_FunctionDef_write(out, value.functions[_i1590]);
            {
                var _own1591 = RecordOut();
                _own1591.blank_bodies = true;
                _own1591.blank_locs = true;
                _own1591.pending_as_bytes = true;
                _m_FunctionDef_write(_own1591, value.functions[_i1590]);
                base.own_function("functions", value.functions[_i1590], interface_text(_own1591));
            }
        }
        base.count("functions" + " changed", _changed1583.count);
        out.unsigned(_news1589.count);
        for (var _i1590 in _news1589) {
            out.unsigned(_i1590);
            _m_FunctionDef_write(out, value.functions[_i1590]);
            {
                var _own1592 = RecordOut();
                _own1592.blank_bodies = true;
                _own1592.blank_locs = true;
                _own1592.pending_as_bytes = true;
                _m_FunctionDef_write(_own1592, value.functions[_i1590]);
                base.own_function("functions", value.functions[_i1590], interface_text(_own1592));
            }
        }
        base.count("functions" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("functions" + " whole", 0);
        out.unsigned(value.functions.count);
        for (var _i1590 in 0..value.functions.count) {
            _m_FunctionDef_write(out, value.functions[_i1590]);
            {
                var _own1593 = RecordOut();
                _own1593.blank_bodies = true;
                _own1593.blank_locs = true;
                _own1593.pending_as_bytes = true;
                _m_FunctionDef_write(_own1593, value.functions[_i1590]);
                base.own_function("functions", value.functions[_i1590], interface_text(_own1593));
            }
        }
    }
    base.stat("functions", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1606 = Array<String>();
    for (var _item1601 in value.externs) {
        var scratch = base.scratch();
        _m_ExternDef_write(scratch, _item1601);
        _hs1606.append(base.hash_of(scratch));
    }
    var _seq1607 = base.sequence("externs");
    ulong _bj1608 = 0;
    var _news1609 = Array<ulong>();
    for (var _i1610 in 0.._hs1606.count) {
        if (_bj1608 < _seq1607.count and _hs1606[_i1610] == _seq1607[_bj1608]) {
            _bj1608 += 1;
        } else {
            _news1609.append(_i1610);
        }
    }
    if (_bj1608 == _seq1607.count) {
        out.unsigned(2);
        out.unsigned(_news1609.count);
        for (var _i1610 in _news1609) {
            out.unsigned(_i1610);
            _m_ExternDef_write(out, value.externs[_i1610]);
            {
                var _own1611 = RecordOut();
                _own1611.blank_bodies = true;
                _own1611.blank_locs = true;
                _own1611.pending_as_bytes = true;
                _m_ExternDef_write(_own1611, value.externs[_i1610]);
                base.own("externs", interface_text(_own1611));
            }
        }
        base.count("externs" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("externs" + " whole", 0);
        out.unsigned(value.externs.count);
        for (var _i1610 in 0..value.externs.count) {
            _m_ExternDef_write(out, value.externs[_i1610]);
            {
                var _own1612 = RecordOut();
                _own1612.blank_bodies = true;
                _own1612.blank_locs = true;
                _own1612.pending_as_bytes = true;
                _m_ExternDef_write(_own1612, value.externs[_i1610]);
                base.own("externs", interface_text(_own1612));
            }
        }
    }
    base.stat("externs", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1625 = Array<String>();
    for (var _item1620 in value.globals) {
        var scratch = base.scratch();
        _m_VariableDef_write(scratch, _item1620);
        _hs1625.append(base.hash_of(scratch));
    }
    var _seq1626 = base.sequence("globals");
    ulong _bj1627 = 0;
    var _news1628 = Array<ulong>();
    for (var _i1629 in 0.._hs1625.count) {
        if (_bj1627 < _seq1626.count and _hs1625[_i1629] == _seq1626[_bj1627]) {
            _bj1627 += 1;
        } else {
            _news1628.append(_i1629);
        }
    }
    if (_bj1627 == _seq1626.count) {
        out.unsigned(2);
        out.unsigned(_news1628.count);
        for (var _i1629 in _news1628) {
            out.unsigned(_i1629);
            _m_VariableDef_write(out, value.globals[_i1629]);
            {
                var _own1630 = RecordOut();
                _own1630.blank_bodies = true;
                _own1630.blank_locs = true;
                _own1630.pending_as_bytes = true;
                _m_VariableDef_write(_own1630, value.globals[_i1629]);
                base.own("globals", interface_text(_own1630));
            }
        }
        base.count("globals" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("globals" + " whole", 0);
        out.unsigned(value.globals.count);
        for (var _i1629 in 0..value.globals.count) {
            _m_VariableDef_write(out, value.globals[_i1629]);
            {
                var _own1631 = RecordOut();
                _own1631.blank_bodies = true;
                _own1631.blank_locs = true;
                _own1631.pending_as_bytes = true;
                _m_VariableDef_write(_own1631, value.globals[_i1629]);
                base.own("globals", interface_text(_own1631));
            }
        }
    }
    base.stat("globals", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1644 = Array<String>();
    for (var _item1639 in value.static_blocks) {
        var scratch = base.scratch();
        _m_ModuleStaticBlock_write(scratch, _item1639);
        _hs1644.append(base.hash_of(scratch));
    }
    var _seq1645 = base.sequence("static_blocks");
    ulong _bj1646 = 0;
    var _news1647 = Array<ulong>();
    for (var _i1648 in 0.._hs1644.count) {
        if (_bj1646 < _seq1645.count and _hs1644[_i1648] == _seq1645[_bj1646]) {
            _bj1646 += 1;
        } else {
            _news1647.append(_i1648);
        }
    }
    if (_bj1646 == _seq1645.count) {
        out.unsigned(2);
        out.unsigned(_news1647.count);
        for (var _i1648 in _news1647) {
            out.unsigned(_i1648);
            _m_ModuleStaticBlock_write(out, value.static_blocks[_i1648]);
            {
                var _own1649 = RecordOut();
                _own1649.blank_bodies = true;
                _own1649.blank_locs = true;
                _own1649.pending_as_bytes = true;
                _m_ModuleStaticBlock_write(_own1649, value.static_blocks[_i1648]);
                base.own("static_blocks", interface_text(_own1649));
            }
        }
        base.count("static_blocks" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("static_blocks" + " whole", 0);
        out.unsigned(value.static_blocks.count);
        for (var _i1648 in 0..value.static_blocks.count) {
            _m_ModuleStaticBlock_write(out, value.static_blocks[_i1648]);
            {
                var _own1650 = RecordOut();
                _own1650.blank_bodies = true;
                _own1650.blank_locs = true;
                _own1650.pending_as_bytes = true;
                _m_ModuleStaticBlock_write(_own1650, value.static_blocks[_i1648]);
                base.own("static_blocks", interface_text(_own1650));
            }
        }
    }
    base.stat("static_blocks", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1663 = Array<String>();
    for (var _item1658 in value.enums) {
        var scratch = base.scratch();
        _m_EnumDef_write(scratch, _item1658);
        _hs1663.append(base.hash_of(scratch));
    }
    var _seq1664 = base.sequence("enums");
    ulong _bj1665 = 0;
    var _news1666 = Array<ulong>();
    for (var _i1667 in 0.._hs1663.count) {
        if (_bj1665 < _seq1664.count and _hs1663[_i1667] == _seq1664[_bj1665]) {
            _bj1665 += 1;
        } else {
            _news1666.append(_i1667);
        }
    }
    if (_bj1665 == _seq1664.count) {
        out.unsigned(2);
        out.unsigned(_news1666.count);
        for (var _i1667 in _news1666) {
            out.unsigned(_i1667);
            _m_EnumDef_write(out, value.enums[_i1667]);
            {
                var _own1668 = RecordOut();
                _own1668.blank_bodies = true;
                _own1668.blank_locs = true;
                _own1668.pending_as_bytes = true;
                _m_EnumDef_write(_own1668, value.enums[_i1667]);
                base.own_named("enums", value.enums[_i1667].name, interface_text(_own1668));
            }
        }
        base.count("enums" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("enums" + " whole", 0);
        out.unsigned(value.enums.count);
        for (var _i1667 in 0..value.enums.count) {
            _m_EnumDef_write(out, value.enums[_i1667]);
            {
                var _own1669 = RecordOut();
                _own1669.blank_bodies = true;
                _own1669.blank_locs = true;
                _own1669.pending_as_bytes = true;
                _m_EnumDef_write(_own1669, value.enums[_i1667]);
                base.own_named("enums", value.enums[_i1667].name, interface_text(_own1669));
            }
        }
    }
    base.stat("enums", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1682 = Array<String>();
    for (var _item1677 in value.struct_specs) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item1677);
        _hs1682.append(base.hash_of(scratch));
    }
    var _seq1683 = base.sequence("struct_specs");
    ulong _bj1684 = 0;
    var _news1685 = Array<ulong>();
    for (var _i1686 in 0.._hs1682.count) {
        if (_bj1684 < _seq1683.count and _hs1682[_i1686] == _seq1683[_bj1684]) {
            _bj1684 += 1;
        } else {
            _news1685.append(_i1686);
        }
    }
    if (_bj1684 == _seq1683.count) {
        out.unsigned(2);
        out.unsigned(_news1685.count);
        for (var _i1686 in _news1685) {
            out.unsigned(_i1686);
            _m_TypeName_write(out, value.struct_specs[_i1686]);
            {
                var _own1687 = RecordOut();
                _own1687.blank_bodies = true;
                _own1687.blank_locs = true;
                _own1687.pending_as_bytes = true;
                _m_TypeName_write(_own1687, value.struct_specs[_i1686]);
                base.own("struct_specs", interface_text(_own1687));
            }
        }
        base.count("struct_specs" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("struct_specs" + " whole", 0);
        out.unsigned(value.struct_specs.count);
        for (var _i1686 in 0..value.struct_specs.count) {
            _m_TypeName_write(out, value.struct_specs[_i1686]);
            {
                var _own1688 = RecordOut();
                _own1688.blank_bodies = true;
                _own1688.blank_locs = true;
                _own1688.pending_as_bytes = true;
                _m_TypeName_write(_own1688, value.struct_specs[_i1686]);
                base.own("struct_specs", interface_text(_own1688));
            }
        }
    }
    base.stat("struct_specs", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1701 = Array<String>();
    for (var _item1696 in value.func_specs) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item1696);
        _hs1701.append(base.hash_of(scratch));
    }
    var _seq1702 = base.sequence("func_specs");
    ulong _bj1703 = 0;
    var _news1704 = Array<ulong>();
    for (var _i1705 in 0.._hs1701.count) {
        if (_bj1703 < _seq1702.count and _hs1701[_i1705] == _seq1702[_bj1703]) {
            _bj1703 += 1;
        } else {
            _news1704.append(_i1705);
        }
    }
    if (_bj1703 == _seq1702.count) {
        out.unsigned(2);
        out.unsigned(_news1704.count);
        for (var _i1705 in _news1704) {
            out.unsigned(_i1705);
            _m_TypeName_write(out, value.func_specs[_i1705]);
            {
                var _own1706 = RecordOut();
                _own1706.blank_bodies = true;
                _own1706.blank_locs = true;
                _own1706.pending_as_bytes = true;
                _m_TypeName_write(_own1706, value.func_specs[_i1705]);
                base.own("func_specs", interface_text(_own1706));
            }
        }
        base.count("func_specs" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("func_specs" + " whole", 0);
        out.unsigned(value.func_specs.count);
        for (var _i1705 in 0..value.func_specs.count) {
            _m_TypeName_write(out, value.func_specs[_i1705]);
            {
                var _own1707 = RecordOut();
                _own1707.blank_bodies = true;
                _own1707.blank_locs = true;
                _own1707.pending_as_bytes = true;
                _m_TypeName_write(_own1707, value.func_specs[_i1705]);
                base.own("func_specs", interface_text(_own1707));
            }
        }
    }
    base.stat("func_specs", out.values.count - _mark);
    _mark = out.values.count;
    var _hits1719 = HashSet<long>();
    out.unsigned(value.type_aliases.count);
    for (var _item1715 in value.type_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1715);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed("type_aliases", hash);
        if (at >= 0) {
            _hits1719.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_TypeAliasDef_write(out, _item1715);
        }
    }
    base.missed("type_aliases", "type_aliases", _hits1719.count);
    base.stat("type_aliases", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1729 = Array<String>();
    for (var _item1724 in value.withheld) {
        var scratch = base.scratch();
        _m_Withheld_write(scratch, _item1724);
        _hs1729.append(base.hash_of(scratch));
    }
    var _seq1730 = base.sequence("withheld");
    ulong _bj1731 = 0;
    var _news1732 = Array<ulong>();
    for (var _i1733 in 0.._hs1729.count) {
        if (_bj1731 < _seq1730.count and _hs1729[_i1733] == _seq1730[_bj1731]) {
            _bj1731 += 1;
        } else {
            _news1732.append(_i1733);
        }
    }
    if (_bj1731 == _seq1730.count) {
        out.unsigned(2);
        out.unsigned(_news1732.count);
        for (var _i1733 in _news1732) {
            out.unsigned(_i1733);
            _m_Withheld_write(out, value.withheld[_i1733]);
            {
                var _own1734 = RecordOut();
                _own1734.blank_bodies = true;
                _own1734.blank_locs = true;
                _own1734.pending_as_bytes = true;
                _m_Withheld_write(_own1734, value.withheld[_i1733]);
                base.own("withheld", interface_text(_own1734));
            }
        }
        base.count("withheld" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("withheld" + " whole", 0);
        out.unsigned(value.withheld.count);
        for (var _i1733 in 0..value.withheld.count) {
            _m_Withheld_write(out, value.withheld[_i1733]);
            {
                var _own1735 = RecordOut();
                _own1735.blank_bodies = true;
                _own1735.blank_locs = true;
                _own1735.pending_as_bytes = true;
                _m_Withheld_write(_own1735, value.withheld[_i1733]);
                base.own("withheld", interface_text(_own1735));
            }
        }
    }
    base.stat("withheld", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1748 = Array<String>();
    for (var _item1743 in value.properties) {
        var scratch = base.scratch();
        _m_PropertyDef_write(scratch, _item1743);
        _hs1748.append(base.hash_of(scratch));
    }
    var _seq1749 = base.sequence("properties");
    ulong _bj1750 = 0;
    var _news1751 = Array<ulong>();
    for (var _i1752 in 0.._hs1748.count) {
        if (_bj1750 < _seq1749.count and _hs1748[_i1752] == _seq1749[_bj1750]) {
            _bj1750 += 1;
        } else {
            _news1751.append(_i1752);
        }
    }
    if (_bj1750 == _seq1749.count) {
        out.unsigned(2);
        out.unsigned(_news1751.count);
        for (var _i1752 in _news1751) {
            out.unsigned(_i1752);
            _m_PropertyDef_write(out, value.properties[_i1752]);
            {
                var _own1753 = RecordOut();
                _own1753.blank_bodies = true;
                _own1753.blank_locs = true;
                _own1753.pending_as_bytes = true;
                _m_PropertyDef_write(_own1753, value.properties[_i1752]);
                base.own("properties", interface_text(_own1753));
            }
        }
        base.count("properties" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("properties" + " whole", 0);
        out.unsigned(value.properties.count);
        for (var _i1752 in 0..value.properties.count) {
            _m_PropertyDef_write(out, value.properties[_i1752]);
            {
                var _own1754 = RecordOut();
                _own1754.blank_bodies = true;
                _own1754.blank_locs = true;
                _own1754.pending_as_bytes = true;
                _m_PropertyDef_write(_own1754, value.properties[_i1752]);
                base.own("properties", interface_text(_own1754));
            }
        }
    }
    base.stat("properties", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1767 = Array<String>();
    for (var _item1762 in value.type_uses) {
        var scratch = base.scratch();
        _m_TypeUse_write(scratch, _item1762);
        _hs1767.append(base.hash_of(scratch));
    }
    var _seq1768 = base.sequence("type_uses");
    ulong _bj1769 = 0;
    var _news1770 = Array<ulong>();
    for (var _i1771 in 0.._hs1767.count) {
        if (_bj1769 < _seq1768.count and _hs1767[_i1771] == _seq1768[_bj1769]) {
            _bj1769 += 1;
        } else {
            _news1770.append(_i1771);
        }
    }
    if (_bj1769 == _seq1768.count) {
        out.unsigned(2);
        out.unsigned(_news1770.count);
        for (var _i1771 in _news1770) {
            out.unsigned(_i1771);
            _m_TypeUse_write(out, value.type_uses[_i1771]);
            {
                var _own1772 = RecordOut();
                _own1772.blank_bodies = true;
                _own1772.blank_locs = true;
                _own1772.pending_as_bytes = true;
                _m_TypeUse_write(_own1772, value.type_uses[_i1771]);
                base.own("type_uses", interface_text(_own1772));
            }
        }
        base.count("type_uses" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("type_uses" + " whole", 0);
        out.unsigned(value.type_uses.count);
        for (var _i1771 in 0..value.type_uses.count) {
            _m_TypeUse_write(out, value.type_uses[_i1771]);
            {
                var _own1773 = RecordOut();
                _own1773.blank_bodies = true;
                _own1773.blank_locs = true;
                _own1773.pending_as_bytes = true;
                _m_TypeUse_write(_own1773, value.type_uses[_i1771]);
                base.own("type_uses", interface_text(_own1773));
            }
        }
    }
    base.stat("type_uses", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1786 = Array<String>();
    for (var _item1781 in value.use_contexts) {
        var scratch = base.scratch();
        _m_UseContext_write(scratch, _item1781);
        _hs1786.append(base.hash_of(scratch));
    }
    var _seq1787 = base.sequence("use_contexts");
    ulong _bj1788 = 0;
    var _news1789 = Array<ulong>();
    for (var _i1790 in 0.._hs1786.count) {
        if (_bj1788 < _seq1787.count and _hs1786[_i1790] == _seq1787[_bj1788]) {
            _bj1788 += 1;
        } else {
            _news1789.append(_i1790);
        }
    }
    if (_bj1788 == _seq1787.count) {
        out.unsigned(2);
        out.unsigned(_news1789.count);
        for (var _i1790 in _news1789) {
            out.unsigned(_i1790);
            _m_UseContext_write(out, value.use_contexts[_i1790]);
            {
                var _own1791 = RecordOut();
                _own1791.blank_bodies = true;
                _own1791.blank_locs = true;
                _own1791.pending_as_bytes = true;
                _m_UseContext_write(_own1791, value.use_contexts[_i1790]);
                base.own("use_contexts", interface_text(_own1791));
            }
        }
        base.count("use_contexts" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("use_contexts" + " whole", 0);
        out.unsigned(value.use_contexts.count);
        for (var _i1790 in 0..value.use_contexts.count) {
            _m_UseContext_write(out, value.use_contexts[_i1790]);
            {
                var _own1792 = RecordOut();
                _own1792.blank_bodies = true;
                _own1792.blank_locs = true;
                _own1792.pending_as_bytes = true;
                _m_UseContext_write(_own1792, value.use_contexts[_i1790]);
                base.own("use_contexts", interface_text(_own1792));
            }
        }
    }
    base.stat("use_contexts", out.values.count - _mark);
    _mark = out.values.count;
    var _n1802 = base.size("literal_args");
    var _scratch1801 = base.scratch();
    if (value.literal_args.count >= _n1802) {
        for (var _i1803 in 0.._n1802) {
            var (_t1804, _t1805, _t1806) = value.literal_args[_i1803];
            _scratch1801.loc(_t1804);
            _scratch1801.unsigned(_t1805);
            _scratch1801.loc(_t1806);
        }
    }
    if (value.literal_args.count >= _n1802 and base.same_list("literal_args", _scratch1801)) {
        out.unsigned(1);
        out.unsigned(_n1802);
        out.unsigned(value.literal_args.count - _n1802);
        for (var _i1803 in _n1802..value.literal_args.count) {
            var (_t1807, _t1808, _t1809) = value.literal_args[_i1803];
            out.loc(_t1807);
            out.unsigned(_t1808);
            out.loc(_t1809);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.literal_args.count);
        for (var _item1810 in value.literal_args) {
            var (_t1811, _t1812, _t1813) = _item1810;
            out.loc(_t1811);
            out.unsigned(_t1812);
            out.loc(_t1813);
        }
        base.count("literal_args whole", 0);
    }
    base.stat("literal_args", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1836 = Array<String>();
    for (var _item1831 in value.constrained_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1831);
        _hs1836.append(base.hash_of(scratch));
    }
    var _seq1837 = base.sequence("constrained_aliases");
    ulong _bj1838 = 0;
    var _news1839 = Array<ulong>();
    for (var _i1840 in 0.._hs1836.count) {
        if (_bj1838 < _seq1837.count and _hs1836[_i1840] == _seq1837[_bj1838]) {
            _bj1838 += 1;
        } else {
            _news1839.append(_i1840);
        }
    }
    if (_bj1838 == _seq1837.count) {
        out.unsigned(2);
        out.unsigned(_news1839.count);
        for (var _i1840 in _news1839) {
            out.unsigned(_i1840);
            _m_TypeAliasDef_write(out, value.constrained_aliases[_i1840]);
            {
                var _own1841 = RecordOut();
                _own1841.blank_bodies = true;
                _own1841.blank_locs = true;
                _own1841.pending_as_bytes = true;
                _m_TypeAliasDef_write(_own1841, value.constrained_aliases[_i1840]);
                base.own("constrained_aliases", interface_text(_own1841));
            }
        }
        base.count("constrained_aliases" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("constrained_aliases" + " whole", 0);
        out.unsigned(value.constrained_aliases.count);
        for (var _i1840 in 0..value.constrained_aliases.count) {
            _m_TypeAliasDef_write(out, value.constrained_aliases[_i1840]);
            {
                var _own1842 = RecordOut();
                _own1842.blank_bodies = true;
                _own1842.blank_locs = true;
                _own1842.pending_as_bytes = true;
                _m_TypeAliasDef_write(_own1842, value.constrained_aliases[_i1840]);
                base.own("constrained_aliases", interface_text(_own1842));
            }
        }
    }
    base.stat("constrained_aliases", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1855 = Array<String>();
    for (var _item1850 in value.trait_types) {
        var scratch = base.scratch();
        _m_TraitType_write(scratch, _item1850);
        _hs1855.append(base.hash_of(scratch));
    }
    var _seq1856 = base.sequence("trait_types");
    ulong _bj1857 = 0;
    var _news1858 = Array<ulong>();
    for (var _i1859 in 0.._hs1855.count) {
        if (_bj1857 < _seq1856.count and _hs1855[_i1859] == _seq1856[_bj1857]) {
            _bj1857 += 1;
        } else {
            _news1858.append(_i1859);
        }
    }
    if (_bj1857 == _seq1856.count) {
        out.unsigned(2);
        out.unsigned(_news1858.count);
        for (var _i1859 in _news1858) {
            out.unsigned(_i1859);
            _m_TraitType_write(out, value.trait_types[_i1859]);
            {
                var _own1860 = RecordOut();
                _own1860.blank_bodies = true;
                _own1860.blank_locs = true;
                _own1860.pending_as_bytes = true;
                _m_TraitType_write(_own1860, value.trait_types[_i1859]);
                base.own("trait_types", interface_text(_own1860));
            }
        }
        base.count("trait_types" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("trait_types" + " whole", 0);
        out.unsigned(value.trait_types.count);
        for (var _i1859 in 0..value.trait_types.count) {
            _m_TraitType_write(out, value.trait_types[_i1859]);
            {
                var _own1861 = RecordOut();
                _own1861.blank_bodies = true;
                _own1861.blank_locs = true;
                _own1861.pending_as_bytes = true;
                _m_TraitType_write(_own1861, value.trait_types[_i1859]);
                base.own("trait_types", interface_text(_own1861));
            }
        }
    }
    base.stat("trait_types", out.values.count - _mark);
    _mark = out.values.count;
    out.unsigned(value.conversions.count);
    for (var _item1869 in value.conversions) {
        _m_Conversion_write(out, _item1869);
    }
    for (var _conv1870 in value.conversions) {
        var _own1871 = RecordOut();
        _own1871.blank_locs = true;
        _m_Conversion_write(_own1871, _conv1870);
        var _h = interface_text(_own1871);
        if (base.find_hashed("conversions", _h) < 0) {
            base.own("conversions", _h);
        }
    }
    base.stat("conversions", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept1879 = 0;
    var _news1880 = Map<String, Array<String>>();
    for (var (_key1876, _) in value.overload_sets) {
        var _kscratch1877 = base.scratch();
        _kscratch1877.text(_key1876);
        var _vscratch1878 = base.scratch();
        _vscratch1878.unsigned(value.overload_sets[_key1876].count);
        for (var _item1881 in value.overload_sets[_key1876]) {
            _vscratch1878.text(_item1881);
        }
        var _had = base.entry("overload_sets", _kscratch1877, _vscratch1878);
        if (_had >= 0) {
            _kept1879 += 1;
        }
        if (_had != 1) {
            _news1880[_key1876] = value.overload_sets[_key1876];
        }
    }
    if (_kept1879 == base.size("overload_sets")) {
        out.unsigned(1);
        var _keys1883 = Array<(u8[], u8[], String)>();
        for (var (_key1882, _) in _news1880) {
            var _scratch1884 = out.scratch();
            _scratch1884.text(_key1882);
            var _vscratch1886 = out.scratch();
            _vscratch1886.unsigned(_news1880[_key1882].count);
            for (var _item1887 in _news1880[_key1882]) {
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
            out.unsigned(_news1880[_key1882].count);
            for (var _item1888 in _news1880[_key1882]) {
                out.text(_item1888);
            }
        }
        for (var (_okey1889, _) in _news1880) {
            var _own1890 = RecordOut();
            _own1890.blank_bodies = true;
            _own1890.blank_locs = true;
            _own1890.pending_as_bytes = true;
            _own1890.text(_okey1889);
            _own1890.unsigned(_news1880[_okey1889].count);
            for (var _item1891 in _news1880[_okey1889]) {
                _own1890.text(_item1891);
            }
            base.own("overload_sets", interface_text(_own1890));
        }
    } else {
        out.unsigned(0);
        var _keys1893 = Array<(u8[], u8[], String)>();
        for (var (_key1892, _) in value.overload_sets) {
            var _scratch1894 = out.scratch();
            _scratch1894.text(_key1892);
            var _vscratch1896 = out.scratch();
            _vscratch1896.unsigned(value.overload_sets[_key1892].count);
            for (var _item1897 in value.overload_sets[_key1892]) {
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
            out.unsigned(value.overload_sets[_key1892].count);
            for (var _item1898 in value.overload_sets[_key1892]) {
                out.text(_item1898);
            }
        }
        for (var (_okey1899, _) in value.overload_sets) {
            var _own1900 = RecordOut();
            _own1900.blank_bodies = true;
            _own1900.blank_locs = true;
            _own1900.pending_as_bytes = true;
            _own1900.text(_okey1899);
            _own1900.unsigned(value.overload_sets[_okey1899].count);
            for (var _item1901 in value.overload_sets[_okey1899]) {
                _own1900.text(_item1901);
            }
            base.own("overload_sets", interface_text(_own1900));
        }
        base.count("overload_sets whole", 0);
    }
    base.stat("overload_sets", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept1919 = 0;
    var _news1920 = Map<String, Array<Array<String>>>();
    for (var (_key1916, _) in value.overload_unions) {
        var _kscratch1917 = base.scratch();
        _kscratch1917.text(_key1916);
        var _vscratch1918 = base.scratch();
        _vscratch1918.unsigned(value.overload_unions[_key1916].count);
        for (var _item1921 in value.overload_unions[_key1916]) {
            _vscratch1918.unsigned(_item1921.count);
            for (var _item1922 in _item1921) {
                _vscratch1918.text(_item1922);
            }
        }
        var _had = base.entry("overload_unions", _kscratch1917, _vscratch1918);
        if (_had >= 0) {
            _kept1919 += 1;
        }
        if (_had != 1) {
            _news1920[_key1916] = value.overload_unions[_key1916];
        }
    }
    if (_kept1919 == base.size("overload_unions")) {
        out.unsigned(1);
        var _keys1924 = Array<(u8[], u8[], String)>();
        for (var (_key1923, _) in _news1920) {
            var _scratch1925 = out.scratch();
            _scratch1925.text(_key1923);
            var _vscratch1927 = out.scratch();
            _vscratch1927.unsigned(_news1920[_key1923].count);
            for (var _item1928 in _news1920[_key1923]) {
                _vscratch1927.unsigned(_item1928.count);
                for (var _item1929 in _item1928) {
                    _vscratch1927.text(_item1929);
                }
            }
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
            out.text(_key1923);
            out.unsigned(_news1920[_key1923].count);
            for (var _item1930 in _news1920[_key1923]) {
                out.unsigned(_item1930.count);
                for (var _item1931 in _item1930) {
                    out.text(_item1931);
                }
            }
        }
        for (var (_okey1932, _) in _news1920) {
            var _own1933 = RecordOut();
            _own1933.blank_bodies = true;
            _own1933.blank_locs = true;
            _own1933.pending_as_bytes = true;
            _own1933.text(_okey1932);
            _own1933.unsigned(_news1920[_okey1932].count);
            for (var _item1934 in _news1920[_okey1932]) {
                _own1933.unsigned(_item1934.count);
                for (var _item1935 in _item1934) {
                    _own1933.text(_item1935);
                }
            }
            base.own("overload_unions", interface_text(_own1933));
        }
    } else {
        out.unsigned(0);
        var _keys1937 = Array<(u8[], u8[], String)>();
        for (var (_key1936, _) in value.overload_unions) {
            var _scratch1938 = out.scratch();
            _scratch1938.text(_key1936);
            var _vscratch1940 = out.scratch();
            _vscratch1940.unsigned(value.overload_unions[_key1936].count);
            for (var _item1941 in value.overload_unions[_key1936]) {
                _vscratch1940.unsigned(_item1941.count);
                for (var _item1942 in _item1941) {
                    _vscratch1940.text(_item1942);
                }
            }
            _keys1937.append((_scratch1938.finish(), _vscratch1940.finish(), _key1936));
        }
        _keys1937.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1937.count);
        for (var (_bytes1939, _, _key1936) in _keys1937) {
            out.text(_key1936);
            out.unsigned(value.overload_unions[_key1936].count);
            for (var _item1943 in value.overload_unions[_key1936]) {
                out.unsigned(_item1943.count);
                for (var _item1944 in _item1943) {
                    out.text(_item1944);
                }
            }
        }
        for (var (_okey1945, _) in value.overload_unions) {
            var _own1946 = RecordOut();
            _own1946.blank_bodies = true;
            _own1946.blank_locs = true;
            _own1946.pending_as_bytes = true;
            _own1946.text(_okey1945);
            _own1946.unsigned(value.overload_unions[_okey1945].count);
            for (var _item1947 in value.overload_unions[_okey1945]) {
                _own1946.unsigned(_item1947.count);
                for (var _item1948 in _item1947) {
                    _own1946.text(_item1948);
                }
            }
            base.own("overload_unions", interface_text(_own1946));
        }
        base.count("overload_unions whole", 0);
    }
    base.stat("overload_unions", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept1971 = 0;
    var _news1972 = Map<String, Map<String, Array<String>>>();
    for (var (_key1968, _) in value.method_overload_sets) {
        var _kscratch1969 = base.scratch();
        _kscratch1969.text(_key1968);
        var _vscratch1970 = base.scratch();
        var _keys1974 = Array<(u8[], u8[], String)>();
        for (var (_key1973, _) in value.method_overload_sets[_key1968]) {
            var _scratch1975 = _vscratch1970.scratch();
            _scratch1975.text(_key1973);
            var _vscratch1977 = _vscratch1970.scratch();
            _vscratch1977.unsigned(value.method_overload_sets[_key1968][_key1973].count);
            for (var _item1978 in value.method_overload_sets[_key1968][_key1973]) {
                _vscratch1977.text(_item1978);
            }
            _keys1974.append((_scratch1975.finish(), _vscratch1977.finish(), _key1973));
        }
        _keys1974.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        _vscratch1970.unsigned(_keys1974.count);
        for (var (_bytes1976, _, _key1973) in _keys1974) {
            _vscratch1970.text(_key1973);
            _vscratch1970.unsigned(value.method_overload_sets[_key1968][_key1973].count);
            for (var _item1979 in value.method_overload_sets[_key1968][_key1973]) {
                _vscratch1970.text(_item1979);
            }
        }
        var _had = base.entry("method_overload_sets", _kscratch1969, _vscratch1970);
        if (_had >= 0) {
            _kept1971 += 1;
        }
        if (_had != 1) {
            _news1972[_key1968] = value.method_overload_sets[_key1968];
        }
    }
    if (_kept1971 == base.size("method_overload_sets")) {
        out.unsigned(1);
        var _keys1981 = Array<(u8[], u8[], String)>();
        for (var (_key1980, _) in _news1972) {
            var _scratch1982 = out.scratch();
            _scratch1982.text(_key1980);
            var _vscratch1984 = out.scratch();
            var _keys1986 = Array<(u8[], u8[], String)>();
            for (var (_key1985, _) in _news1972[_key1980]) {
                var _scratch1987 = _vscratch1984.scratch();
                _scratch1987.text(_key1985);
                var _vscratch1989 = _vscratch1984.scratch();
                _vscratch1989.unsigned(_news1972[_key1980][_key1985].count);
                for (var _item1990 in _news1972[_key1980][_key1985]) {
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
            _vscratch1984.unsigned(_keys1986.count);
            for (var (_bytes1988, _, _key1985) in _keys1986) {
                _vscratch1984.text(_key1985);
                _vscratch1984.unsigned(_news1972[_key1980][_key1985].count);
                for (var _item1991 in _news1972[_key1980][_key1985]) {
                    _vscratch1984.text(_item1991);
                }
            }
            _keys1981.append((_scratch1982.finish(), _vscratch1984.finish(), _key1980));
        }
        _keys1981.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1981.count);
        for (var (_bytes1983, _, _key1980) in _keys1981) {
            out.text(_key1980);
            var _keys1993 = Array<(u8[], u8[], String)>();
            for (var (_key1992, _) in _news1972[_key1980]) {
                var _scratch1994 = out.scratch();
                _scratch1994.text(_key1992);
                var _vscratch1996 = out.scratch();
                _vscratch1996.unsigned(_news1972[_key1980][_key1992].count);
                for (var _item1997 in _news1972[_key1980][_key1992]) {
                    _vscratch1996.text(_item1997);
                }
                _keys1993.append((_scratch1994.finish(), _vscratch1996.finish(), _key1992));
            }
            _keys1993.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            out.unsigned(_keys1993.count);
            for (var (_bytes1995, _, _key1992) in _keys1993) {
                out.text(_key1992);
                out.unsigned(_news1972[_key1980][_key1992].count);
                for (var _item1998 in _news1972[_key1980][_key1992]) {
                    out.text(_item1998);
                }
            }
        }
        for (var (_okey1999, _) in _news1972) {
            var _own2000 = RecordOut();
            _own2000.blank_bodies = true;
            _own2000.blank_locs = true;
            _own2000.pending_as_bytes = true;
            _own2000.text(_okey1999);
            var _keys2002 = Array<(u8[], u8[], String)>();
            for (var (_key2001, _) in _news1972[_okey1999]) {
                var _scratch2003 = _own2000.scratch();
                _scratch2003.text(_key2001);
                var _vscratch2005 = _own2000.scratch();
                _vscratch2005.unsigned(_news1972[_okey1999][_key2001].count);
                for (var _item2006 in _news1972[_okey1999][_key2001]) {
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
            _own2000.unsigned(_keys2002.count);
            for (var (_bytes2004, _, _key2001) in _keys2002) {
                _own2000.text(_key2001);
                _own2000.unsigned(_news1972[_okey1999][_key2001].count);
                for (var _item2007 in _news1972[_okey1999][_key2001]) {
                    _own2000.text(_item2007);
                }
            }
            base.own("method_overload_sets", interface_text(_own2000));
        }
    } else {
        out.unsigned(0);
        var _keys2009 = Array<(u8[], u8[], String)>();
        for (var (_key2008, _) in value.method_overload_sets) {
            var _scratch2010 = out.scratch();
            _scratch2010.text(_key2008);
            var _vscratch2012 = out.scratch();
            var _keys2014 = Array<(u8[], u8[], String)>();
            for (var (_key2013, _) in value.method_overload_sets[_key2008]) {
                var _scratch2015 = _vscratch2012.scratch();
                _scratch2015.text(_key2013);
                var _vscratch2017 = _vscratch2012.scratch();
                _vscratch2017.unsigned(value.method_overload_sets[_key2008][_key2013].count);
                for (var _item2018 in value.method_overload_sets[_key2008][_key2013]) {
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
            _vscratch2012.unsigned(_keys2014.count);
            for (var (_bytes2016, _, _key2013) in _keys2014) {
                _vscratch2012.text(_key2013);
                _vscratch2012.unsigned(value.method_overload_sets[_key2008][_key2013].count);
                for (var _item2019 in value.method_overload_sets[_key2008][_key2013]) {
                    _vscratch2012.text(_item2019);
                }
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
            var _keys2021 = Array<(u8[], u8[], String)>();
            for (var (_key2020, _) in value.method_overload_sets[_key2008]) {
                var _scratch2022 = out.scratch();
                _scratch2022.text(_key2020);
                var _vscratch2024 = out.scratch();
                _vscratch2024.unsigned(value.method_overload_sets[_key2008][_key2020].count);
                for (var _item2025 in value.method_overload_sets[_key2008][_key2020]) {
                    _vscratch2024.text(_item2025);
                }
                _keys2021.append((_scratch2022.finish(), _vscratch2024.finish(), _key2020));
            }
            _keys2021.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            out.unsigned(_keys2021.count);
            for (var (_bytes2023, _, _key2020) in _keys2021) {
                out.text(_key2020);
                out.unsigned(value.method_overload_sets[_key2008][_key2020].count);
                for (var _item2026 in value.method_overload_sets[_key2008][_key2020]) {
                    out.text(_item2026);
                }
            }
        }
        for (var (_okey2027, _) in value.method_overload_sets) {
            var _own2028 = RecordOut();
            _own2028.blank_bodies = true;
            _own2028.blank_locs = true;
            _own2028.pending_as_bytes = true;
            _own2028.text(_okey2027);
            var _keys2030 = Array<(u8[], u8[], String)>();
            for (var (_key2029, _) in value.method_overload_sets[_okey2027]) {
                var _scratch2031 = _own2028.scratch();
                _scratch2031.text(_key2029);
                var _vscratch2033 = _own2028.scratch();
                _vscratch2033.unsigned(value.method_overload_sets[_okey2027][_key2029].count);
                for (var _item2034 in value.method_overload_sets[_okey2027][_key2029]) {
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
            _own2028.unsigned(_keys2030.count);
            for (var (_bytes2032, _, _key2029) in _keys2030) {
                _own2028.text(_key2029);
                _own2028.unsigned(value.method_overload_sets[_okey2027][_key2029].count);
                for (var _item2035 in value.method_overload_sets[_okey2027][_key2029]) {
                    _own2028.text(_item2035);
                }
            }
            base.own("method_overload_sets", interface_text(_own2028));
        }
        base.count("method_overload_sets whole", 0);
    }
    base.stat("method_overload_sets", out.values.count - _mark);
    _mark = out.values.count;
    _m_ExtensionScopes_write(out, value.extension_scopes);
    base.stat("extension_scopes", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2066 = 0;
    var _news2067 = HashSet<Loc>();
    for (var _key2063 in value.private_functions) {
        var _kscratch2064 = base.scratch();
        _kscratch2064.loc(_key2063);
        var _vscratch2065 = base.scratch();
        var _had = base.entry("private_functions", _kscratch2064, _vscratch2065);
        if (_had >= 0) {
            _kept2066 += 1;
        }
        if (_had != 1) {
            _news2067.insert(_key2063);
        }
    }
    if (_kept2066 == base.size("private_functions")) {
        out.unsigned(1);
        var _keys2069 = Array<(u8[], u8[], Loc)>();
        for (var _key2068 in _news2067) {
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
        for (var _okey2073 in _news2067) {
            var _own2074 = RecordOut();
            _own2074.blank_bodies = true;
            _own2074.blank_locs = true;
            _own2074.pending_as_bytes = true;
            _own2074.loc(_okey2073);
            base.own_at("private_functions", _okey2073, interface_text(_own2074));
        }
    } else {
        out.unsigned(0);
        var _keys2076 = Array<(u8[], u8[], Loc)>();
        for (var _key2075 in value.private_functions) {
            var _scratch2077 = out.scratch();
            _scratch2077.loc(_key2075);
            var _vscratch2079 = out.scratch();
            _keys2076.append((_scratch2077.finish(), _vscratch2079.finish(), _key2075));
        }
        _keys2076.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2076.count);
        for (var (_bytes2078, _, _key2075) in _keys2076) {
            out.loc(_key2075);
        }
        for (var _okey2080 in value.private_functions) {
            var _own2081 = RecordOut();
            _own2081.blank_bodies = true;
            _own2081.blank_locs = true;
            _own2081.pending_as_bytes = true;
            _own2081.loc(_okey2080);
            base.own_at("private_functions", _okey2080, interface_text(_own2081));
        }
        base.count("private_functions whole", 0);
    }
    base.stat("private_functions", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2092 = 0;
    var _news2093 = HashSet<Loc>();
    for (var _key2089 in value.file_private_functions) {
        var _kscratch2090 = base.scratch();
        _kscratch2090.loc(_key2089);
        var _vscratch2091 = base.scratch();
        var _had = base.entry("file_private_functions", _kscratch2090, _vscratch2091);
        if (_had >= 0) {
            _kept2092 += 1;
        }
        if (_had != 1) {
            _news2093.insert(_key2089);
        }
    }
    if (_kept2092 == base.size("file_private_functions")) {
        out.unsigned(1);
        var _keys2095 = Array<(u8[], u8[], Loc)>();
        for (var _key2094 in _news2093) {
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
        for (var _okey2099 in _news2093) {
            var _own2100 = RecordOut();
            _own2100.blank_bodies = true;
            _own2100.blank_locs = true;
            _own2100.pending_as_bytes = true;
            _own2100.loc(_okey2099);
            base.own_at("file_private_functions", _okey2099, interface_text(_own2100));
        }
    } else {
        out.unsigned(0);
        var _keys2102 = Array<(u8[], u8[], Loc)>();
        for (var _key2101 in value.file_private_functions) {
            var _scratch2103 = out.scratch();
            _scratch2103.loc(_key2101);
            var _vscratch2105 = out.scratch();
            _keys2102.append((_scratch2103.finish(), _vscratch2105.finish(), _key2101));
        }
        _keys2102.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2102.count);
        for (var (_bytes2104, _, _key2101) in _keys2102) {
            out.loc(_key2101);
        }
        for (var _okey2106 in value.file_private_functions) {
            var _own2107 = RecordOut();
            _own2107.blank_bodies = true;
            _own2107.blank_locs = true;
            _own2107.pending_as_bytes = true;
            _own2107.loc(_okey2106);
            base.own_at("file_private_functions", _okey2106, interface_text(_own2107));
        }
        base.count("file_private_functions whole", 0);
    }
    base.stat("file_private_functions", out.values.count - _mark);
    _mark = out.values.count;
    var _n2117 = base.size("call_targets");
    var _scratch2116 = base.scratch();
    if (value.call_targets.count >= _n2117) {
        for (var _i2118 in 0.._n2117) {
            var (_t2119, _t2120) = value.call_targets[_i2118];
            _scratch2116.loc(_t2119);
            _scratch2116.text(_t2120);
        }
    }
    if (value.call_targets.count >= _n2117 and base.same_list("call_targets", _scratch2116)) {
        out.unsigned(1);
        out.unsigned(_n2117);
        out.unsigned(value.call_targets.count - _n2117);
        for (var _i2118 in _n2117..value.call_targets.count) {
            var (_t2121, _t2122) = value.call_targets[_i2118];
            out.loc(_t2121);
            out.text(_t2122);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.call_targets.count);
        for (var _item2123 in value.call_targets) {
            var (_t2124, _t2125) = _item2123;
            out.loc(_t2124);
            out.text(_t2125);
        }
        base.count("call_targets whole", 0);
    }
    base.stat("call_targets", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2142 = 0;
    var _news2143 = Array<(Loc, String)>();
    for (var _item2140 in value.argument_names) {
        var _escratch2141 = base.scratch();
        var (_t2144, _t2145) = _item2140;
        _escratch2141.loc(_t2144);
        _escratch2141.text(_t2145);
        if (base.entry("argument_names", _escratch2141, base.scratch()) >= 0) {
            _kept2142 += 1;
        } else {
            _news2143.append(_item2140);
        }
    }
    if (_kept2142 == base.size("argument_names")) {
        out.unsigned(1);
        out.unsigned(_news2143.count);
        for (var _item2146 in _news2143) {
            var (_t2147, _t2148) = _item2146;
            out.loc(_t2147);
            out.text(_t2148);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.argument_names.count);
        for (var _item2149 in value.argument_names) {
            var (_t2150, _t2151) = _item2149;
            out.loc(_t2150);
            out.text(_t2151);
        }
        base.count("argument_names whole", 0);
    }
    base.stat("argument_names", out.values.count - _mark);
    _mark = out.values.count;
    var _n2166 = base.size("namespaces");
    var _scratch2165 = base.scratch();
    if (value.namespaces.count >= _n2166) {
        for (var _i2167 in 0.._n2166) {
            _scratch2165.text(value.namespaces[_i2167]);
        }
    }
    if (value.namespaces.count >= _n2166 and base.same_list("namespaces", _scratch2165)) {
        out.unsigned(1);
        out.unsigned(_n2166);
        out.unsigned(value.namespaces.count - _n2166);
        for (var _i2167 in _n2166..value.namespaces.count) {
            out.text(value.namespaces[_i2167]);
            {
                var _own2168 = RecordOut();
                _own2168.blank_bodies = true;
                _own2168.blank_locs = true;
                _own2168.pending_as_bytes = true;
                _own2168.text(value.namespaces[_i2167]);
                base.own("namespaces", interface_text(_own2168));
            }
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.namespaces.count);
        for (var _item2169 in value.namespaces) {
            out.text(_item2169);
        }
        for (var _i2167 in 0..value.namespaces.count) {
            {
                var _own2170 = RecordOut();
                _own2170.blank_bodies = true;
                _own2170.blank_locs = true;
                _own2170.pending_as_bytes = true;
                _own2170.text(value.namespaces[_i2167]);
                base.own("namespaces", interface_text(_own2170));
            }
        }
        base.count("namespaces whole", 0);
    }
    base.stat("namespaces", out.values.count - _mark);
    _mark = out.values.count;
    var _n2181 = base.size("cached_files");
    var _scratch2180 = base.scratch();
    if (value.cached_files.count >= _n2181) {
        for (var _i2182 in 0.._n2181) {
            _scratch2180.flag(value.cached_files[_i2182]);
        }
    }
    if (value.cached_files.count >= _n2181 and base.same_list("cached_files", _scratch2180)) {
        out.unsigned(1);
        out.unsigned(_n2181);
        out.unsigned(value.cached_files.count - _n2181);
        for (var _i2182 in _n2181..value.cached_files.count) {
            out.flag(value.cached_files[_i2182]);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.cached_files.count);
        for (var _item2183 in value.cached_files) {
            out.flag(_item2183);
        }
        base.count("cached_files whole", 0);
    }
    base.stat("cached_files", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2195 = 0;
    var _news2196 = HashMap<Loc, String>();
    for (var (_key2192, _) in value.recorded_summaries) {
        var _kscratch2193 = base.scratch();
        _kscratch2193.loc(_key2192);
        var _vscratch2194 = base.scratch();
        _vscratch2194.text(value.recorded_summaries[_key2192]);
        var _had = base.entry("recorded_summaries", _kscratch2193, _vscratch2194);
        if (_had >= 0) {
            _kept2195 += 1;
        }
        if (_had != 1) {
            _news2196[_key2192] = value.recorded_summaries[_key2192];
        }
    }
    if (_kept2195 == base.size("recorded_summaries")) {
        out.unsigned(1);
        var _keys2198 = Array<(u8[], u8[], Loc)>();
        for (var (_key2197, _) in _news2196) {
            var _scratch2199 = out.scratch();
            _scratch2199.loc(_key2197);
            var _vscratch2201 = out.scratch();
            _vscratch2201.text(_news2196[_key2197]);
            _keys2198.append((_scratch2199.finish(), _vscratch2201.finish(), _key2197));
        }
        _keys2198.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2198.count);
        for (var (_bytes2200, _, _key2197) in _keys2198) {
            out.loc(_key2197);
            out.text(_news2196[_key2197]);
        }
    } else {
        out.unsigned(0);
        var _keys2203 = Array<(u8[], u8[], Loc)>();
        for (var (_key2202, _) in value.recorded_summaries) {
            var _scratch2204 = out.scratch();
            _scratch2204.loc(_key2202);
            var _vscratch2206 = out.scratch();
            _vscratch2206.text(value.recorded_summaries[_key2202]);
            _keys2203.append((_scratch2204.finish(), _vscratch2206.finish(), _key2202));
        }
        _keys2203.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2203.count);
        for (var (_bytes2205, _, _key2202) in _keys2203) {
            out.loc(_key2202);
            out.text(value.recorded_summaries[_key2202]);
        }
        base.count("recorded_summaries whole", 0);
    }
    base.stat("recorded_summaries", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2219 = 0;
    var _news2220 = HashSet<Loc>();
    for (var _key2216 in value.stripped) {
        var _kscratch2217 = base.scratch();
        _kscratch2217.loc(_key2216);
        var _vscratch2218 = base.scratch();
        var _had = base.entry("stripped", _kscratch2217, _vscratch2218);
        if (_had >= 0) {
            _kept2219 += 1;
        }
        if (_had != 1) {
            _news2220.insert(_key2216);
        }
    }
    if (_kept2219 == base.size("stripped")) {
        out.unsigned(1);
        var _keys2222 = Array<(u8[], u8[], Loc)>();
        for (var _key2221 in _news2220) {
            var _scratch2223 = out.scratch();
            _scratch2223.loc(_key2221);
            var _vscratch2225 = out.scratch();
            _keys2222.append((_scratch2223.finish(), _vscratch2225.finish(), _key2221));
        }
        _keys2222.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2222.count);
        for (var (_bytes2224, _, _key2221) in _keys2222) {
            out.loc(_key2221);
        }
    } else {
        out.unsigned(0);
        var _keys2227 = Array<(u8[], u8[], Loc)>();
        for (var _key2226 in value.stripped) {
            var _scratch2228 = out.scratch();
            _scratch2228.loc(_key2226);
            var _vscratch2230 = out.scratch();
            _keys2227.append((_scratch2228.finish(), _vscratch2230.finish(), _key2226));
        }
        _keys2227.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2227.count);
        for (var (_bytes2229, _, _key2226) in _keys2227) {
            out.loc(_key2226);
        }
        base.count("stripped whole", 0);
    }
    base.stat("stripped", out.values.count - _mark);
    _mark = out.values.count;
    out.flag(value.templates.frozen);
    var _seq2240 = base.ref_templates;
    ulong _bj2241 = 0;
    var _news2243 = Array<ulong>();
    var _patches2244 = Array<(ulong, ulong)>();
    for (var _i2245 in 0..value.templates.structs.count) {
        if (_bj2241 < _seq2240.count
            and value.templates.structs[_i2245] === _seq2240[_bj2241]
            and !value.extended_checked.contains(value.templates.structs[_i2245].name)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_StructDef_write(scratch, value.templates.structs[_i2245]);
                base.verify_same("t", _bj2241, scratch, value.templates.structs[_i2245].name);
            }
            _bj2241 += 1;
        } else if (_bj2241 < _seq2240.count
            and !(value.templates.structs[_i2245] === _seq2240[_bj2241])
            and _same_m_StructDef(value.templates.structs[_i2245], _seq2240[_bj2241], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_StructDef_write(scratch, value.templates.structs[_i2245]);
                base.verify_same("t", _bj2241, scratch, value.templates.structs[_i2245].name);
            }
            _bj2241 += 1;
        } else if (_bj2241 < _seq2240.count and value.templates.structs[_i2245].name == _seq2240[_bj2241].name) {
            _patches2244.append((_i2245, _bj2241));
            _bj2241 += 1;
        } else {
            _news2243.append(_i2245);
        }
    }
    if (_bj2241 == _seq2240.count) {
        out.unsigned(2);
        out.unsigned(_patches2244.count);
        for (var (_i2245, _b) in _patches2244) {
            ulong _before = out.values.count;
            out.text(value.templates.structs[_i2245].name);
            out.unsigned(_b);
            _patch_t_write(out, value.templates.structs[_i2245], base, _b);
            base.count("t patched", out.values.count - _before);
            {
                var _own2246 = RecordOut();
                _own2246.blank_bodies = false;
                _own2246.blank_locs = true;
                _own2246.pending_as_bytes = true;
                _m_StructDef_write(_own2246, value.templates.structs[_i2245]);
                base.own("templates structs", interface_text(_own2246));
            }
        }
        out.unsigned(_news2243.count);
        for (var _i2245 in _news2243) {
            ulong _before = out.values.count;
            out.unsigned(_i2245);
            _m_StructDef_write(out, value.templates.structs[_i2245]);
            base.count("t new", out.values.count - _before);
            {
                var _own2247 = RecordOut();
                _own2247.blank_bodies = false;
                _own2247.blank_locs = true;
                _own2247.pending_as_bytes = true;
                _m_StructDef_write(_own2247, value.templates.structs[_i2245]);
                base.own("templates structs", interface_text(_own2247));
            }
        }
        base.count("t merged", 0);
    } else {
        out.unsigned(1);
        base.count("t by place", 0);
        var _struct_hits2239 = HashSet<long>();
        var _slots2242 = HashMap<String, long>();
        for (var _i2245 in 0.._seq2240.count) {
            if (!_slots2242.contains(_seq2240[_i2245].name)) {
                _slots2242[_seq2240[_i2245].name] = _i2245 as long;
            }
        }
        out.unsigned(value.templates.structs.count);
        for (var _i2245 in 0..value.templates.structs.count) {
            var _item2238 = value.templates.structs[_i2245];
            var _slot = _slots2242.try_get(_item2238.name);
            long named = _slot.is_value() ? _slot.value() : -1;
            long at = -1;
            if (named >= 0
                and _seq2240[named as ulong] === _item2238
                and !value.extended_checked.contains(_item2238.name)) {
                at = named;
            }
            ulong _before = out.values.count;
            if (at >= 0) {
                _struct_hits2239.insert(at);
                out.unsigned((at as ulong) * 2 + 1);
            } else if (named >= 0) {
                _struct_hits2239.insert(named);
                out.unsigned(2);
                out.unsigned(named as ulong);
                _patch_t_write(out, _item2238, base, named as ulong);
                base.count("t patched", out.values.count - _before);
            } else {
                out.unsigned(0);
                _m_StructDef_write(out, _item2238);
                base.count("t new", out.values.count - _before);
            }
        }
        base.missed("t", "t", _struct_hits2239.count);
    }
    var _seq2261 = base.ref_template_functions;
    ulong _bj2262 = 0;
    var _news2263 = Array<ulong>();
    var _changed2257 = Array<(ulong, ulong)>();
    for (var _i2264 in 0..value.templates.functions.count) {
        if (_bj2262 < _seq2261.count and value.templates.functions[_i2264] === _seq2261[_bj2262]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.templates.functions[_i2264]);
                base.verify_same("tf", _bj2262, scratch);
            }
            _bj2262 += 1;
        } else if (_bj2262 < _seq2261.count
            and _same_m_FunctionDef(value.templates.functions[_i2264], _seq2261[_bj2262], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.templates.functions[_i2264]);
                base.verify_same("tf", _bj2262, scratch);
            }
            _bj2262 += 1;
        } else if (_bj2262 < _seq2261.count and value.templates.functions[_i2264].name == _seq2261[_bj2262].name) {
            _changed2257.append((_i2264, _bj2262));
            _bj2262 += 1;
        } else {
            _news2263.append(_i2264);
        }
    }
    if (_bj2262 == _seq2261.count) {
        out.unsigned(2);
        out.unsigned(_changed2257.count);
        for (var (_i2264, _b) in _changed2257) {
            out.text(value.templates.functions[_i2264].name);
            out.unsigned(_b);
            _m_FunctionDef_write(out, value.templates.functions[_i2264]);
            {
                var _own2265 = RecordOut();
                _own2265.blank_bodies = false;
                _own2265.blank_locs = true;
                _own2265.pending_as_bytes = true;
                _m_FunctionDef_write(_own2265, value.templates.functions[_i2264]);
                base.own("templates functions", interface_text(_own2265));
            }
        }
        base.count("tf" + " changed", _changed2257.count);
        out.unsigned(_news2263.count);
        for (var _i2264 in _news2263) {
            out.unsigned(_i2264);
            _m_FunctionDef_write(out, value.templates.functions[_i2264]);
            {
                var _own2266 = RecordOut();
                _own2266.blank_bodies = false;
                _own2266.blank_locs = true;
                _own2266.pending_as_bytes = true;
                _m_FunctionDef_write(_own2266, value.templates.functions[_i2264]);
                base.own("templates functions", interface_text(_own2266));
            }
        }
        base.count("tf" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("tf" + " whole", 0);
        out.unsigned(value.templates.functions.count);
        for (var _i2264 in 0..value.templates.functions.count) {
            _m_FunctionDef_write(out, value.templates.functions[_i2264]);
            {
                var _own2267 = RecordOut();
                _own2267.blank_bodies = false;
                _own2267.blank_locs = true;
                _own2267.pending_as_bytes = true;
                _m_FunctionDef_write(_own2267, value.templates.functions[_i2264]);
                base.own("templates functions", interface_text(_own2267));
            }
        }
    }
    base.stat("templates", out.values.count - _mark);
    _mark = out.values.count;
    base.write_checked(out, value.checked);
    base.stat("checked", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2280 = 0;
    var _news2281 = HashMap<String, SpecRequest>();
    for (var (_key2277, _) in value.spec_requests) {
        var _kscratch2278 = base.scratch();
        _kscratch2278.text(_key2277);
        var _vscratch2279 = base.scratch();
        _m_SpecRequest_write(_vscratch2279, value.spec_requests[_key2277]);
        var _had = base.entry("spec_requests", _kscratch2278, _vscratch2279);
        if (_had >= 0) {
            _kept2280 += 1;
        }
        if (_had != 1) {
            _news2281[_key2277] = value.spec_requests[_key2277];
        }
    }
    if (_kept2280 == base.size("spec_requests")) {
        out.unsigned(1);
        var _keys2283 = Array<(u8[], u8[], String)>();
        for (var (_key2282, _) in _news2281) {
            var _scratch2284 = out.scratch();
            _scratch2284.text(_key2282);
            var _vscratch2286 = out.scratch();
            _m_SpecRequest_write(_vscratch2286, _news2281[_key2282]);
            _keys2283.append((_scratch2284.finish(), _vscratch2286.finish(), _key2282));
        }
        _keys2283.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2283.count);
        for (var (_bytes2285, _, _key2282) in _keys2283) {
            out.text(_key2282);
            _m_SpecRequest_write(out, _news2281[_key2282]);
        }
        for (var (_okey2287, _) in _news2281) {
            var _own2288 = RecordOut();
            _own2288.blank_bodies = true;
            _own2288.blank_locs = true;
            _own2288.pending_as_bytes = true;
            _own2288.text(_okey2287);
            _m_SpecRequest_write(_own2288, _news2281[_okey2287]);
            base.own("spec_requests", interface_text(_own2288));
        }
    } else {
        out.unsigned(0);
        var _keys2290 = Array<(u8[], u8[], String)>();
        for (var (_key2289, _) in value.spec_requests) {
            var _scratch2291 = out.scratch();
            _scratch2291.text(_key2289);
            var _vscratch2293 = out.scratch();
            _m_SpecRequest_write(_vscratch2293, value.spec_requests[_key2289]);
            _keys2290.append((_scratch2291.finish(), _vscratch2293.finish(), _key2289));
        }
        _keys2290.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2290.count);
        for (var (_bytes2292, _, _key2289) in _keys2290) {
            out.text(_key2289);
            _m_SpecRequest_write(out, value.spec_requests[_key2289]);
        }
        for (var (_okey2294, _) in value.spec_requests) {
            var _own2295 = RecordOut();
            _own2295.blank_bodies = true;
            _own2295.blank_locs = true;
            _own2295.pending_as_bytes = true;
            _own2295.text(_okey2294);
            _m_SpecRequest_write(_own2295, value.spec_requests[_okey2294]);
            base.own("spec_requests", interface_text(_own2295));
        }
        base.count("spec_requests whole", 0);
    }
    base.stat("spec_requests", out.values.count - _mark);
    _mark = out.values.count;
    out.flag(value.record_summaries);
    base.stat("record_summaries", out.values.count - _mark);
    _mark = out.values.count;
    var _n2308 = base.size("summaries_to_record");
    var _scratch2307 = base.scratch();
    if (value.summaries_to_record.count >= _n2308) {
        for (var _i2309 in 0.._n2308) {
            var (_t2310, _t2311) = value.summaries_to_record[_i2309];
            _scratch2307.loc(_t2310);
            _scratch2307.text(_t2311);
        }
    }
    if (value.summaries_to_record.count >= _n2308 and base.same_list("summaries_to_record", _scratch2307)) {
        out.unsigned(1);
        out.unsigned(_n2308);
        out.unsigned(value.summaries_to_record.count - _n2308);
        for (var _i2309 in _n2308..value.summaries_to_record.count) {
            var (_t2312, _t2313) = value.summaries_to_record[_i2309];
            out.loc(_t2312);
            out.text(_t2313);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.summaries_to_record.count);
        for (var _item2314 in value.summaries_to_record) {
            var (_t2315, _t2316) = _item2314;
            out.loc(_t2315);
            out.text(_t2316);
        }
        base.count("summaries_to_record whole", 0);
    }
    base.stat("summaries_to_record", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2334 = 0;
    var _news2335 = HashMap<String, Array<bool>>();
    for (var (_key2331, _) in value.caller_copies) {
        var _kscratch2332 = base.scratch();
        _kscratch2332.text(_key2331);
        var _vscratch2333 = base.scratch();
        _vscratch2333.unsigned(value.caller_copies[_key2331].count);
        for (var _item2336 in value.caller_copies[_key2331]) {
            _vscratch2333.flag(_item2336);
        }
        var _had = base.entry("caller_copies", _kscratch2332, _vscratch2333);
        if (_had >= 0) {
            _kept2334 += 1;
        }
        if (_had != 1) {
            _news2335[_key2331] = value.caller_copies[_key2331];
        }
    }
    if (_kept2334 == base.size("caller_copies")) {
        out.unsigned(1);
        var _keys2338 = Array<(u8[], u8[], String)>();
        for (var (_key2337, _) in _news2335) {
            var _scratch2339 = out.scratch();
            _scratch2339.text(_key2337);
            var _vscratch2341 = out.scratch();
            _vscratch2341.unsigned(_news2335[_key2337].count);
            for (var _item2342 in _news2335[_key2337]) {
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
            out.unsigned(_news2335[_key2337].count);
            for (var _item2343 in _news2335[_key2337]) {
                out.flag(_item2343);
            }
        }
        for (var (_okey2344, _) in _news2335) {
            var _own2345 = RecordOut();
            _own2345.blank_bodies = true;
            _own2345.blank_locs = true;
            _own2345.pending_as_bytes = true;
            _own2345.text(_okey2344);
            _own2345.unsigned(_news2335[_okey2344].count);
            for (var _item2346 in _news2335[_okey2344]) {
                _own2345.flag(_item2346);
            }
            base.own("caller_copies", interface_text(_own2345));
        }
    } else {
        out.unsigned(0);
        var _keys2348 = Array<(u8[], u8[], String)>();
        for (var (_key2347, _) in value.caller_copies) {
            var _scratch2349 = out.scratch();
            _scratch2349.text(_key2347);
            var _vscratch2351 = out.scratch();
            _vscratch2351.unsigned(value.caller_copies[_key2347].count);
            for (var _item2352 in value.caller_copies[_key2347]) {
                _vscratch2351.flag(_item2352);
            }
            _keys2348.append((_scratch2349.finish(), _vscratch2351.finish(), _key2347));
        }
        _keys2348.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2348.count);
        for (var (_bytes2350, _, _key2347) in _keys2348) {
            out.text(_key2347);
            out.unsigned(value.caller_copies[_key2347].count);
            for (var _item2353 in value.caller_copies[_key2347]) {
                out.flag(_item2353);
            }
        }
        for (var (_okey2354, _) in value.caller_copies) {
            var _own2355 = RecordOut();
            _own2355.blank_bodies = true;
            _own2355.blank_locs = true;
            _own2355.pending_as_bytes = true;
            _own2355.text(_okey2354);
            _own2355.unsigned(value.caller_copies[_okey2354].count);
            for (var _item2356 in value.caller_copies[_okey2354]) {
                _own2355.flag(_item2356);
            }
            base.own("caller_copies", interface_text(_own2355));
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
    var _f1503 = Array<ast.Import>();
    var _mode1506 = input.unsigned();
    if (_mode1506 == 2) {
        var _changed1492 = HashMap<ulong, ast.Import>();
        ulong _bi1507 = 0;
        var _n1504 = input.count();
        for (var _ in 0.._n1504) {
            var _at1508 = input.unsigned();
            while (_f1503.count < _at1508 or (input.merging and _bi1507 < base.imports.count)) {
                var _c = _changed1492.try_get(_bi1507);
                _f1503.append(_c.is_value() ? _c.value() : base.imports[_bi1507]);
                _bi1507 += 1;
            }
            _f1503.append(_a_Import_read(input));
        }
        while (_bi1507 < base.imports.count) {
            var _c = _changed1492.try_get(_bi1507);
            _f1503.append(_c.is_value() ? _c.value() : base.imports[_bi1507]);
            _bi1507 += 1;
        }
    } else if (_mode1506 == 3) {
        var _n1504 = input.count();
        for (var _ in 0.._n1504) {
            _f1503.append(_a_Import_read(input));
        }
    } else {
        var _n1504 = input.count();
        if (input.merging) {
            input.error = "imports" + " written by place";
        }
        for (var _ in 0.._n1504) {
            var _tag1505 = input.unsigned();
            if (_tag1505 & 1 == 1) {
                if (!input.merging) {
                    _f1503.append(base.imports[_tag1505 >> 1]);
                }
            } else {
                var _read = _a_Import_read(input);
                if (!input.merging or true) {
                    _f1503.append(_read);
                }
            }
        }
    }
    var _f1536 = Array<StructDef>();
    var _mode1539 = input.unsigned();
    if (_mode1539 == 2) {
        var _patched1542 = HashMap<ulong, StructDef>();
        var _n1537 = input.count();
        for (var _ in 0.._n1537) {
            var _name = input.text();
            var _slot = input.unsigned();
            if (input.merging) {
                _slot = struct_named(base.structs, _name);
            }
            if (_slot >= base.structs.count) {
                input.error = $"no struct {_name} to patch";
                break;
            }
            _patched1542[_slot] = _patch_s_read(input, base.structs[_slot]);
        }
        ulong _bi1540 = 0;
        var _added = input.count();
        for (var _ in 0.._added) {
            var _at1541 = input.unsigned();
            while (_f1536.count < _at1541 or (input.merging and _bi1540 < base.structs.count)) {
                var _p = _patched1542.try_get(_bi1540);
                _f1536.append(_p.is_value() ? _p.value() : base.structs[_bi1540]);
                _bi1540 += 1;
            }
            _f1536.append(_m_StructDef_read_lazy(input));
        }
        while (_bi1540 < base.structs.count) {
            var _p = _patched1542.try_get(_bi1540);
            _f1536.append(_p.is_value() ? _p.value() : base.structs[_bi1540]);
            _bi1540 += 1;
        }
    } else {
        if (input.merging) {
            input.error = "structs written by place";
        }
        var _n1537 = input.count();
        for (var _ in 0.._n1537) {
            var _tag1538 = input.unsigned();
            if (_tag1538 & 1 == 1) {
                _f1536.append(base.structs[(_tag1538 >> 1) < base.structs.count ? _tag1538 >> 1 : 0]);
            } else if (_tag1538 == 2) {
                var _was = base.structs[input.unsigned()];
                _f1536.append(_patch_s_read(input, _was));
            } else {
                _f1536.append(_m_StructDef_read_lazy(input));
            }
        }
    }
    var _f1556 = Array<TraitDef>();
    var _mode1559 = input.unsigned();
    if (_mode1559 == 2) {
        var _changed1545 = HashMap<ulong, TraitDef>();
        ulong _bi1560 = 0;
        var _n1557 = input.count();
        for (var _ in 0.._n1557) {
            var _at1561 = input.unsigned();
            while (_f1556.count < _at1561 or (input.merging and _bi1560 < base.traits.count)) {
                var _c = _changed1545.try_get(_bi1560);
                _f1556.append(_c.is_value() ? _c.value() : base.traits[_bi1560]);
                _bi1560 += 1;
            }
            _f1556.append(_m_TraitDef_read(input));
        }
        while (_bi1560 < base.traits.count) {
            var _c = _changed1545.try_get(_bi1560);
            _f1556.append(_c.is_value() ? _c.value() : base.traits[_bi1560]);
            _bi1560 += 1;
        }
    } else if (_mode1559 == 3) {
        var _n1557 = input.count();
        for (var _ in 0.._n1557) {
            _f1556.append(_m_TraitDef_read(input));
        }
    } else {
        var _n1557 = input.count();
        if (input.merging) {
            input.error = "traits" + " written by place";
        }
        for (var _ in 0.._n1557) {
            var _tag1558 = input.unsigned();
            if (_tag1558 & 1 == 1) {
                if (!input.merging) {
                    _f1556.append(base.traits[_tag1558 >> 1]);
                }
            } else {
                var _read = _m_TraitDef_read(input);
                if (!input.merging or true) {
                    _f1556.append(_read);
                }
            }
        }
    }
    var _f1575 = Array<ExtensionDef>();
    var _mode1578 = input.unsigned();
    if (_mode1578 == 2) {
        var _changed1564 = HashMap<ulong, ExtensionDef>();
        ulong _bi1579 = 0;
        var _n1576 = input.count();
        for (var _ in 0.._n1576) {
            var _at1580 = input.unsigned();
            while (_f1575.count < _at1580 or (input.merging and _bi1579 < base.extensions.count)) {
                var _c = _changed1564.try_get(_bi1579);
                _f1575.append(_c.is_value() ? _c.value() : base.extensions[_bi1579]);
                _bi1579 += 1;
            }
            _f1575.append(_m_ExtensionDef_read(input));
        }
        while (_bi1579 < base.extensions.count) {
            var _c = _changed1564.try_get(_bi1579);
            _f1575.append(_c.is_value() ? _c.value() : base.extensions[_bi1579]);
            _bi1579 += 1;
        }
    } else if (_mode1578 == 3) {
        var _n1576 = input.count();
        for (var _ in 0.._n1576) {
            _f1575.append(_m_ExtensionDef_read(input));
        }
    } else {
        var _n1576 = input.count();
        if (input.merging) {
            input.error = "extensions" + " written by place";
        }
        for (var _ in 0.._n1576) {
            var _tag1577 = input.unsigned();
            if (_tag1577 & 1 == 1) {
                if (!input.merging) {
                    _f1575.append(base.extensions[_tag1577 >> 1]);
                }
            } else {
                var _read = _m_ExtensionDef_read(input);
                if (!input.merging or true) {
                    _f1575.append(_read);
                }
            }
        }
    }
    var _f1594 = Array<FunctionDef>();
    var _mode1597 = input.unsigned();
    if (_mode1597 == 2) {
        var _changed1583 = HashMap<ulong, FunctionDef>();
        var _nc1585 = input.count();
        for (var _ in 0.._nc1585) {
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
                _changed1583[_slot] = _el;
            } else {
                input.error = $"no {_name} to change";
            }
        }
        ulong _bi1598 = 0;
        var _n1595 = input.count();
        for (var _ in 0.._n1595) {
            var _at1599 = input.unsigned();
            while (_f1594.count < _at1599 or (input.merging and _bi1598 < base.functions.count)) {
                var _c = _changed1583.try_get(_bi1598);
                _f1594.append(_c.is_value() ? _c.value() : base.functions[_bi1598]);
                _bi1598 += 1;
            }
            _f1594.append(_m_FunctionDef_read_lazy(input));
        }
        while (_bi1598 < base.functions.count) {
            var _c = _changed1583.try_get(_bi1598);
            _f1594.append(_c.is_value() ? _c.value() : base.functions[_bi1598]);
            _bi1598 += 1;
        }
    } else if (_mode1597 == 3) {
        var _n1595 = input.count();
        for (var _ in 0.._n1595) {
            _f1594.append(_m_FunctionDef_read_lazy(input));
        }
    } else {
        var _n1595 = input.count();
        if (input.merging) {
            input.error = "functions" + " written by place";
        }
        for (var _ in 0.._n1595) {
            var _tag1596 = input.unsigned();
            if (_tag1596 & 1 == 1) {
                if (!input.merging) {
                    _f1594.append(base.functions[_tag1596 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read_lazy(input);
                if (!input.merging or true) {
                    _f1594.append(_read);
                }
            }
        }
    }
    var _f1613 = Array<ExternDef>();
    var _mode1616 = input.unsigned();
    if (_mode1616 == 2) {
        var _changed1602 = HashMap<ulong, ExternDef>();
        ulong _bi1617 = 0;
        var _n1614 = input.count();
        for (var _ in 0.._n1614) {
            var _at1618 = input.unsigned();
            while (_f1613.count < _at1618 or (input.merging and _bi1617 < base.externs.count)) {
                var _c = _changed1602.try_get(_bi1617);
                _f1613.append(_c.is_value() ? _c.value() : base.externs[_bi1617]);
                _bi1617 += 1;
            }
            _f1613.append(_m_ExternDef_read(input));
        }
        while (_bi1617 < base.externs.count) {
            var _c = _changed1602.try_get(_bi1617);
            _f1613.append(_c.is_value() ? _c.value() : base.externs[_bi1617]);
            _bi1617 += 1;
        }
    } else if (_mode1616 == 3) {
        var _n1614 = input.count();
        for (var _ in 0.._n1614) {
            _f1613.append(_m_ExternDef_read(input));
        }
    } else {
        var _n1614 = input.count();
        if (input.merging) {
            input.error = "externs" + " written by place";
        }
        for (var _ in 0.._n1614) {
            var _tag1615 = input.unsigned();
            if (_tag1615 & 1 == 1) {
                if (!input.merging) {
                    _f1613.append(base.externs[_tag1615 >> 1]);
                }
            } else {
                var _read = _m_ExternDef_read(input);
                if (!input.merging or true) {
                    _f1613.append(_read);
                }
            }
        }
    }
    var _f1632 = Array<VariableDef>();
    var _mode1635 = input.unsigned();
    if (_mode1635 == 2) {
        var _changed1621 = HashMap<ulong, VariableDef>();
        ulong _bi1636 = 0;
        var _n1633 = input.count();
        for (var _ in 0.._n1633) {
            var _at1637 = input.unsigned();
            while (_f1632.count < _at1637 or (input.merging and _bi1636 < base.globals.count)) {
                var _c = _changed1621.try_get(_bi1636);
                _f1632.append(_c.is_value() ? _c.value() : base.globals[_bi1636]);
                _bi1636 += 1;
            }
            _f1632.append(_m_VariableDef_read(input));
        }
        while (_bi1636 < base.globals.count) {
            var _c = _changed1621.try_get(_bi1636);
            _f1632.append(_c.is_value() ? _c.value() : base.globals[_bi1636]);
            _bi1636 += 1;
        }
    } else if (_mode1635 == 3) {
        var _n1633 = input.count();
        for (var _ in 0.._n1633) {
            _f1632.append(_m_VariableDef_read(input));
        }
    } else {
        var _n1633 = input.count();
        if (input.merging) {
            input.error = "globals" + " written by place";
        }
        for (var _ in 0.._n1633) {
            var _tag1634 = input.unsigned();
            if (_tag1634 & 1 == 1) {
                if (!input.merging) {
                    _f1632.append(base.globals[_tag1634 >> 1]);
                }
            } else {
                var _read = _m_VariableDef_read(input);
                if (!input.merging or true) {
                    _f1632.append(_read);
                }
            }
        }
    }
    var _f1651 = Array<ModuleStaticBlock>();
    var _mode1654 = input.unsigned();
    if (_mode1654 == 2) {
        var _changed1640 = HashMap<ulong, ModuleStaticBlock>();
        ulong _bi1655 = 0;
        var _n1652 = input.count();
        for (var _ in 0.._n1652) {
            var _at1656 = input.unsigned();
            while (_f1651.count < _at1656 or (input.merging and _bi1655 < base.static_blocks.count)) {
                var _c = _changed1640.try_get(_bi1655);
                _f1651.append(_c.is_value() ? _c.value() : base.static_blocks[_bi1655]);
                _bi1655 += 1;
            }
            _f1651.append(_m_ModuleStaticBlock_read(input));
        }
        while (_bi1655 < base.static_blocks.count) {
            var _c = _changed1640.try_get(_bi1655);
            _f1651.append(_c.is_value() ? _c.value() : base.static_blocks[_bi1655]);
            _bi1655 += 1;
        }
    } else if (_mode1654 == 3) {
        var _n1652 = input.count();
        for (var _ in 0.._n1652) {
            _f1651.append(_m_ModuleStaticBlock_read(input));
        }
    } else {
        var _n1652 = input.count();
        if (input.merging) {
            input.error = "static_blocks" + " written by place";
        }
        for (var _ in 0.._n1652) {
            var _tag1653 = input.unsigned();
            if (_tag1653 & 1 == 1) {
                if (!input.merging) {
                    _f1651.append(base.static_blocks[_tag1653 >> 1]);
                }
            } else {
                var _read = _m_ModuleStaticBlock_read(input);
                if (!input.merging or true) {
                    _f1651.append(_read);
                }
            }
        }
    }
    var _f1670 = Array<EnumDef>();
    var _mode1673 = input.unsigned();
    if (_mode1673 == 2) {
        var _changed1659 = HashMap<ulong, EnumDef>();
        ulong _bi1674 = 0;
        var _n1671 = input.count();
        for (var _ in 0.._n1671) {
            var _at1675 = input.unsigned();
            while (_f1670.count < _at1675 or (input.merging and _bi1674 < base.enums.count)) {
                var _c = _changed1659.try_get(_bi1674);
                _f1670.append(_c.is_value() ? _c.value() : base.enums[_bi1674]);
                _bi1674 += 1;
            }
            _f1670.append(_m_EnumDef_read(input));
        }
        while (_bi1674 < base.enums.count) {
            var _c = _changed1659.try_get(_bi1674);
            _f1670.append(_c.is_value() ? _c.value() : base.enums[_bi1674]);
            _bi1674 += 1;
        }
    } else if (_mode1673 == 3) {
        var _n1671 = input.count();
        for (var _ in 0.._n1671) {
            _f1670.append(_m_EnumDef_read(input));
        }
    } else {
        var _n1671 = input.count();
        if (input.merging) {
            input.error = "enums" + " written by place";
        }
        for (var _ in 0.._n1671) {
            var _tag1672 = input.unsigned();
            if (_tag1672 & 1 == 1) {
                if (!input.merging) {
                    _f1670.append(base.enums[_tag1672 >> 1]);
                }
            } else {
                var _read = _m_EnumDef_read(input);
                if (!input.merging or true) {
                    _f1670.append(_read);
                }
            }
        }
    }
    var _f1689 = Array<TypeName>();
    var _mode1692 = input.unsigned();
    if (_mode1692 == 2) {
        var _changed1678 = HashMap<ulong, TypeName>();
        ulong _bi1693 = 0;
        var _n1690 = input.count();
        for (var _ in 0.._n1690) {
            var _at1694 = input.unsigned();
            while (_f1689.count < _at1694 or (input.merging and _bi1693 < base.struct_specs.count)) {
                var _c = _changed1678.try_get(_bi1693);
                _f1689.append(_c.is_value() ? _c.value() : base.struct_specs[_bi1693]);
                _bi1693 += 1;
            }
            _f1689.append(_m_TypeName_read(input));
        }
        while (_bi1693 < base.struct_specs.count) {
            var _c = _changed1678.try_get(_bi1693);
            _f1689.append(_c.is_value() ? _c.value() : base.struct_specs[_bi1693]);
            _bi1693 += 1;
        }
    } else if (_mode1692 == 3) {
        var _n1690 = input.count();
        for (var _ in 0.._n1690) {
            _f1689.append(_m_TypeName_read(input));
        }
    } else {
        var _n1690 = input.count();
        if (input.merging) {
            input.error = "struct_specs" + " written by place";
        }
        for (var _ in 0.._n1690) {
            var _tag1691 = input.unsigned();
            if (_tag1691 & 1 == 1) {
                if (!input.merging) {
                    _f1689.append(base.struct_specs[_tag1691 >> 1]);
                }
            } else {
                var _read = _m_TypeName_read(input);
                if (!input.merging or true) {
                    _f1689.append(_read);
                }
            }
        }
    }
    var _f1708 = Array<TypeName>();
    var _mode1711 = input.unsigned();
    if (_mode1711 == 2) {
        var _changed1697 = HashMap<ulong, TypeName>();
        ulong _bi1712 = 0;
        var _n1709 = input.count();
        for (var _ in 0.._n1709) {
            var _at1713 = input.unsigned();
            while (_f1708.count < _at1713 or (input.merging and _bi1712 < base.func_specs.count)) {
                var _c = _changed1697.try_get(_bi1712);
                _f1708.append(_c.is_value() ? _c.value() : base.func_specs[_bi1712]);
                _bi1712 += 1;
            }
            _f1708.append(_m_TypeName_read(input));
        }
        while (_bi1712 < base.func_specs.count) {
            var _c = _changed1697.try_get(_bi1712);
            _f1708.append(_c.is_value() ? _c.value() : base.func_specs[_bi1712]);
            _bi1712 += 1;
        }
    } else if (_mode1711 == 3) {
        var _n1709 = input.count();
        for (var _ in 0.._n1709) {
            _f1708.append(_m_TypeName_read(input));
        }
    } else {
        var _n1709 = input.count();
        if (input.merging) {
            input.error = "func_specs" + " written by place";
        }
        for (var _ in 0.._n1709) {
            var _tag1710 = input.unsigned();
            if (_tag1710 & 1 == 1) {
                if (!input.merging) {
                    _f1708.append(base.func_specs[_tag1710 >> 1]);
                }
            } else {
                var _read = _m_TypeName_read(input);
                if (!input.merging or true) {
                    _f1708.append(_read);
                }
            }
        }
    }
    var _f1720 = Array<TypeAliasDef>();
    var _n1721 = input.count();
    if (input.merging) {
        for (var _b in base.type_aliases) {
            _f1720.append(_b);
        }
    }
    for (var _ in 0.._n1721) {
        var _tag1722 = input.unsigned();
        if (_tag1722 & 1 == 1) {
            if (!input.merging) {
                _f1720.append(base.type_aliases[_tag1722 >> 1]);
            }
        } else {
            var _read = _m_TypeAliasDef_read(input);
            if (!input.merging or false) {
                _f1720.append(_read);
            }
        }
    }
    var _f1736 = Array<Withheld>();
    var _mode1739 = input.unsigned();
    if (_mode1739 == 2) {
        var _changed1725 = HashMap<ulong, Withheld>();
        ulong _bi1740 = 0;
        var _n1737 = input.count();
        for (var _ in 0.._n1737) {
            var _at1741 = input.unsigned();
            while (_f1736.count < _at1741 or (input.merging and _bi1740 < base.withheld.count)) {
                var _c = _changed1725.try_get(_bi1740);
                _f1736.append(_c.is_value() ? _c.value() : base.withheld[_bi1740]);
                _bi1740 += 1;
            }
            _f1736.append(_m_Withheld_read(input));
        }
        while (_bi1740 < base.withheld.count) {
            var _c = _changed1725.try_get(_bi1740);
            _f1736.append(_c.is_value() ? _c.value() : base.withheld[_bi1740]);
            _bi1740 += 1;
        }
    } else if (_mode1739 == 3) {
        var _n1737 = input.count();
        for (var _ in 0.._n1737) {
            _f1736.append(_m_Withheld_read(input));
        }
    } else {
        var _n1737 = input.count();
        if (input.merging) {
            input.error = "withheld" + " written by place";
        }
        for (var _ in 0.._n1737) {
            var _tag1738 = input.unsigned();
            if (_tag1738 & 1 == 1) {
                if (!input.merging) {
                    _f1736.append(base.withheld[_tag1738 >> 1]);
                }
            } else {
                var _read = _m_Withheld_read(input);
                if (!input.merging or true) {
                    _f1736.append(_read);
                }
            }
        }
    }
    var _f1755 = Array<PropertyDef>();
    var _mode1758 = input.unsigned();
    if (_mode1758 == 2) {
        var _changed1744 = HashMap<ulong, PropertyDef>();
        ulong _bi1759 = 0;
        var _n1756 = input.count();
        for (var _ in 0.._n1756) {
            var _at1760 = input.unsigned();
            while (_f1755.count < _at1760 or (input.merging and _bi1759 < base.properties.count)) {
                var _c = _changed1744.try_get(_bi1759);
                _f1755.append(_c.is_value() ? _c.value() : base.properties[_bi1759]);
                _bi1759 += 1;
            }
            _f1755.append(_m_PropertyDef_read(input));
        }
        while (_bi1759 < base.properties.count) {
            var _c = _changed1744.try_get(_bi1759);
            _f1755.append(_c.is_value() ? _c.value() : base.properties[_bi1759]);
            _bi1759 += 1;
        }
    } else if (_mode1758 == 3) {
        var _n1756 = input.count();
        for (var _ in 0.._n1756) {
            _f1755.append(_m_PropertyDef_read(input));
        }
    } else {
        var _n1756 = input.count();
        if (input.merging) {
            input.error = "properties" + " written by place";
        }
        for (var _ in 0.._n1756) {
            var _tag1757 = input.unsigned();
            if (_tag1757 & 1 == 1) {
                if (!input.merging) {
                    _f1755.append(base.properties[_tag1757 >> 1]);
                }
            } else {
                var _read = _m_PropertyDef_read(input);
                if (!input.merging or true) {
                    _f1755.append(_read);
                }
            }
        }
    }
    var _f1774 = Array<TypeUse>();
    var _mode1777 = input.unsigned();
    if (_mode1777 == 2) {
        var _changed1763 = HashMap<ulong, TypeUse>();
        ulong _bi1778 = 0;
        var _n1775 = input.count();
        for (var _ in 0.._n1775) {
            var _at1779 = input.unsigned();
            while (_f1774.count < _at1779 or (input.merging and _bi1778 < base.type_uses.count)) {
                var _c = _changed1763.try_get(_bi1778);
                _f1774.append(_c.is_value() ? _c.value() : base.type_uses[_bi1778]);
                _bi1778 += 1;
            }
            _f1774.append(_m_TypeUse_read(input));
        }
        while (_bi1778 < base.type_uses.count) {
            var _c = _changed1763.try_get(_bi1778);
            _f1774.append(_c.is_value() ? _c.value() : base.type_uses[_bi1778]);
            _bi1778 += 1;
        }
    } else if (_mode1777 == 3) {
        var _n1775 = input.count();
        for (var _ in 0.._n1775) {
            _f1774.append(_m_TypeUse_read(input));
        }
    } else {
        var _n1775 = input.count();
        if (input.merging) {
            input.error = "type_uses" + " written by place";
        }
        for (var _ in 0.._n1775) {
            var _tag1776 = input.unsigned();
            if (_tag1776 & 1 == 1) {
                if (!input.merging) {
                    _f1774.append(base.type_uses[_tag1776 >> 1]);
                }
            } else {
                var _read = _m_TypeUse_read(input);
                if (!input.merging or true) {
                    _f1774.append(_read);
                }
            }
        }
    }
    var _f1793 = Array<UseContext>();
    var _mode1796 = input.unsigned();
    if (_mode1796 == 2) {
        var _changed1782 = HashMap<ulong, UseContext>();
        ulong _bi1797 = 0;
        var _n1794 = input.count();
        for (var _ in 0.._n1794) {
            var _at1798 = input.unsigned();
            while (_f1793.count < _at1798 or (input.merging and _bi1797 < base.use_contexts.count)) {
                var _c = _changed1782.try_get(_bi1797);
                _f1793.append(_c.is_value() ? _c.value() : base.use_contexts[_bi1797]);
                _bi1797 += 1;
            }
            _f1793.append(_m_UseContext_read(input));
        }
        while (_bi1797 < base.use_contexts.count) {
            var _c = _changed1782.try_get(_bi1797);
            _f1793.append(_c.is_value() ? _c.value() : base.use_contexts[_bi1797]);
            _bi1797 += 1;
        }
    } else if (_mode1796 == 3) {
        var _n1794 = input.count();
        for (var _ in 0.._n1794) {
            _f1793.append(_m_UseContext_read(input));
        }
    } else {
        var _n1794 = input.count();
        if (input.merging) {
            input.error = "use_contexts" + " written by place";
        }
        for (var _ in 0.._n1794) {
            var _tag1795 = input.unsigned();
            if (_tag1795 & 1 == 1) {
                if (!input.merging) {
                    _f1793.append(base.use_contexts[_tag1795 >> 1]);
                }
            } else {
                var _read = _m_UseContext_read(input);
                if (!input.merging or true) {
                    _f1793.append(_read);
                }
            }
        }
    }
    var _f1814 = Array<(Loc, ulong, Loc)>();
    var _tag1815 = input.unsigned();
    if (_tag1815 == 1) {
        input.unsigned();
        for (var _i1803 in 0..base.literal_args.count) {
            _f1814.append(base.literal_args[_i1803]);
        }
        var _more1817 = input.count();
        for (var _ in 0.._more1817) {
            var _t1818 = input.loc();
            var _t1819 = input.unsigned();
            var _t1820 = input.loc();
            _f1814.append((_t1818, _t1819, _t1820));
        }
    } else {
        var _v1821 = Array<(Loc, ulong, Loc)>();
        var _n1822 = input.count();
        for (var _ in 0.._n1822) {
            var _t1823 = input.loc();
            var _t1824 = input.unsigned();
            var _t1825 = input.loc();
            _v1821.append((_t1823, _t1824, _t1825));
        }
        _f1814 = _v1821;
    }
    var _f1843 = Array<TypeAliasDef>();
    var _mode1846 = input.unsigned();
    if (_mode1846 == 2) {
        var _changed1832 = HashMap<ulong, TypeAliasDef>();
        ulong _bi1847 = 0;
        var _n1844 = input.count();
        for (var _ in 0.._n1844) {
            var _at1848 = input.unsigned();
            while (_f1843.count < _at1848 or (input.merging and _bi1847 < base.constrained_aliases.count)) {
                var _c = _changed1832.try_get(_bi1847);
                _f1843.append(_c.is_value() ? _c.value() : base.constrained_aliases[_bi1847]);
                _bi1847 += 1;
            }
            _f1843.append(_m_TypeAliasDef_read(input));
        }
        while (_bi1847 < base.constrained_aliases.count) {
            var _c = _changed1832.try_get(_bi1847);
            _f1843.append(_c.is_value() ? _c.value() : base.constrained_aliases[_bi1847]);
            _bi1847 += 1;
        }
    } else if (_mode1846 == 3) {
        var _n1844 = input.count();
        for (var _ in 0.._n1844) {
            _f1843.append(_m_TypeAliasDef_read(input));
        }
    } else {
        var _n1844 = input.count();
        if (input.merging) {
            input.error = "constrained_aliases" + " written by place";
        }
        for (var _ in 0.._n1844) {
            var _tag1845 = input.unsigned();
            if (_tag1845 & 1 == 1) {
                if (!input.merging) {
                    _f1843.append(base.constrained_aliases[_tag1845 >> 1]);
                }
            } else {
                var _read = _m_TypeAliasDef_read(input);
                if (!input.merging or true) {
                    _f1843.append(_read);
                }
            }
        }
    }
    var _f1862 = Array<TraitType>();
    var _mode1865 = input.unsigned();
    if (_mode1865 == 2) {
        var _changed1851 = HashMap<ulong, TraitType>();
        ulong _bi1866 = 0;
        var _n1863 = input.count();
        for (var _ in 0.._n1863) {
            var _at1867 = input.unsigned();
            while (_f1862.count < _at1867 or (input.merging and _bi1866 < base.trait_types.count)) {
                var _c = _changed1851.try_get(_bi1866);
                _f1862.append(_c.is_value() ? _c.value() : base.trait_types[_bi1866]);
                _bi1866 += 1;
            }
            _f1862.append(_m_TraitType_read(input));
        }
        while (_bi1866 < base.trait_types.count) {
            var _c = _changed1851.try_get(_bi1866);
            _f1862.append(_c.is_value() ? _c.value() : base.trait_types[_bi1866]);
            _bi1866 += 1;
        }
    } else if (_mode1865 == 3) {
        var _n1863 = input.count();
        for (var _ in 0.._n1863) {
            _f1862.append(_m_TraitType_read(input));
        }
    } else {
        var _n1863 = input.count();
        if (input.merging) {
            input.error = "trait_types" + " written by place";
        }
        for (var _ in 0.._n1863) {
            var _tag1864 = input.unsigned();
            if (_tag1864 & 1 == 1) {
                if (!input.merging) {
                    _f1862.append(base.trait_types[_tag1864 >> 1]);
                }
            } else {
                var _read = _m_TraitType_read(input);
                if (!input.merging or true) {
                    _f1862.append(_read);
                }
            }
        }
    }
    var _v1873 = Array<Conversion>();
    var _n1874 = input.count();
    for (var _ in 0.._n1874) {
        _v1873.append(_m_Conversion_read(input));
    }
    var _f1875 = _v1873;
    var _f1902 = Map<String, Array<String>>();
    var _tag1903 = input.unsigned();
    if (_tag1903 == 1) {
        for (var (_bk1904, _bv) in base.overload_sets) {
            _f1902[_bk1904] = _bv;
        }
        var _v1905 = Map<String, Array<String>>();
        var _n1906 = input.count();
        for (var _ in 0.._n1906) {
            var _k1907 = input.text();
            var _v1908 = Array<String>();
            var _n1909 = input.count();
            for (var _ in 0.._n1909) {
                _v1908.append(input.text());
            }
            _v1905[_k1907] = _v1908;
        }
        for (var (_bk1904, _av) in _v1905) {
            _f1902[_bk1904] = _av;
        }
    } else {
        var _v1910 = Map<String, Array<String>>();
        var _n1911 = input.count();
        for (var _ in 0.._n1911) {
            var _k1912 = input.text();
            var _v1913 = Array<String>();
            var _n1914 = input.count();
            for (var _ in 0.._n1914) {
                _v1913.append(input.text());
            }
            _v1910[_k1912] = _v1913;
        }
        _f1902 = _v1910;
    }
    var _f1949 = Map<String, Array<Array<String>>>();
    var _tag1950 = input.unsigned();
    if (_tag1950 == 1) {
        for (var (_bk1951, _bv) in base.overload_unions) {
            _f1949[_bk1951] = _bv;
        }
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
        for (var (_bk1951, _av) in _v1952) {
            _f1949[_bk1951] = _av;
        }
    } else {
        var _v1959 = Map<String, Array<Array<String>>>();
        var _n1960 = input.count();
        for (var _ in 0.._n1960) {
            var _k1961 = input.text();
            var _v1962 = Array<Array<String>>();
            var _n1963 = input.count();
            for (var _ in 0.._n1963) {
                var _v1964 = Array<String>();
                var _n1965 = input.count();
                for (var _ in 0.._n1965) {
                    _v1964.append(input.text());
                }
                _v1962.append(_v1964);
            }
            _v1959[_k1961] = _v1962;
        }
        _f1949 = _v1959;
    }
    var _f2036 = Map<String, Map<String, Array<String>>>();
    var _tag2037 = input.unsigned();
    if (_tag2037 == 1) {
        for (var (_bk2038, _bv) in base.method_overload_sets) {
            _f2036[_bk2038] = _bv;
        }
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
        for (var (_bk2038, _av) in _v2039) {
            _f2036[_bk2038] = _av;
        }
    } else {
        var _v2047 = Map<String, Map<String, Array<String>>>();
        var _n2048 = input.count();
        for (var _ in 0.._n2048) {
            var _k2049 = input.text();
            var _v2050 = Map<String, Array<String>>();
            var _n2051 = input.count();
            for (var _ in 0.._n2051) {
                var _k2052 = input.text();
                var _v2053 = Array<String>();
                var _n2054 = input.count();
                for (var _ in 0.._n2054) {
                    _v2053.append(input.text());
                }
                _v2050[_k2052] = _v2053;
            }
            _v2047[_k2049] = _v2050;
        }
        _f2036 = _v2047;
    }
    var _f2062 = _m_ExtensionScopes_read(input);
    var _f2082 = HashSet<Loc>();
    var _tag2083 = input.unsigned();
    if (_tag2083 == 1) {
        for (var _bk2084 in base.private_functions) {
            _f2082.insert(_bk2084);
        }
        var _v2085 = HashSet<Loc>();
        var _n2086 = input.count();
        for (var _ in 0.._n2086) {
            _v2085.insert(input.loc());
        }
        for (var _bk2084 in _v2085) {
            _f2082.insert(_bk2084);
        }
    } else {
        var _v2087 = HashSet<Loc>();
        var _n2088 = input.count();
        for (var _ in 0.._n2088) {
            _v2087.insert(input.loc());
        }
        _f2082 = _v2087;
    }
    var _f2108 = HashSet<Loc>();
    var _tag2109 = input.unsigned();
    if (_tag2109 == 1) {
        for (var _bk2110 in base.file_private_functions) {
            _f2108.insert(_bk2110);
        }
        var _v2111 = HashSet<Loc>();
        var _n2112 = input.count();
        for (var _ in 0.._n2112) {
            _v2111.insert(input.loc());
        }
        for (var _bk2110 in _v2111) {
            _f2108.insert(_bk2110);
        }
    } else {
        var _v2113 = HashSet<Loc>();
        var _n2114 = input.count();
        for (var _ in 0.._n2114) {
            _v2113.insert(input.loc());
        }
        _f2108 = _v2113;
    }
    var _f2126 = Array<(Loc, String)>();
    var _tag2127 = input.unsigned();
    if (_tag2127 == 1) {
        input.unsigned();
        for (var _i2118 in 0..base.call_targets.count) {
            _f2126.append(base.call_targets[_i2118]);
        }
        var _more2129 = input.count();
        for (var _ in 0.._more2129) {
            var _t2130 = input.loc();
            var _t2131 = input.text();
            _f2126.append((_t2130, _t2131));
        }
    } else {
        var _v2132 = Array<(Loc, String)>();
        var _n2133 = input.count();
        for (var _ in 0.._n2133) {
            var _t2134 = input.loc();
            var _t2135 = input.text();
            _v2132.append((_t2134, _t2135));
        }
        _f2126 = _v2132;
    }
    var _f2152 = Array<(Loc, String)>();
    var _tag2153 = input.unsigned();
    if (_tag2153 == 1) {
        var _v2154 = Array<(Loc, String)>();
        var _n2155 = input.count();
        for (var _ in 0.._n2155) {
            var _t2156 = input.loc();
            var _t2157 = input.text();
            _v2154.append((_t2156, _t2157));
        }
        _f2152 = merge_by_place(base.argument_names, _v2154);
    } else {
        var _v2158 = Array<(Loc, String)>();
        var _n2159 = input.count();
        for (var _ in 0.._n2159) {
            var _t2160 = input.loc();
            var _t2161 = input.text();
            _v2158.append((_t2160, _t2161));
        }
        _f2152 = _v2158;
    }
    var _f2171 = Array<String>();
    var _tag2172 = input.unsigned();
    if (_tag2172 == 1) {
        input.unsigned();
        for (var _i2167 in 0..base.namespaces.count) {
            _f2171.append(base.namespaces[_i2167]);
        }
        var _more2174 = input.count();
        for (var _ in 0.._more2174) {
            _f2171.append(input.text());
        }
    } else {
        var _v2175 = Array<String>();
        var _n2176 = input.count();
        for (var _ in 0.._n2176) {
            _v2175.append(input.text());
        }
        _f2171 = _v2175;
    }
    var _f2184 = Array<bool>();
    var _tag2185 = input.unsigned();
    if (_tag2185 == 1) {
        input.unsigned();
        for (var _i2182 in 0..base.cached_files.count) {
            _f2184.append(base.cached_files[_i2182]);
        }
        var _more2187 = input.count();
        for (var _ in 0.._more2187) {
            _f2184.append(input.flag());
        }
    } else {
        var _v2188 = Array<bool>();
        var _n2189 = input.count();
        for (var _ in 0.._n2189) {
            _v2188.append(input.flag());
        }
        _f2184 = _v2188;
    }
    var _f2207 = HashMap<Loc, String>();
    var _tag2208 = input.unsigned();
    if (_tag2208 == 1) {
        for (var (_bk2209, _bv) in base.recorded_summaries) {
            _f2207[_bk2209] = _bv;
        }
        var _v2210 = HashMap<Loc, String>();
        var _n2211 = input.count();
        for (var _ in 0.._n2211) {
            var _k2212 = input.loc();
            _v2210[_k2212] = input.text();
        }
        for (var (_bk2209, _av) in _v2210) {
            _f2207[_bk2209] = _av;
        }
    } else {
        var _v2213 = HashMap<Loc, String>();
        var _n2214 = input.count();
        for (var _ in 0.._n2214) {
            var _k2215 = input.loc();
            _v2213[_k2215] = input.text();
        }
        _f2207 = _v2213;
    }
    var _f2231 = HashSet<Loc>();
    var _tag2232 = input.unsigned();
    if (_tag2232 == 1) {
        for (var _bk2233 in base.stripped) {
            _f2231.insert(_bk2233);
        }
        var _v2234 = HashSet<Loc>();
        var _n2235 = input.count();
        for (var _ in 0.._n2235) {
            _v2234.insert(input.loc());
        }
        for (var _bk2233 in _v2234) {
            _f2231.insert(_bk2233);
        }
    } else {
        var _v2236 = HashSet<Loc>();
        var _n2237 = input.count();
        for (var _ in 0.._n2237) {
            _v2236.insert(input.loc());
        }
        _f2231 = _v2236;
    }
    var _frozen = input.flag();
    var _f2248 = Array<StructDef>();
    var _mode2251 = input.unsigned();
    if (_mode2251 == 2) {
        var _patched2254 = HashMap<ulong, StructDef>();
        var _n2249 = input.count();
        for (var _ in 0.._n2249) {
            var _name = input.text();
            var _slot = input.unsigned();
            if (input.merging) {
                _slot = struct_named(base.templates.structs, _name);
            }
            if (_slot >= base.templates.structs.count) {
                input.error = $"no struct {_name} to patch";
                break;
            }
            _patched2254[_slot] = _patch_t_read(input, base.templates.structs[_slot]);
        }
        ulong _bi2252 = 0;
        var _added = input.count();
        for (var _ in 0.._added) {
            var _at2253 = input.unsigned();
            while (_f2248.count < _at2253 or (input.merging and _bi2252 < base.templates.structs.count)) {
                var _p = _patched2254.try_get(_bi2252);
                _f2248.append(_p.is_value() ? _p.value() : base.templates.structs[_bi2252]);
                _bi2252 += 1;
            }
            _f2248.append(_m_StructDef_read(input));
        }
        while (_bi2252 < base.templates.structs.count) {
            var _p = _patched2254.try_get(_bi2252);
            _f2248.append(_p.is_value() ? _p.value() : base.templates.structs[_bi2252]);
            _bi2252 += 1;
        }
    } else {
        if (input.merging) {
            input.error = "structs written by place";
        }
        var _n2249 = input.count();
        for (var _ in 0.._n2249) {
            var _tag2250 = input.unsigned();
            if (_tag2250 & 1 == 1) {
                _f2248.append(
                    base.templates.structs[(_tag2250 >> 1) < base.templates.structs.count ? _tag2250 >> 1 : 0]
                );
            } else if (_tag2250 == 2) {
                var _was = base.templates.structs[input.unsigned()];
                _f2248.append(_patch_t_read(input, _was));
            } else {
                _f2248.append(_m_StructDef_read(input));
            }
        }
    }
    var _f2268 = Array<FunctionDef>();
    var _mode2271 = input.unsigned();
    if (_mode2271 == 2) {
        var _changed2257 = HashMap<ulong, FunctionDef>();
        var _nc2259 = input.count();
        for (var _ in 0.._nc2259) {
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
                _changed2257[_slot] = _el;
            } else {
                input.error = $"no {_name} to change";
            }
        }
        ulong _bi2272 = 0;
        var _n2269 = input.count();
        for (var _ in 0.._n2269) {
            var _at2273 = input.unsigned();
            while (_f2268.count < _at2273 or (input.merging and _bi2272 < base.templates.functions.count)) {
                var _c = _changed2257.try_get(_bi2272);
                _f2268.append(_c.is_value() ? _c.value() : base.templates.functions[_bi2272]);
                _bi2272 += 1;
            }
            _f2268.append(_m_FunctionDef_read(input));
        }
        while (_bi2272 < base.templates.functions.count) {
            var _c = _changed2257.try_get(_bi2272);
            _f2268.append(_c.is_value() ? _c.value() : base.templates.functions[_bi2272]);
            _bi2272 += 1;
        }
    } else if (_mode2271 == 3) {
        var _n2269 = input.count();
        for (var _ in 0.._n2269) {
            _f2268.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2269 = input.count();
        if (input.merging) {
            input.error = "tf" + " written by place";
        }
        for (var _ in 0.._n2269) {
            var _tag2270 = input.unsigned();
            if (_tag2270 & 1 == 1) {
                if (!input.merging) {
                    _f2268.append(base.templates.functions[_tag2270 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2268.append(_read);
                }
            }
        }
    }
    var _f2275 = Templates(_frozen, _f2248, _f2268);
    var _f2276 = DeltaBase.read_checked(input, base.checked);
    var _f2296 = HashMap<String, SpecRequest>();
    var _tag2297 = input.unsigned();
    if (_tag2297 == 1) {
        for (var (_bk2298, _bv) in base.spec_requests) {
            _f2296[_bk2298] = _bv;
        }
        var _v2299 = HashMap<String, SpecRequest>();
        var _n2300 = input.count();
        for (var _ in 0.._n2300) {
            var _k2301 = input.text();
            _v2299[_k2301] = _m_SpecRequest_read(input);
        }
        for (var (_bk2298, _av) in _v2299) {
            _f2296[_bk2298] = _av;
        }
    } else {
        var _v2302 = HashMap<String, SpecRequest>();
        var _n2303 = input.count();
        for (var _ in 0.._n2303) {
            var _k2304 = input.text();
            _v2302[_k2304] = _m_SpecRequest_read(input);
        }
        _f2296 = _v2302;
    }
    var _f2305 = input.flag();
    var _f2317 = Array<(Loc, String)>();
    var _tag2318 = input.unsigned();
    if (_tag2318 == 1) {
        input.unsigned();
        for (var _i2309 in 0..base.summaries_to_record.count) {
            _f2317.append(base.summaries_to_record[_i2309]);
        }
        var _more2320 = input.count();
        for (var _ in 0.._more2320) {
            var _t2321 = input.loc();
            var _t2322 = input.text();
            _f2317.append((_t2321, _t2322));
        }
    } else {
        var _v2323 = Array<(Loc, String)>();
        var _n2324 = input.count();
        for (var _ in 0.._n2324) {
            var _t2325 = input.loc();
            var _t2326 = input.text();
            _v2323.append((_t2325, _t2326));
        }
        _f2317 = _v2323;
    }
    var _f2357 = HashMap<String, Array<bool>>();
    var _tag2358 = input.unsigned();
    if (_tag2358 == 1) {
        for (var (_bk2359, _bv) in base.caller_copies) {
            _f2357[_bk2359] = _bv;
        }
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
        for (var (_bk2359, _av) in _v2360) {
            _f2357[_bk2359] = _av;
        }
    } else {
        var _v2365 = HashMap<String, Array<bool>>();
        var _n2366 = input.count();
        for (var _ in 0.._n2366) {
            var _k2367 = input.text();
            var _v2368 = Array<bool>();
            var _n2369 = input.count();
            for (var _ in 0.._n2369) {
                _v2368.append(input.flag());
            }
            _v2365[_k2367] = _v2368;
        }
        _f2357 = _v2365;
    }
    var _f2371 = input.flag();
    return Module(
        _f1503,
        _f1536,
        _f1556,
        _f1575,
        _f1594,
        _f1613,
        _f1632,
        _f1651,
        _f1670,
        _f1689,
        _f1708,
        _f1720,
        _f1736,
        _f1755,
        _f1774,
        _f1793,
        _f1814,
        _f1843,
        _f1862,
        _f1875,
        _f1902,
        _f1949,
        _f2036,
        _f2062,
        _f2082,
        _f2108,
        _f2126,
        _f2152,
        _f2171,
        _f2184,
        _f2207,
        _f2231,
        _f2275,
        _f2276,
        _f2296,
        _f2305,
        _f2317,
        _f2357,
        _f2371
    );
}

_m_Module_index(value: Module, base: DeltaBase) {
    ulong _j1509 = 0;
    for (var _item1491 in value.imports) {
        var scratch = base.scratch();
        _a_Import_write(scratch, _item1491);
        base.add("imports", scratch, _j1509);
        _j1509 += 1;
    }
    if (base.verifying) {
        ulong _j1543 = 0;
        for (var _item1510 in value.structs) {
            var scratch = base.scratch();
            _m_StructDef_write(scratch, _item1510);
            base.add("s", scratch, _j1543);
            base.name("s", _item1510.name, _j1543);
            _patch_s_index(_item1510, base, _j1543);
            _j1543 += 1;
        }
    }
    base.ref_structs = value.structs.clone();
    base.ref_struct_parts = Array<StructDef>();
    for (var _item1510 in value.structs) {
        base.ref_struct_parts.append(_m_StructDef_shallow(_item1510));
    }
    ulong _j1562 = 0;
    for (var _item1544 in value.traits) {
        var scratch = base.scratch();
        _m_TraitDef_write(scratch, _item1544);
        base.add("traits", scratch, _j1562);
        _j1562 += 1;
    }
    ulong _j1581 = 0;
    for (var _item1563 in value.extensions) {
        var scratch = base.scratch();
        _m_ExtensionDef_write(scratch, _item1563);
        base.add("extensions", scratch, _j1581);
        _j1581 += 1;
    }
    if (base.verifying) {
        ulong _j1600 = 0;
        for (var _item1582 in value.functions) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item1582);
            base.add("functions", scratch, _j1600);
            base.name("functions", _item1582.name, _j1600);
            _j1600 += 1;
        }
    }
    base.ref_functions = value.functions.clone();
    ulong _j1619 = 0;
    for (var _item1601 in value.externs) {
        var scratch = base.scratch();
        _m_ExternDef_write(scratch, _item1601);
        base.add("externs", scratch, _j1619);
        _j1619 += 1;
    }
    ulong _j1638 = 0;
    for (var _item1620 in value.globals) {
        var scratch = base.scratch();
        _m_VariableDef_write(scratch, _item1620);
        base.add("globals", scratch, _j1638);
        _j1638 += 1;
    }
    ulong _j1657 = 0;
    for (var _item1639 in value.static_blocks) {
        var scratch = base.scratch();
        _m_ModuleStaticBlock_write(scratch, _item1639);
        base.add("static_blocks", scratch, _j1657);
        _j1657 += 1;
    }
    ulong _j1676 = 0;
    for (var _item1658 in value.enums) {
        var scratch = base.scratch();
        _m_EnumDef_write(scratch, _item1658);
        base.add("enums", scratch, _j1676);
        _j1676 += 1;
    }
    ulong _j1695 = 0;
    for (var _item1677 in value.struct_specs) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item1677);
        base.add("struct_specs", scratch, _j1695);
        _j1695 += 1;
    }
    ulong _j1714 = 0;
    for (var _item1696 in value.func_specs) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item1696);
        base.add("func_specs", scratch, _j1714);
        _j1714 += 1;
    }
    ulong _j1723 = 0;
    for (var _item1715 in value.type_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1715);
        base.add("type_aliases", scratch, _j1723);
        _j1723 += 1;
    }
    ulong _j1742 = 0;
    for (var _item1724 in value.withheld) {
        var scratch = base.scratch();
        _m_Withheld_write(scratch, _item1724);
        base.add("withheld", scratch, _j1742);
        _j1742 += 1;
    }
    ulong _j1761 = 0;
    for (var _item1743 in value.properties) {
        var scratch = base.scratch();
        _m_PropertyDef_write(scratch, _item1743);
        base.add("properties", scratch, _j1761);
        _j1761 += 1;
    }
    ulong _j1780 = 0;
    for (var _item1762 in value.type_uses) {
        var scratch = base.scratch();
        _m_TypeUse_write(scratch, _item1762);
        base.add("type_uses", scratch, _j1780);
        _j1780 += 1;
    }
    ulong _j1799 = 0;
    for (var _item1781 in value.use_contexts) {
        var scratch = base.scratch();
        _m_UseContext_write(scratch, _item1781);
        base.add("use_contexts", scratch, _j1799);
        _j1799 += 1;
    }
    var _xscratch1826 = base.scratch();
    for (var _xitem1827 in value.literal_args) {
        var (_t1828, _t1829, _t1830) = _xitem1827;
        _xscratch1826.loc(_t1828);
        _xscratch1826.unsigned(_t1829);
        _xscratch1826.loc(_t1830);
    }
    base.keep_list("literal_args", value.literal_args.count, _xscratch1826);
    ulong _j1849 = 0;
    for (var _item1831 in value.constrained_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1831);
        base.add("constrained_aliases", scratch, _j1849);
        _j1849 += 1;
    }
    ulong _j1868 = 0;
    for (var _item1850 in value.trait_types) {
        var scratch = base.scratch();
        _m_TraitType_write(scratch, _item1850);
        base.add("trait_types", scratch, _j1868);
        _j1868 += 1;
    }
    ulong _cj1872 = 0;
    for (var _conv1870 in value.conversions) {
        var _own1871 = RecordOut();
        _own1871.blank_locs = true;
        _m_Conversion_write(_own1871, _conv1870);
        base.add_hashed("conversions", interface_text(_own1871), _cj1872);
        _cj1872 += 1;
    }
    for (var (_key1876, _) in value.overload_sets) {
        var _kscratch1877 = base.scratch();
        _kscratch1877.text(_key1876);
        var _vscratch1878 = base.scratch();
        _vscratch1878.unsigned(value.overload_sets[_key1876].count);
        for (var _item1915 in value.overload_sets[_key1876]) {
            _vscratch1878.text(_item1915);
        }
        base.keep_entry("overload_sets", _kscratch1877, _vscratch1878);
    }
    for (var (_key1916, _) in value.overload_unions) {
        var _kscratch1917 = base.scratch();
        _kscratch1917.text(_key1916);
        var _vscratch1918 = base.scratch();
        _vscratch1918.unsigned(value.overload_unions[_key1916].count);
        for (var _item1966 in value.overload_unions[_key1916]) {
            _vscratch1918.unsigned(_item1966.count);
            for (var _item1967 in _item1966) {
                _vscratch1918.text(_item1967);
            }
        }
        base.keep_entry("overload_unions", _kscratch1917, _vscratch1918);
    }
    for (var (_key1968, _) in value.method_overload_sets) {
        var _kscratch1969 = base.scratch();
        _kscratch1969.text(_key1968);
        var _vscratch1970 = base.scratch();
        var _keys2056 = Array<(u8[], u8[], String)>();
        for (var (_key2055, _) in value.method_overload_sets[_key1968]) {
            var _scratch2057 = _vscratch1970.scratch();
            _scratch2057.text(_key2055);
            var _vscratch2059 = _vscratch1970.scratch();
            _vscratch2059.unsigned(value.method_overload_sets[_key1968][_key2055].count);
            for (var _item2060 in value.method_overload_sets[_key1968][_key2055]) {
                _vscratch2059.text(_item2060);
            }
            _keys2056.append((_scratch2057.finish(), _vscratch2059.finish(), _key2055));
        }
        _keys2056.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        _vscratch1970.unsigned(_keys2056.count);
        for (var (_bytes2058, _, _key2055) in _keys2056) {
            _vscratch1970.text(_key2055);
            _vscratch1970.unsigned(value.method_overload_sets[_key1968][_key2055].count);
            for (var _item2061 in value.method_overload_sets[_key1968][_key2055]) {
                _vscratch1970.text(_item2061);
            }
        }
        base.keep_entry("method_overload_sets", _kscratch1969, _vscratch1970);
    }
    for (var _key2063 in value.private_functions) {
        var _kscratch2064 = base.scratch();
        _kscratch2064.loc(_key2063);
        var _vscratch2065 = base.scratch();
        base.keep_entry("private_functions", _kscratch2064, _vscratch2065);
    }
    for (var _key2089 in value.file_private_functions) {
        var _kscratch2090 = base.scratch();
        _kscratch2090.loc(_key2089);
        var _vscratch2091 = base.scratch();
        base.keep_entry("file_private_functions", _kscratch2090, _vscratch2091);
    }
    var _xscratch2136 = base.scratch();
    for (var _xitem2137 in value.call_targets) {
        var (_t2138, _t2139) = _xitem2137;
        _xscratch2136.loc(_t2138);
        _xscratch2136.text(_t2139);
    }
    base.keep_list("call_targets", value.call_targets.count, _xscratch2136);
    for (var _item2140 in value.argument_names) {
        var _escratch2141 = base.scratch();
        var (_t2162, _t2163) = _item2140;
        _escratch2141.loc(_t2162);
        _escratch2141.text(_t2163);
        base.keep_entry("argument_names", _escratch2141, base.scratch());
    }
    var _xscratch2177 = base.scratch();
    for (var _xitem2178 in value.namespaces) {
        _xscratch2177.text(_xitem2178);
    }
    base.keep_list("namespaces", value.namespaces.count, _xscratch2177);
    var _xscratch2190 = base.scratch();
    for (var _xitem2191 in value.cached_files) {
        _xscratch2190.flag(_xitem2191);
    }
    base.keep_list("cached_files", value.cached_files.count, _xscratch2190);
    for (var (_key2192, _) in value.recorded_summaries) {
        var _kscratch2193 = base.scratch();
        _kscratch2193.loc(_key2192);
        var _vscratch2194 = base.scratch();
        _vscratch2194.text(value.recorded_summaries[_key2192]);
        base.keep_entry("recorded_summaries", _kscratch2193, _vscratch2194);
    }
    for (var _key2216 in value.stripped) {
        var _kscratch2217 = base.scratch();
        _kscratch2217.loc(_key2216);
        var _vscratch2218 = base.scratch();
        base.keep_entry("stripped", _kscratch2217, _vscratch2218);
    }
    if (base.verifying) {
        ulong _j2255 = 0;
        for (var _item2238 in value.templates.structs) {
            var scratch = base.scratch();
            _m_StructDef_write(scratch, _item2238);
            base.add("t", scratch, _j2255);
            base.name("t", _item2238.name, _j2255);
            _patch_t_index(_item2238, base, _j2255);
            _j2255 += 1;
        }
    }
    base.ref_templates = value.templates.structs.clone();
    base.ref_template_parts = Array<StructDef>();
    for (var _item2238 in value.templates.structs) {
        base.ref_template_parts.append(_m_StructDef_shallow(_item2238));
    }
    if (base.verifying) {
        ulong _j2274 = 0;
        for (var _item2256 in value.templates.functions) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2256);
            base.add("tf", scratch, _j2274);
            base.name("tf", _item2256.name, _j2274);
            _j2274 += 1;
        }
    }
    base.ref_template_functions = value.templates.functions.clone();
    base.keep_checked(value.checked);
    for (var (_key2277, _) in value.spec_requests) {
        var _kscratch2278 = base.scratch();
        _kscratch2278.text(_key2277);
        var _vscratch2279 = base.scratch();
        _m_SpecRequest_write(_vscratch2279, value.spec_requests[_key2277]);
        base.keep_entry("spec_requests", _kscratch2278, _vscratch2279);
    }
    var _xscratch2327 = base.scratch();
    for (var _xitem2328 in value.summaries_to_record) {
        var (_t2329, _t2330) = _xitem2328;
        _xscratch2327.loc(_t2329);
        _xscratch2327.text(_t2330);
    }
    base.keep_list("summaries_to_record", value.summaries_to_record.count, _xscratch2327);
    for (var (_key2331, _) in value.caller_copies) {
        var _kscratch2332 = base.scratch();
        _kscratch2332.text(_key2331);
        var _vscratch2333 = base.scratch();
        _vscratch2333.unsigned(value.caller_copies[_key2331].count);
        for (var _item2370 in value.caller_copies[_key2331]) {
            _vscratch2333.flag(_item2370);
        }
        base.keep_entry("caller_copies", _kscratch2332, _vscratch2333);
    }
}

_m_Module_index_resumed(value: Module, base: DeltaBase) {
    ulong _j1723 = 0;
    for (var _item1715 in value.type_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1715);
        base.add("type_aliases", scratch, _j1723);
        _j1723 += 1;
    }
    for (var (_key2192, _) in value.recorded_summaries) {
        var _kscratch2193 = base.scratch();
        _kscratch2193.loc(_key2192);
        var _vscratch2194 = base.scratch();
        _vscratch2194.text(value.recorded_summaries[_key2192]);
        base.keep_entry("recorded_summaries", _kscratch2193, _vscratch2194);
    }
    var _xscratch2327 = base.scratch();
    for (var _xitem2328 in value.summaries_to_record) {
        var (_t2329, _t2330) = _xitem2328;
        _xscratch2327.loc(_t2329);
        _xscratch2327.text(_t2330);
    }
    base.keep_list("summaries_to_record", value.summaries_to_record.count, _xscratch2327);
}

_patch_s_write(out: RecordOut, value: StructDef, base: DeltaBase, slot: ulong) {
    out.text(value.name);
    _m_TypeName_write(out, value.ty);
    var _seq2379 = base.ref_struct_parts[slot].generic_params;
    ulong _bj2380 = 0;
    var _news2381 = Array<ulong>();
    for (var _i2382 in 0..value.generic_params.count) {
        if (_bj2380 < _seq2379.count and value.generic_params[_i2382] === _seq2379[_bj2380]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_GenericParam_write(scratch, value.generic_params[_i2382]);
                base.verify_same($"s.{slot}.generic_params", _bj2380, scratch);
            }
            _bj2380 += 1;
        } else if (_bj2380 < _seq2379.count
            and _same_m_GenericParam(value.generic_params[_i2382], _seq2379[_bj2380], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_GenericParam_write(scratch, value.generic_params[_i2382]);
                base.verify_same($"s.{slot}.generic_params", _bj2380, scratch);
            }
            _bj2380 += 1;
        } else {
            _news2381.append(_i2382);
        }
    }
    if (_bj2380 == _seq2379.count) {
        out.unsigned(2);
        out.unsigned(_news2381.count);
        for (var _i2382 in _news2381) {
            out.unsigned(_i2382);
            _m_GenericParam_write(out, value.generic_params[_i2382]);
        }
        base.count("s.*.generic_params" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.generic_params" + " whole", 0);
        out.unsigned(value.generic_params.count);
        for (var _i2382 in 0..value.generic_params.count) {
            _m_GenericParam_write(out, value.generic_params[_i2382]);
        }
    }
    var _seq2395 = base.ref_struct_parts[slot].field_members;
    ulong _bj2396 = 0;
    var _news2397 = Array<ulong>();
    for (var _i2398 in 0..value.field_members.count) {
        if (_bj2396 < _seq2395.count and value.field_members[_i2398] === _seq2395[_bj2396]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_VariableDef_write(scratch, value.field_members[_i2398]);
                base.verify_same($"s.{slot}.field_members", _bj2396, scratch);
            }
            _bj2396 += 1;
        } else if (_bj2396 < _seq2395.count
            and _same_m_VariableDef(value.field_members[_i2398], _seq2395[_bj2396], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_VariableDef_write(scratch, value.field_members[_i2398]);
                base.verify_same($"s.{slot}.field_members", _bj2396, scratch);
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
    var _seq2411 = base.ref_struct_parts[slot].method_members;
    ulong _bj2412 = 0;
    var _news2413 = Array<ulong>();
    for (var _i2414 in 0..value.method_members.count) {
        if (_bj2412 < _seq2411.count and value.method_members[_i2414] === _seq2411[_bj2412]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.method_members[_i2414]);
                base.verify_same($"s.{slot}.method_members", _bj2412, scratch);
            }
            _bj2412 += 1;
        } else if (_bj2412 < _seq2411.count
            and _same_m_FunctionDef(value.method_members[_i2414], _seq2411[_bj2412], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.method_members[_i2414]);
                base.verify_same($"s.{slot}.method_members", _bj2412, scratch);
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
            _m_FunctionDef_write(out, value.method_members[_i2414]);
        }
        base.count("s.*.method_members" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.method_members" + " whole", 0);
        out.unsigned(value.method_members.count);
        for (var _i2414 in 0..value.method_members.count) {
            _m_FunctionDef_write(out, value.method_members[_i2414]);
        }
    }
    var _seq2427 = base.ref_struct_parts[slot].generic_methods;
    ulong _bj2428 = 0;
    var _news2429 = Array<ulong>();
    for (var _i2430 in 0..value.generic_methods.count) {
        if (_bj2428 < _seq2427.count and value.generic_methods[_i2430] === _seq2427[_bj2428]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.generic_methods[_i2430]);
                base.verify_same($"s.{slot}.generic_methods", _bj2428, scratch);
            }
            _bj2428 += 1;
        } else if (_bj2428 < _seq2427.count
            and _same_m_FunctionDef(value.generic_methods[_i2430], _seq2427[_bj2428], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.generic_methods[_i2430]);
                base.verify_same($"s.{slot}.generic_methods", _bj2428, scratch);
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
            _m_FunctionDef_write(out, value.generic_methods[_i2430]);
        }
        base.count("s.*.generic_methods" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.generic_methods" + " whole", 0);
        out.unsigned(value.generic_methods.count);
        for (var _i2430 in 0..value.generic_methods.count) {
            _m_FunctionDef_write(out, value.generic_methods[_i2430]);
        }
    }
    var _seq2443 = base.ref_struct_parts[slot].constructors;
    ulong _bj2444 = 0;
    var _news2445 = Array<ulong>();
    for (var _i2446 in 0..value.constructors.count) {
        if (_bj2444 < _seq2443.count and value.constructors[_i2446] === _seq2443[_bj2444]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.constructors[_i2446]);
                base.verify_same($"s.{slot}.constructors", _bj2444, scratch);
            }
            _bj2444 += 1;
        } else if (_bj2444 < _seq2443.count
            and _same_m_FunctionDef(value.constructors[_i2446], _seq2443[_bj2444], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.constructors[_i2446]);
                base.verify_same($"s.{slot}.constructors", _bj2444, scratch);
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
            _m_FunctionDef_write(out, value.constructors[_i2446]);
        }
        base.count("s.*.constructors" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.constructors" + " whole", 0);
        out.unsigned(value.constructors.count);
        for (var _i2446 in 0..value.constructors.count) {
            _m_FunctionDef_write(out, value.constructors[_i2446]);
        }
    }
    _m_FunctionDef_write(out, value.destructor);
    _m_FunctionDef_write(out, value.acquire);
    _m_FunctionDef_write(out, value.release);
    var _seq2462 = base.ref_struct_parts[slot].traits;
    ulong _bj2463 = 0;
    var _news2464 = Array<ulong>();
    for (var _i2465 in 0..value.traits.count) {
        if (_bj2463 < _seq2462.count and value.traits[_i2465] === _seq2462[_bj2463]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_TypeName_write(scratch, value.traits[_i2465]);
                base.verify_same($"s.{slot}.traits", _bj2463, scratch);
            }
            _bj2463 += 1;
        } else if (_bj2463 < _seq2462.count and _same_m_TypeName(value.traits[_i2465], _seq2462[_bj2463], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_TypeName_write(scratch, value.traits[_i2465]);
                base.verify_same($"s.{slot}.traits", _bj2463, scratch);
            }
            _bj2463 += 1;
        } else {
            _news2464.append(_i2465);
        }
    }
    if (_bj2463 == _seq2462.count) {
        out.unsigned(2);
        out.unsigned(_news2464.count);
        for (var _i2465 in _news2464) {
            out.unsigned(_i2465);
            _m_TypeName_write(out, value.traits[_i2465]);
        }
        base.count("s.*.traits" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.traits" + " whole", 0);
        out.unsigned(value.traits.count);
        for (var _i2465 in 0..value.traits.count) {
            _m_TypeName_write(out, value.traits[_i2465]);
        }
    }
    var _seq2478 = base.ref_struct_parts[slot].attributes;
    ulong _bj2479 = 0;
    var _news2480 = Array<ulong>();
    for (var _i2481 in 0..value.attributes.count) {
        if (_bj2479 < _seq2478.count and value.attributes[_i2481] === _seq2478[_bj2479]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _a_Attribute_write(scratch, value.attributes[_i2481]);
                base.verify_same($"s.{slot}.attributes", _bj2479, scratch);
            }
            _bj2479 += 1;
        } else if (_bj2479 < _seq2478.count and _same_a_Attribute(value.attributes[_i2481], _seq2478[_bj2479], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _a_Attribute_write(scratch, value.attributes[_i2481]);
                base.verify_same($"s.{slot}.attributes", _bj2479, scratch);
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
            _a_Attribute_write(out, value.attributes[_i2481]);
        }
        base.count("s.*.attributes" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.attributes" + " whole", 0);
        out.unsigned(value.attributes.count);
        for (var _i2481 in 0..value.attributes.count) {
            _a_Attribute_write(out, value.attributes[_i2481]);
        }
    }
    out.loc(value.loc);
    if (value.enum_cases.is_value()) {
        out.unsigned(1);
        out.unsigned(value.enum_cases.value().count);
        for (var _item2490 in value.enum_cases.value()) {
            _m_EnumCaseDef_write(out, _item2490);
        }
    } else {
        out.unsigned(0);
    }
}

_patch_s_read(input: RecordIn, was: StructDef): StructDef {
    var _f2372 = input.text();
    var _f2373 = _m_TypeName_read(input);
    var _f2383 = Array<GenericParam>();
    var _mode2386 = input.unsigned();
    if (_mode2386 == 2) {
        var _changed2375 = HashMap<ulong, GenericParam>();
        ulong _bi2387 = 0;
        var _n2384 = input.count();
        for (var _ in 0.._n2384) {
            var _at2388 = input.unsigned();
            while (_f2383.count < _at2388 or (input.merging and _bi2387 < was.generic_params.count)) {
                var _c = _changed2375.try_get(_bi2387);
                _f2383.append(_c.is_value() ? _c.value() : was.generic_params[_bi2387]);
                _bi2387 += 1;
            }
            _f2383.append(_m_GenericParam_read(input));
        }
        while (_bi2387 < was.generic_params.count) {
            var _c = _changed2375.try_get(_bi2387);
            _f2383.append(_c.is_value() ? _c.value() : was.generic_params[_bi2387]);
            _bi2387 += 1;
        }
    } else if (_mode2386 == 3) {
        var _n2384 = input.count();
        for (var _ in 0.._n2384) {
            _f2383.append(_m_GenericParam_read(input));
        }
    } else {
        var _n2384 = input.count();
        if (input.merging) {
            input.error = "s.*.generic_params" + " written by place";
        }
        for (var _ in 0.._n2384) {
            var _tag2385 = input.unsigned();
            if (_tag2385 & 1 == 1) {
                if (!input.merging) {
                    _f2383.append(was.generic_params[_tag2385 >> 1]);
                }
            } else {
                var _read = _m_GenericParam_read(input);
                if (!input.merging or true) {
                    _f2383.append(_read);
                }
            }
        }
    }
    var _f2399 = Array<VariableDef>();
    var _mode2402 = input.unsigned();
    if (_mode2402 == 2) {
        var _changed2391 = HashMap<ulong, VariableDef>();
        ulong _bi2403 = 0;
        var _n2400 = input.count();
        for (var _ in 0.._n2400) {
            var _at2404 = input.unsigned();
            while (_f2399.count < _at2404 or (input.merging and _bi2403 < was.field_members.count)) {
                var _c = _changed2391.try_get(_bi2403);
                _f2399.append(_c.is_value() ? _c.value() : was.field_members[_bi2403]);
                _bi2403 += 1;
            }
            _f2399.append(_m_VariableDef_read(input));
        }
        while (_bi2403 < was.field_members.count) {
            var _c = _changed2391.try_get(_bi2403);
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
    var _f2415 = Array<FunctionDef>();
    var _mode2418 = input.unsigned();
    if (_mode2418 == 2) {
        var _changed2407 = HashMap<ulong, FunctionDef>();
        ulong _bi2419 = 0;
        var _n2416 = input.count();
        for (var _ in 0.._n2416) {
            var _at2420 = input.unsigned();
            while (_f2415.count < _at2420 or (input.merging and _bi2419 < was.method_members.count)) {
                var _c = _changed2407.try_get(_bi2419);
                _f2415.append(_c.is_value() ? _c.value() : was.method_members[_bi2419]);
                _bi2419 += 1;
            }
            _f2415.append(_m_FunctionDef_read(input));
        }
        while (_bi2419 < was.method_members.count) {
            var _c = _changed2407.try_get(_bi2419);
            _f2415.append(_c.is_value() ? _c.value() : was.method_members[_bi2419]);
            _bi2419 += 1;
        }
    } else if (_mode2418 == 3) {
        var _n2416 = input.count();
        for (var _ in 0.._n2416) {
            _f2415.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2416 = input.count();
        if (input.merging) {
            input.error = "s.*.method_members" + " written by place";
        }
        for (var _ in 0.._n2416) {
            var _tag2417 = input.unsigned();
            if (_tag2417 & 1 == 1) {
                if (!input.merging) {
                    _f2415.append(was.method_members[_tag2417 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
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
            while (_f2431.count < _at2436 or (input.merging and _bi2435 < was.generic_methods.count)) {
                var _c = _changed2423.try_get(_bi2435);
                _f2431.append(_c.is_value() ? _c.value() : was.generic_methods[_bi2435]);
                _bi2435 += 1;
            }
            _f2431.append(_m_FunctionDef_read(input));
        }
        while (_bi2435 < was.generic_methods.count) {
            var _c = _changed2423.try_get(_bi2435);
            _f2431.append(_c.is_value() ? _c.value() : was.generic_methods[_bi2435]);
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
            input.error = "s.*.generic_methods" + " written by place";
        }
        for (var _ in 0.._n2432) {
            var _tag2433 = input.unsigned();
            if (_tag2433 & 1 == 1) {
                if (!input.merging) {
                    _f2431.append(was.generic_methods[_tag2433 >> 1]);
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
            while (_f2447.count < _at2452 or (input.merging and _bi2451 < was.constructors.count)) {
                var _c = _changed2439.try_get(_bi2451);
                _f2447.append(_c.is_value() ? _c.value() : was.constructors[_bi2451]);
                _bi2451 += 1;
            }
            _f2447.append(_m_FunctionDef_read(input));
        }
        while (_bi2451 < was.constructors.count) {
            var _c = _changed2439.try_get(_bi2451);
            _f2447.append(_c.is_value() ? _c.value() : was.constructors[_bi2451]);
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
            input.error = "s.*.constructors" + " written by place";
        }
        for (var _ in 0.._n2448) {
            var _tag2449 = input.unsigned();
            if (_tag2449 & 1 == 1) {
                if (!input.merging) {
                    _f2447.append(was.constructors[_tag2449 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2447.append(_read);
                }
            }
        }
    }
    var _f2454 = _m_FunctionDef_read(input);
    var _f2455 = _m_FunctionDef_read(input);
    var _f2456 = _m_FunctionDef_read(input);
    var _f2466 = Array<TypeName>();
    var _mode2469 = input.unsigned();
    if (_mode2469 == 2) {
        var _changed2458 = HashMap<ulong, TypeName>();
        ulong _bi2470 = 0;
        var _n2467 = input.count();
        for (var _ in 0.._n2467) {
            var _at2471 = input.unsigned();
            while (_f2466.count < _at2471 or (input.merging and _bi2470 < was.traits.count)) {
                var _c = _changed2458.try_get(_bi2470);
                _f2466.append(_c.is_value() ? _c.value() : was.traits[_bi2470]);
                _bi2470 += 1;
            }
            _f2466.append(_m_TypeName_read(input));
        }
        while (_bi2470 < was.traits.count) {
            var _c = _changed2458.try_get(_bi2470);
            _f2466.append(_c.is_value() ? _c.value() : was.traits[_bi2470]);
            _bi2470 += 1;
        }
    } else if (_mode2469 == 3) {
        var _n2467 = input.count();
        for (var _ in 0.._n2467) {
            _f2466.append(_m_TypeName_read(input));
        }
    } else {
        var _n2467 = input.count();
        if (input.merging) {
            input.error = "s.*.traits" + " written by place";
        }
        for (var _ in 0.._n2467) {
            var _tag2468 = input.unsigned();
            if (_tag2468 & 1 == 1) {
                if (!input.merging) {
                    _f2466.append(was.traits[_tag2468 >> 1]);
                }
            } else {
                var _read = _m_TypeName_read(input);
                if (!input.merging or true) {
                    _f2466.append(_read);
                }
            }
        }
    }
    var _f2482 = Array<ast.Attribute>();
    var _mode2485 = input.unsigned();
    if (_mode2485 == 2) {
        var _changed2474 = HashMap<ulong, ast.Attribute>();
        ulong _bi2486 = 0;
        var _n2483 = input.count();
        for (var _ in 0.._n2483) {
            var _at2487 = input.unsigned();
            while (_f2482.count < _at2487 or (input.merging and _bi2486 < was.attributes.count)) {
                var _c = _changed2474.try_get(_bi2486);
                _f2482.append(_c.is_value() ? _c.value() : was.attributes[_bi2486]);
                _bi2486 += 1;
            }
            _f2482.append(_a_Attribute_read(input));
        }
        while (_bi2486 < was.attributes.count) {
            var _c = _changed2474.try_get(_bi2486);
            _f2482.append(_c.is_value() ? _c.value() : was.attributes[_bi2486]);
            _bi2486 += 1;
        }
    } else if (_mode2485 == 3) {
        var _n2483 = input.count();
        for (var _ in 0.._n2483) {
            _f2482.append(_a_Attribute_read(input));
        }
    } else {
        var _n2483 = input.count();
        if (input.merging) {
            input.error = "s.*.attributes" + " written by place";
        }
        for (var _ in 0.._n2483) {
            var _tag2484 = input.unsigned();
            if (_tag2484 & 1 == 1) {
                if (!input.merging) {
                    _f2482.append(was.attributes[_tag2484 >> 1]);
                }
            } else {
                var _read = _a_Attribute_read(input);
                if (!input.merging or true) {
                    _f2482.append(_read);
                }
            }
        }
    }
    var _f2489 = input.loc();
    var _o2491 = Optional<Array<EnumCaseDef>>.Empty;
    if (input.unsigned() == 1) {
        var _v2492 = Array<EnumCaseDef>();
        var _n2493 = input.count();
        for (var _ in 0.._n2493) {
            _v2492.append(_m_EnumCaseDef_read(input));
        }
        _o2491 = Optional<Array<EnumCaseDef>>.Value(_v2492);
    }
    var _f2494 = _o2491;
    return StructDef(
        _f2372, _f2373, _f2383, _f2399, _f2415, _f2431, _f2447, _f2454, _f2455, _f2456, _f2466, _f2482, _f2489, _f2494
    );
}

_patch_s_index(value: StructDef, base: DeltaBase, slot: ulong) {
    if (base.verifying) {
        ulong _j2389 = 0;
        for (var _item2374 in value.generic_params) {
            var scratch = base.scratch();
            _m_GenericParam_write(scratch, _item2374);
            base.add($"s.{slot}.generic_params", scratch, _j2389);
            _j2389 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2405 = 0;
        for (var _item2390 in value.field_members) {
            var scratch = base.scratch();
            _m_VariableDef_write(scratch, _item2390);
            base.add($"s.{slot}.field_members", scratch, _j2405);
            _j2405 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2421 = 0;
        for (var _item2406 in value.method_members) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2406);
            base.add($"s.{slot}.method_members", scratch, _j2421);
            _j2421 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2437 = 0;
        for (var _item2422 in value.generic_methods) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2422);
            base.add($"s.{slot}.generic_methods", scratch, _j2437);
            _j2437 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2453 = 0;
        for (var _item2438 in value.constructors) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2438);
            base.add($"s.{slot}.constructors", scratch, _j2453);
            _j2453 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2472 = 0;
        for (var _item2457 in value.traits) {
            var scratch = base.scratch();
            _m_TypeName_write(scratch, _item2457);
            base.add($"s.{slot}.traits", scratch, _j2472);
            _j2472 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2488 = 0;
        for (var _item2473 in value.attributes) {
            var scratch = base.scratch();
            _a_Attribute_write(scratch, _item2473);
            base.add($"s.{slot}.attributes", scratch, _j2488);
            _j2488 += 1;
        }
    }
}

_patch_t_write(out: RecordOut, value: StructDef, base: DeltaBase, slot: ulong) {
    out.text(value.name);
    _m_TypeName_write(out, value.ty);
    var _seq2502 = base.ref_template_parts[slot].generic_params;
    ulong _bj2503 = 0;
    var _news2504 = Array<ulong>();
    for (var _i2505 in 0..value.generic_params.count) {
        if (_bj2503 < _seq2502.count and value.generic_params[_i2505] === _seq2502[_bj2503]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_GenericParam_write(scratch, value.generic_params[_i2505]);
                base.verify_same($"t.{slot}.generic_params", _bj2503, scratch);
            }
            _bj2503 += 1;
        } else if (_bj2503 < _seq2502.count
            and _same_m_GenericParam(value.generic_params[_i2505], _seq2502[_bj2503], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_GenericParam_write(scratch, value.generic_params[_i2505]);
                base.verify_same($"t.{slot}.generic_params", _bj2503, scratch);
            }
            _bj2503 += 1;
        } else {
            _news2504.append(_i2505);
        }
    }
    if (_bj2503 == _seq2502.count) {
        out.unsigned(2);
        out.unsigned(_news2504.count);
        for (var _i2505 in _news2504) {
            out.unsigned(_i2505);
            _m_GenericParam_write(out, value.generic_params[_i2505]);
        }
        base.count("t.*.generic_params" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.generic_params" + " whole", 0);
        out.unsigned(value.generic_params.count);
        for (var _i2505 in 0..value.generic_params.count) {
            _m_GenericParam_write(out, value.generic_params[_i2505]);
        }
    }
    var _seq2518 = base.ref_template_parts[slot].field_members;
    ulong _bj2519 = 0;
    var _news2520 = Array<ulong>();
    for (var _i2521 in 0..value.field_members.count) {
        if (_bj2519 < _seq2518.count and value.field_members[_i2521] === _seq2518[_bj2519]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_VariableDef_write(scratch, value.field_members[_i2521]);
                base.verify_same($"t.{slot}.field_members", _bj2519, scratch);
            }
            _bj2519 += 1;
        } else if (_bj2519 < _seq2518.count
            and _same_m_VariableDef(value.field_members[_i2521], _seq2518[_bj2519], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_VariableDef_write(scratch, value.field_members[_i2521]);
                base.verify_same($"t.{slot}.field_members", _bj2519, scratch);
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
            _m_VariableDef_write(out, value.field_members[_i2521]);
        }
        base.count("t.*.field_members" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.field_members" + " whole", 0);
        out.unsigned(value.field_members.count);
        for (var _i2521 in 0..value.field_members.count) {
            _m_VariableDef_write(out, value.field_members[_i2521]);
        }
    }
    var _seq2534 = base.ref_template_parts[slot].method_members;
    ulong _bj2535 = 0;
    var _news2536 = Array<ulong>();
    for (var _i2537 in 0..value.method_members.count) {
        if (_bj2535 < _seq2534.count and value.method_members[_i2537] === _seq2534[_bj2535]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.method_members[_i2537]);
                base.verify_same($"t.{slot}.method_members", _bj2535, scratch);
            }
            _bj2535 += 1;
        } else if (_bj2535 < _seq2534.count
            and _same_m_FunctionDef(value.method_members[_i2537], _seq2534[_bj2535], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.method_members[_i2537]);
                base.verify_same($"t.{slot}.method_members", _bj2535, scratch);
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
            _m_FunctionDef_write(out, value.method_members[_i2537]);
        }
        base.count("t.*.method_members" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.method_members" + " whole", 0);
        out.unsigned(value.method_members.count);
        for (var _i2537 in 0..value.method_members.count) {
            _m_FunctionDef_write(out, value.method_members[_i2537]);
        }
    }
    var _seq2550 = base.ref_template_parts[slot].generic_methods;
    ulong _bj2551 = 0;
    var _news2552 = Array<ulong>();
    for (var _i2553 in 0..value.generic_methods.count) {
        if (_bj2551 < _seq2550.count and value.generic_methods[_i2553] === _seq2550[_bj2551]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.generic_methods[_i2553]);
                base.verify_same($"t.{slot}.generic_methods", _bj2551, scratch);
            }
            _bj2551 += 1;
        } else if (_bj2551 < _seq2550.count
            and _same_m_FunctionDef(value.generic_methods[_i2553], _seq2550[_bj2551], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.generic_methods[_i2553]);
                base.verify_same($"t.{slot}.generic_methods", _bj2551, scratch);
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
            _m_FunctionDef_write(out, value.generic_methods[_i2553]);
        }
        base.count("t.*.generic_methods" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.generic_methods" + " whole", 0);
        out.unsigned(value.generic_methods.count);
        for (var _i2553 in 0..value.generic_methods.count) {
            _m_FunctionDef_write(out, value.generic_methods[_i2553]);
        }
    }
    var _seq2566 = base.ref_template_parts[slot].constructors;
    ulong _bj2567 = 0;
    var _news2568 = Array<ulong>();
    for (var _i2569 in 0..value.constructors.count) {
        if (_bj2567 < _seq2566.count and value.constructors[_i2569] === _seq2566[_bj2567]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.constructors[_i2569]);
                base.verify_same($"t.{slot}.constructors", _bj2567, scratch);
            }
            _bj2567 += 1;
        } else if (_bj2567 < _seq2566.count
            and _same_m_FunctionDef(value.constructors[_i2569], _seq2566[_bj2567], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.constructors[_i2569]);
                base.verify_same($"t.{slot}.constructors", _bj2567, scratch);
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
            _m_FunctionDef_write(out, value.constructors[_i2569]);
        }
        base.count("t.*.constructors" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.constructors" + " whole", 0);
        out.unsigned(value.constructors.count);
        for (var _i2569 in 0..value.constructors.count) {
            _m_FunctionDef_write(out, value.constructors[_i2569]);
        }
    }
    _m_FunctionDef_write(out, value.destructor);
    _m_FunctionDef_write(out, value.acquire);
    _m_FunctionDef_write(out, value.release);
    var _seq2585 = base.ref_template_parts[slot].traits;
    ulong _bj2586 = 0;
    var _news2587 = Array<ulong>();
    for (var _i2588 in 0..value.traits.count) {
        if (_bj2586 < _seq2585.count and value.traits[_i2588] === _seq2585[_bj2586]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_TypeName_write(scratch, value.traits[_i2588]);
                base.verify_same($"t.{slot}.traits", _bj2586, scratch);
            }
            _bj2586 += 1;
        } else if (_bj2586 < _seq2585.count and _same_m_TypeName(value.traits[_i2588], _seq2585[_bj2586], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_TypeName_write(scratch, value.traits[_i2588]);
                base.verify_same($"t.{slot}.traits", _bj2586, scratch);
            }
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
            _m_TypeName_write(out, value.traits[_i2588]);
        }
        base.count("t.*.traits" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.traits" + " whole", 0);
        out.unsigned(value.traits.count);
        for (var _i2588 in 0..value.traits.count) {
            _m_TypeName_write(out, value.traits[_i2588]);
        }
    }
    var _seq2601 = base.ref_template_parts[slot].attributes;
    ulong _bj2602 = 0;
    var _news2603 = Array<ulong>();
    for (var _i2604 in 0..value.attributes.count) {
        if (_bj2602 < _seq2601.count and value.attributes[_i2604] === _seq2601[_bj2602]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _a_Attribute_write(scratch, value.attributes[_i2604]);
                base.verify_same($"t.{slot}.attributes", _bj2602, scratch);
            }
            _bj2602 += 1;
        } else if (_bj2602 < _seq2601.count and _same_a_Attribute(value.attributes[_i2604], _seq2601[_bj2602], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _a_Attribute_write(scratch, value.attributes[_i2604]);
                base.verify_same($"t.{slot}.attributes", _bj2602, scratch);
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
            _a_Attribute_write(out, value.attributes[_i2604]);
        }
        base.count("t.*.attributes" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.attributes" + " whole", 0);
        out.unsigned(value.attributes.count);
        for (var _i2604 in 0..value.attributes.count) {
            _a_Attribute_write(out, value.attributes[_i2604]);
        }
    }
    out.loc(value.loc);
    if (value.enum_cases.is_value()) {
        out.unsigned(1);
        out.unsigned(value.enum_cases.value().count);
        for (var _item2613 in value.enum_cases.value()) {
            _m_EnumCaseDef_write(out, _item2613);
        }
    } else {
        out.unsigned(0);
    }
}

_patch_t_read(input: RecordIn, was: StructDef): StructDef {
    var _f2495 = input.text();
    var _f2496 = _m_TypeName_read(input);
    var _f2506 = Array<GenericParam>();
    var _mode2509 = input.unsigned();
    if (_mode2509 == 2) {
        var _changed2498 = HashMap<ulong, GenericParam>();
        ulong _bi2510 = 0;
        var _n2507 = input.count();
        for (var _ in 0.._n2507) {
            var _at2511 = input.unsigned();
            while (_f2506.count < _at2511 or (input.merging and _bi2510 < was.generic_params.count)) {
                var _c = _changed2498.try_get(_bi2510);
                _f2506.append(_c.is_value() ? _c.value() : was.generic_params[_bi2510]);
                _bi2510 += 1;
            }
            _f2506.append(_m_GenericParam_read(input));
        }
        while (_bi2510 < was.generic_params.count) {
            var _c = _changed2498.try_get(_bi2510);
            _f2506.append(_c.is_value() ? _c.value() : was.generic_params[_bi2510]);
            _bi2510 += 1;
        }
    } else if (_mode2509 == 3) {
        var _n2507 = input.count();
        for (var _ in 0.._n2507) {
            _f2506.append(_m_GenericParam_read(input));
        }
    } else {
        var _n2507 = input.count();
        if (input.merging) {
            input.error = "t.*.generic_params" + " written by place";
        }
        for (var _ in 0.._n2507) {
            var _tag2508 = input.unsigned();
            if (_tag2508 & 1 == 1) {
                if (!input.merging) {
                    _f2506.append(was.generic_params[_tag2508 >> 1]);
                }
            } else {
                var _read = _m_GenericParam_read(input);
                if (!input.merging or true) {
                    _f2506.append(_read);
                }
            }
        }
    }
    var _f2522 = Array<VariableDef>();
    var _mode2525 = input.unsigned();
    if (_mode2525 == 2) {
        var _changed2514 = HashMap<ulong, VariableDef>();
        ulong _bi2526 = 0;
        var _n2523 = input.count();
        for (var _ in 0.._n2523) {
            var _at2527 = input.unsigned();
            while (_f2522.count < _at2527 or (input.merging and _bi2526 < was.field_members.count)) {
                var _c = _changed2514.try_get(_bi2526);
                _f2522.append(_c.is_value() ? _c.value() : was.field_members[_bi2526]);
                _bi2526 += 1;
            }
            _f2522.append(_m_VariableDef_read(input));
        }
        while (_bi2526 < was.field_members.count) {
            var _c = _changed2514.try_get(_bi2526);
            _f2522.append(_c.is_value() ? _c.value() : was.field_members[_bi2526]);
            _bi2526 += 1;
        }
    } else if (_mode2525 == 3) {
        var _n2523 = input.count();
        for (var _ in 0.._n2523) {
            _f2522.append(_m_VariableDef_read(input));
        }
    } else {
        var _n2523 = input.count();
        if (input.merging) {
            input.error = "t.*.field_members" + " written by place";
        }
        for (var _ in 0.._n2523) {
            var _tag2524 = input.unsigned();
            if (_tag2524 & 1 == 1) {
                if (!input.merging) {
                    _f2522.append(was.field_members[_tag2524 >> 1]);
                }
            } else {
                var _read = _m_VariableDef_read(input);
                if (!input.merging or true) {
                    _f2522.append(_read);
                }
            }
        }
    }
    var _f2538 = Array<FunctionDef>();
    var _mode2541 = input.unsigned();
    if (_mode2541 == 2) {
        var _changed2530 = HashMap<ulong, FunctionDef>();
        ulong _bi2542 = 0;
        var _n2539 = input.count();
        for (var _ in 0.._n2539) {
            var _at2543 = input.unsigned();
            while (_f2538.count < _at2543 or (input.merging and _bi2542 < was.method_members.count)) {
                var _c = _changed2530.try_get(_bi2542);
                _f2538.append(_c.is_value() ? _c.value() : was.method_members[_bi2542]);
                _bi2542 += 1;
            }
            _f2538.append(_m_FunctionDef_read(input));
        }
        while (_bi2542 < was.method_members.count) {
            var _c = _changed2530.try_get(_bi2542);
            _f2538.append(_c.is_value() ? _c.value() : was.method_members[_bi2542]);
            _bi2542 += 1;
        }
    } else if (_mode2541 == 3) {
        var _n2539 = input.count();
        for (var _ in 0.._n2539) {
            _f2538.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2539 = input.count();
        if (input.merging) {
            input.error = "t.*.method_members" + " written by place";
        }
        for (var _ in 0.._n2539) {
            var _tag2540 = input.unsigned();
            if (_tag2540 & 1 == 1) {
                if (!input.merging) {
                    _f2538.append(was.method_members[_tag2540 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
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
            while (_f2554.count < _at2559 or (input.merging and _bi2558 < was.generic_methods.count)) {
                var _c = _changed2546.try_get(_bi2558);
                _f2554.append(_c.is_value() ? _c.value() : was.generic_methods[_bi2558]);
                _bi2558 += 1;
            }
            _f2554.append(_m_FunctionDef_read(input));
        }
        while (_bi2558 < was.generic_methods.count) {
            var _c = _changed2546.try_get(_bi2558);
            _f2554.append(_c.is_value() ? _c.value() : was.generic_methods[_bi2558]);
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
            input.error = "t.*.generic_methods" + " written by place";
        }
        for (var _ in 0.._n2555) {
            var _tag2556 = input.unsigned();
            if (_tag2556 & 1 == 1) {
                if (!input.merging) {
                    _f2554.append(was.generic_methods[_tag2556 >> 1]);
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
            while (_f2570.count < _at2575 or (input.merging and _bi2574 < was.constructors.count)) {
                var _c = _changed2562.try_get(_bi2574);
                _f2570.append(_c.is_value() ? _c.value() : was.constructors[_bi2574]);
                _bi2574 += 1;
            }
            _f2570.append(_m_FunctionDef_read(input));
        }
        while (_bi2574 < was.constructors.count) {
            var _c = _changed2562.try_get(_bi2574);
            _f2570.append(_c.is_value() ? _c.value() : was.constructors[_bi2574]);
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
            input.error = "t.*.constructors" + " written by place";
        }
        for (var _ in 0.._n2571) {
            var _tag2572 = input.unsigned();
            if (_tag2572 & 1 == 1) {
                if (!input.merging) {
                    _f2570.append(was.constructors[_tag2572 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2570.append(_read);
                }
            }
        }
    }
    var _f2577 = _m_FunctionDef_read(input);
    var _f2578 = _m_FunctionDef_read(input);
    var _f2579 = _m_FunctionDef_read(input);
    var _f2589 = Array<TypeName>();
    var _mode2592 = input.unsigned();
    if (_mode2592 == 2) {
        var _changed2581 = HashMap<ulong, TypeName>();
        ulong _bi2593 = 0;
        var _n2590 = input.count();
        for (var _ in 0.._n2590) {
            var _at2594 = input.unsigned();
            while (_f2589.count < _at2594 or (input.merging and _bi2593 < was.traits.count)) {
                var _c = _changed2581.try_get(_bi2593);
                _f2589.append(_c.is_value() ? _c.value() : was.traits[_bi2593]);
                _bi2593 += 1;
            }
            _f2589.append(_m_TypeName_read(input));
        }
        while (_bi2593 < was.traits.count) {
            var _c = _changed2581.try_get(_bi2593);
            _f2589.append(_c.is_value() ? _c.value() : was.traits[_bi2593]);
            _bi2593 += 1;
        }
    } else if (_mode2592 == 3) {
        var _n2590 = input.count();
        for (var _ in 0.._n2590) {
            _f2589.append(_m_TypeName_read(input));
        }
    } else {
        var _n2590 = input.count();
        if (input.merging) {
            input.error = "t.*.traits" + " written by place";
        }
        for (var _ in 0.._n2590) {
            var _tag2591 = input.unsigned();
            if (_tag2591 & 1 == 1) {
                if (!input.merging) {
                    _f2589.append(was.traits[_tag2591 >> 1]);
                }
            } else {
                var _read = _m_TypeName_read(input);
                if (!input.merging or true) {
                    _f2589.append(_read);
                }
            }
        }
    }
    var _f2605 = Array<ast.Attribute>();
    var _mode2608 = input.unsigned();
    if (_mode2608 == 2) {
        var _changed2597 = HashMap<ulong, ast.Attribute>();
        ulong _bi2609 = 0;
        var _n2606 = input.count();
        for (var _ in 0.._n2606) {
            var _at2610 = input.unsigned();
            while (_f2605.count < _at2610 or (input.merging and _bi2609 < was.attributes.count)) {
                var _c = _changed2597.try_get(_bi2609);
                _f2605.append(_c.is_value() ? _c.value() : was.attributes[_bi2609]);
                _bi2609 += 1;
            }
            _f2605.append(_a_Attribute_read(input));
        }
        while (_bi2609 < was.attributes.count) {
            var _c = _changed2597.try_get(_bi2609);
            _f2605.append(_c.is_value() ? _c.value() : was.attributes[_bi2609]);
            _bi2609 += 1;
        }
    } else if (_mode2608 == 3) {
        var _n2606 = input.count();
        for (var _ in 0.._n2606) {
            _f2605.append(_a_Attribute_read(input));
        }
    } else {
        var _n2606 = input.count();
        if (input.merging) {
            input.error = "t.*.attributes" + " written by place";
        }
        for (var _ in 0.._n2606) {
            var _tag2607 = input.unsigned();
            if (_tag2607 & 1 == 1) {
                if (!input.merging) {
                    _f2605.append(was.attributes[_tag2607 >> 1]);
                }
            } else {
                var _read = _a_Attribute_read(input);
                if (!input.merging or true) {
                    _f2605.append(_read);
                }
            }
        }
    }
    var _f2612 = input.loc();
    var _o2614 = Optional<Array<EnumCaseDef>>.Empty;
    if (input.unsigned() == 1) {
        var _v2615 = Array<EnumCaseDef>();
        var _n2616 = input.count();
        for (var _ in 0.._n2616) {
            _v2615.append(_m_EnumCaseDef_read(input));
        }
        _o2614 = Optional<Array<EnumCaseDef>>.Value(_v2615);
    }
    var _f2617 = _o2614;
    return StructDef(
        _f2495, _f2496, _f2506, _f2522, _f2538, _f2554, _f2570, _f2577, _f2578, _f2579, _f2589, _f2605, _f2612, _f2617
    );
}

_patch_t_index(value: StructDef, base: DeltaBase, slot: ulong) {
    if (base.verifying) {
        ulong _j2512 = 0;
        for (var _item2497 in value.generic_params) {
            var scratch = base.scratch();
            _m_GenericParam_write(scratch, _item2497);
            base.add($"t.{slot}.generic_params", scratch, _j2512);
            _j2512 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2528 = 0;
        for (var _item2513 in value.field_members) {
            var scratch = base.scratch();
            _m_VariableDef_write(scratch, _item2513);
            base.add($"t.{slot}.field_members", scratch, _j2528);
            _j2528 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2544 = 0;
        for (var _item2529 in value.method_members) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2529);
            base.add($"t.{slot}.method_members", scratch, _j2544);
            _j2544 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2560 = 0;
        for (var _item2545 in value.generic_methods) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2545);
            base.add($"t.{slot}.generic_methods", scratch, _j2560);
            _j2560 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2576 = 0;
        for (var _item2561 in value.constructors) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2561);
            base.add($"t.{slot}.constructors", scratch, _j2576);
            _j2576 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2595 = 0;
        for (var _item2580 in value.traits) {
            var scratch = base.scratch();
            _m_TypeName_write(scratch, _item2580);
            base.add($"t.{slot}.traits", scratch, _j2595);
            _j2595 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2611 = 0;
        for (var _item2596 in value.attributes) {
            var scratch = base.scratch();
            _a_Attribute_write(scratch, _item2596);
            base.add($"t.{slot}.attributes", scratch, _j2611);
            _j2611 += 1;
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
        for (var _item2618 in value.imports) {
            _a_Import_write(out, _item2618);
        }
        found.append(("imports", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.structs.count);
        for (var _item2619 in value.structs) {
            _m_StructDef_write(out, _item2619);
        }
        found.append(("structs", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.blank_bodies = false;
        out.unsigned(value.traits.count);
        for (var _item2620 in value.traits) {
            _m_TraitDef_write(out, _item2620);
        }
        found.append(("traits", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.extensions.count);
        for (var _item2621 in value.extensions) {
            _m_ExtensionDef_write(out, _item2621);
        }
        found.append(("extensions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.functions.count);
        for (var _item2622 in value.functions) {
            _m_FunctionDef_write(out, _item2622);
        }
        found.append(("functions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.externs.count);
        for (var _item2623 in value.externs) {
            _m_ExternDef_write(out, _item2623);
        }
        found.append(("externs", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.globals.count);
        for (var _item2624 in value.globals) {
            _m_VariableDef_write(out, _item2624);
        }
        found.append(("globals", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.static_blocks.count);
        for (var _item2625 in value.static_blocks) {
            _m_ModuleStaticBlock_write(out, _item2625);
        }
        found.append(("static_blocks", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.enums.count);
        for (var _item2626 in value.enums) {
            _m_EnumDef_write(out, _item2626);
        }
        found.append(("enums", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.struct_specs.count);
        for (var _item2627 in value.struct_specs) {
            _m_TypeName_write(out, _item2627);
        }
        found.append(("struct_specs", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.func_specs.count);
        for (var _item2628 in value.func_specs) {
            _m_TypeName_write(out, _item2628);
        }
        found.append(("func_specs", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.type_aliases.count);
        for (var _item2629 in value.type_aliases) {
            _m_TypeAliasDef_write(out, _item2629);
        }
        found.append(("type_aliases", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.withheld.count);
        for (var _item2630 in value.withheld) {
            _m_Withheld_write(out, _item2630);
        }
        found.append(("withheld", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.properties.count);
        for (var _item2631 in value.properties) {
            _m_PropertyDef_write(out, _item2631);
        }
        found.append(("properties", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.type_uses.count);
        for (var _item2632 in value.type_uses) {
            _m_TypeUse_write(out, _item2632);
        }
        found.append(("type_uses", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.use_contexts.count);
        for (var _item2633 in value.use_contexts) {
            _m_UseContext_write(out, _item2633);
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
            for (var _item2634 in value.literal_args) {
                var (_t2635, _t2636, _t2637) = _item2634;
                out.loc(_t2635);
                out.unsigned(_t2636);
                out.loc(_t2637);
            }
        }
        found.append(("literal_args", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.constrained_aliases.count);
        for (var _item2638 in value.constrained_aliases) {
            _m_TypeAliasDef_write(out, _item2638);
        }
        found.append(("constrained_aliases", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.trait_types.count);
        for (var _item2639 in value.trait_types) {
            _m_TraitType_write(out, _item2639);
        }
        found.append(("trait_types", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.conversions.count);
        for (var _item2640 in value.conversions) {
            _m_Conversion_write(out, _item2640);
        }
        found.append(("conversions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2642 = Array<(u8[], u8[], String)>();
        for (var (_key2641, _) in value.overload_sets) {
            var _scratch2643 = out.scratch();
            _scratch2643.text(_key2641);
            var _vscratch2645 = out.scratch();
            _vscratch2645.unsigned(value.overload_sets[_key2641].count);
            for (var _item2646 in value.overload_sets[_key2641]) {
                _vscratch2645.text(_item2646);
            }
            _keys2642.append((_scratch2643.finish(), _vscratch2645.finish(), _key2641));
        }
        _keys2642.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2642.count);
        for (var (_bytes2644, _, _key2641) in _keys2642) {
            out.text(_key2641);
            out.unsigned(value.overload_sets[_key2641].count);
            for (var _item2647 in value.overload_sets[_key2641]) {
                out.text(_item2647);
            }
        }
        found.append(("overload_sets", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2649 = Array<(u8[], u8[], String)>();
        for (var (_key2648, _) in value.overload_unions) {
            var _scratch2650 = out.scratch();
            _scratch2650.text(_key2648);
            var _vscratch2652 = out.scratch();
            _vscratch2652.unsigned(value.overload_unions[_key2648].count);
            for (var _item2653 in value.overload_unions[_key2648]) {
                _vscratch2652.unsigned(_item2653.count);
                for (var _item2654 in _item2653) {
                    _vscratch2652.text(_item2654);
                }
            }
            _keys2649.append((_scratch2650.finish(), _vscratch2652.finish(), _key2648));
        }
        _keys2649.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2649.count);
        for (var (_bytes2651, _, _key2648) in _keys2649) {
            out.text(_key2648);
            out.unsigned(value.overload_unions[_key2648].count);
            for (var _item2655 in value.overload_unions[_key2648]) {
                out.unsigned(_item2655.count);
                for (var _item2656 in _item2655) {
                    out.text(_item2656);
                }
            }
        }
        found.append(("overload_unions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2658 = Array<(u8[], u8[], String)>();
        for (var (_key2657, _) in value.method_overload_sets) {
            var _scratch2659 = out.scratch();
            _scratch2659.text(_key2657);
            var _vscratch2661 = out.scratch();
            var _keys2663 = Array<(u8[], u8[], String)>();
            for (var (_key2662, _) in value.method_overload_sets[_key2657]) {
                var _scratch2664 = _vscratch2661.scratch();
                _scratch2664.text(_key2662);
                var _vscratch2666 = _vscratch2661.scratch();
                _vscratch2666.unsigned(value.method_overload_sets[_key2657][_key2662].count);
                for (var _item2667 in value.method_overload_sets[_key2657][_key2662]) {
                    _vscratch2666.text(_item2667);
                }
                _keys2663.append((_scratch2664.finish(), _vscratch2666.finish(), _key2662));
            }
            _keys2663.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            _vscratch2661.unsigned(_keys2663.count);
            for (var (_bytes2665, _, _key2662) in _keys2663) {
                _vscratch2661.text(_key2662);
                _vscratch2661.unsigned(value.method_overload_sets[_key2657][_key2662].count);
                for (var _item2668 in value.method_overload_sets[_key2657][_key2662]) {
                    _vscratch2661.text(_item2668);
                }
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
            var _keys2670 = Array<(u8[], u8[], String)>();
            for (var (_key2669, _) in value.method_overload_sets[_key2657]) {
                var _scratch2671 = out.scratch();
                _scratch2671.text(_key2669);
                var _vscratch2673 = out.scratch();
                _vscratch2673.unsigned(value.method_overload_sets[_key2657][_key2669].count);
                for (var _item2674 in value.method_overload_sets[_key2657][_key2669]) {
                    _vscratch2673.text(_item2674);
                }
                _keys2670.append((_scratch2671.finish(), _vscratch2673.finish(), _key2669));
            }
            _keys2670.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            out.unsigned(_keys2670.count);
            for (var (_bytes2672, _, _key2669) in _keys2670) {
                out.text(_key2669);
                out.unsigned(value.method_overload_sets[_key2657][_key2669].count);
                for (var _item2675 in value.method_overload_sets[_key2657][_key2669]) {
                    out.text(_item2675);
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
        var _keys2677 = Array<(u8[], u8[], Loc)>();
        for (var _key2676 in value.private_functions) {
            var _scratch2678 = out.scratch();
            _scratch2678.loc(_key2676);
            var _vscratch2680 = out.scratch();
            _keys2677.append((_scratch2678.finish(), _vscratch2680.finish(), _key2676));
        }
        _keys2677.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2677.count);
        for (var (_bytes2679, _, _key2676) in _keys2677) {
            out.loc(_key2676);
        }
        found.append(("private_functions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2682 = Array<(u8[], u8[], Loc)>();
        for (var _key2681 in value.file_private_functions) {
            var _scratch2683 = out.scratch();
            _scratch2683.loc(_key2681);
            var _vscratch2685 = out.scratch();
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
            out.loc(_key2681);
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
            for (var _item2686 in value.call_targets) {
                var (_t2687, _t2688) = _item2686;
                out.loc(_t2687);
                out.text(_t2688);
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
            for (var _item2689 in value.argument_names) {
                var (_t2690, _t2691) = _item2689;
                out.loc(_t2690);
                out.text(_t2691);
            }
        }
        found.append(("argument_names", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.namespaces.count);
        for (var _item2692 in value.namespaces) {
            out.text(_item2692);
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
            for (var _item2693 in value.cached_files) {
                out.flag(_item2693);
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
            var _keys2695 = Array<(u8[], u8[], Loc)>();
            for (var (_key2694, _) in value.recorded_summaries) {
                var _scratch2696 = out.scratch();
                _scratch2696.loc(_key2694);
                var _vscratch2698 = out.scratch();
                _vscratch2698.text(value.recorded_summaries[_key2694]);
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
                out.loc(_key2694);
                out.text(value.recorded_summaries[_key2694]);
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
            var _keys2700 = Array<(u8[], u8[], Loc)>();
            for (var _key2699 in value.stripped) {
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
        var _keys2705 = Array<(u8[], u8[], String)>();
        for (var (_key2704, _) in value.spec_requests) {
            var _scratch2706 = out.scratch();
            _scratch2706.text(_key2704);
            var _vscratch2708 = out.scratch();
            _m_SpecRequest_write(_vscratch2708, value.spec_requests[_key2704]);
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
            _m_SpecRequest_write(out, value.spec_requests[_key2704]);
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
            for (var _item2709 in value.summaries_to_record) {
                var (_t2710, _t2711) = _item2709;
                out.loc(_t2710);
                out.text(_t2711);
            }
        }
        found.append(("summaries_to_record", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2713 = Array<(u8[], u8[], String)>();
        for (var (_key2712, _) in value.caller_copies) {
            var _scratch2714 = out.scratch();
            _scratch2714.text(_key2712);
            var _vscratch2716 = out.scratch();
            _vscratch2716.unsigned(value.caller_copies[_key2712].count);
            for (var _item2717 in value.caller_copies[_key2712]) {
                _vscratch2716.flag(_item2717);
            }
            _keys2713.append((_scratch2714.finish(), _vscratch2716.finish(), _key2712));
        }
        _keys2713.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2713.count);
        for (var (_bytes2715, _, _key2712) in _keys2713) {
            out.text(_key2712);
            out.unsigned(value.caller_copies[_key2712].count);
            for (var _item2718 in value.caller_copies[_key2712]) {
                out.flag(_item2718);
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
    for (var _item2719 in value.structs) {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        _m_StructDef_write(out, _item2719);
        found.append(("structs " + _item2719.name, interface_text(out)));
    }
    for (var _item2720 in value.functions) {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        _m_FunctionDef_write(out, _item2720);
        found.append(("functions " + _item2720.name, interface_text(out)));
    }
    return found;
}
