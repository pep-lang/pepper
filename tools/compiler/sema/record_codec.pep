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
    var _f1359 = input.text();
    var _f1360 = input.flag();
    var _f1361 = input.loc();
    return StringLiteralExpression(_f1359, _f1360, _f1361);
}

_m_BinaryExpression_write(out: RecordOut, value: BinaryExpression) {
    _m_BinaryOp_write(out, value.op);
    _m_Expression_write(out, value.lhs);
    _m_Expression_write(out, value.rhs);
    out.loc(value.loc);
}

_m_BinaryExpression_read(input: RecordIn): BinaryExpression {
    var _f1362 = _m_BinaryOp_read(input);
    var _f1363 = _m_Expression_read(input);
    var _f1364 = _m_Expression_read(input);
    var _f1365 = input.loc();
    return BinaryExpression(_f1363, _f1364, _f1362, _f1365);
}

_m_UnaryExpression_write(out: RecordOut, value: UnaryExpression) {
    _m_UnaryOp_write(out, value.op);
    _m_Expression_write(out, value.operand);
    out.loc(value.loc);
}

_m_UnaryExpression_read(input: RecordIn): UnaryExpression {
    var _f1366 = _m_UnaryOp_read(input);
    var _f1367 = _m_Expression_read(input);
    var _f1368 = input.loc();
    return UnaryExpression(_f1367, _f1366, _f1368);
}

_m_CastExpression_write(out: RecordOut, value: CastExpression) {
    _m_Expression_write(out, value.expr);
    _m_TypeName_write(out, value.ty);
    out.loc(value.loc);
    _m_CastKind_write(out, value.kind);
}

_m_CastExpression_read(input: RecordIn): CastExpression {
    var _f1369 = _m_Expression_read(input);
    var _f1370 = _m_TypeName_read(input);
    var _f1371 = input.loc();
    var _f1372 = _m_CastKind_read(input);
    return CastExpression(_f1369, _f1370, _f1371, _f1372);
}

_m_TernaryExpression_write(out: RecordOut, value: TernaryExpression) {
    _m_Expression_write(out, value.condition);
    _m_Expression_write(out, value.true_expr);
    _m_Expression_write(out, value.false_expr);
}

_m_TernaryExpression_read(input: RecordIn): TernaryExpression {
    var _f1373 = _m_Expression_read(input);
    var _f1374 = _m_Expression_read(input);
    var _f1375 = _m_Expression_read(input);
    return TernaryExpression(_f1373, _f1374, _f1375);
}

_m_IndexExpression_write(out: RecordOut, value: IndexExpression) {
    _m_Expression_write(out, value.lhs);
    _m_Expression_write(out, value.rhs);
    out.loc(value.loc);
}

_m_IndexExpression_read(input: RecordIn): IndexExpression {
    var _f1376 = _m_Expression_read(input);
    var _f1377 = _m_Expression_read(input);
    var _f1378 = input.loc();
    return IndexExpression(_f1376, _f1377, _f1378);
}

_m_ArrayIndexExpression_write(out: RecordOut, value: ArrayIndexExpression) {
    _m_TypeName_write(out, value.ty);
    _m_Expression_write(out, value.lhs);
    _m_Expression_write(out, value.rhs);
    out.loc(value.loc);
}

_m_ArrayIndexExpression_read(input: RecordIn): ArrayIndexExpression {
    var _f1379 = _m_TypeName_read(input);
    var _f1380 = _m_Expression_read(input);
    var _f1381 = _m_Expression_read(input);
    var _f1382 = input.loc();
    return ArrayIndexExpression(_f1380, _f1381, _f1379, _f1382);
}

_m_SimdExpression_write(out: RecordOut, value: SimdExpression) {
    _m_SimdOp_write(out, value.op);
    _m_TypeName_write(out, value.ty);
    out.unsigned(value.args.count);
    for (var _item1406 in value.args) {
        _m_Expression_write(out, _item1406);
    }
    out.loc(value.loc);
}

_m_SimdExpression_read(input: RecordIn): SimdExpression {
    var _f1407 = _m_SimdOp_read(input);
    var _f1408 = _m_TypeName_read(input);
    var _v1409 = Array<Expression>();
    var _n1410 = input.count();
    for (var _ in 0.._n1410) {
        _v1409.append(_m_Expression_read(input));
    }
    var _f1411 = _v1409;
    var _f1412 = input.loc();
    return SimdExpression(_f1407, _f1408, _f1411, _f1412);
}

_m_CountStepExpression_write(out: RecordOut, value: CountStepExpression) {
    _m_CountField_write(out, value.field);
    out.flag(value.increment);
    out.flag(value.atomic);
}

_m_CountStepExpression_read(input: RecordIn): CountStepExpression {
    var _f1416 = _m_CountField_read(input);
    var _f1417 = input.flag();
    var _f1418 = input.flag();
    return CountStepExpression(_f1416, _f1417, _f1418);
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
    var _o1419 = Optional<TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o1419 = Optional<TypeName>.Value(_m_TypeName_read(input));
    }
    var _f1420 = _o1419;
    var _f1421 = input.text();
    var _f1422 = input.loc();
    return FunctionPointerExpression(_f1420, _f1421, _f1422);
}

_m_FunctionCallExpression_write(out: RecordOut, value: FunctionCallExpression) {
    out.text(value.function);
    out.unsigned(value.args.count);
    for (var _item1423 in value.args) {
        _m_Expression_write(out, _item1423);
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
    var _f1424 = input.text();
    var _v1425 = Array<Expression>();
    var _n1426 = input.count();
    for (var _ in 0.._n1426) {
        _v1425.append(_m_Expression_read(input));
    }
    var _f1427 = _v1425;
    var _f1428 = input.loc();
    var _o1429 = Optional<TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o1429 = Optional<TypeName>.Value(_m_TypeName_read(input));
    }
    var _f1430 = _o1429;
    var _f1431 = input.flag();
    return FunctionCallExpression(_f1424, _f1427, _f1428, _f1430, _f1431);
}

_m_NamedArgumentExpression_write(out: RecordOut, value: NamedArgumentExpression) {
    out.text(value.name);
    _m_Expression_write(out, value.value);
    out.loc(value.loc);
}

_m_NamedArgumentExpression_read(input: RecordIn): NamedArgumentExpression {
    var _f1432 = input.text();
    var _f1433 = _m_Expression_read(input);
    var _f1434 = input.loc();
    return NamedArgumentExpression(_f1433, _f1432, _f1434);
}

_m_DefaultArgumentExpression_write(out: RecordOut, value: DefaultArgumentExpression) {
    _m_TypeName_write(out, value.ty);
}

_m_DefaultArgumentExpression_read(input: RecordIn): DefaultArgumentExpression {
    var _f1435 = _m_TypeName_read(input);
    return DefaultArgumentExpression(_f1435);
}

_m_MethodCallExpression_write(out: RecordOut, value: MethodCallExpression) {
    _m_Expression_write(out, value.this_value);
    out.text(value.method);
    out.unsigned(value.args.count);
    for (var _item1436 in value.args) {
        _m_Expression_write(out, _item1436);
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
    var _f1437 = _m_Expression_read(input);
    var _f1438 = input.text();
    var _v1439 = Array<Expression>();
    var _n1440 = input.count();
    for (var _ in 0.._n1440) {
        _v1439.append(_m_Expression_read(input));
    }
    var _f1441 = _v1439;
    var _f1442 = input.loc();
    var _o1443 = Optional<TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o1443 = Optional<TypeName>.Value(_m_TypeName_read(input));
    }
    var _f1444 = _o1443;
    return MethodCallExpression(_f1437, _f1438, _f1441, _f1442, _f1444);
}

_m_FunctionRefExpression_write(out: RecordOut, value: FunctionRefExpression) {
    out.text(value.function);
    _m_TypeName_write(out, value.ty);
    out.loc(value.loc);
}

_m_FunctionRefExpression_read(input: RecordIn): FunctionRefExpression {
    var _f1445 = input.text();
    var _f1446 = _m_TypeName_read(input);
    var _f1447 = input.loc();
    return FunctionRefExpression(_f1445, _f1446, _f1447);
}

_m_InvokeExpression_write(out: RecordOut, value: InvokeExpression) {
    _m_Expression_write(out, value.callee);
    out.unsigned(value.args.count);
    for (var _item1448 in value.args) {
        _m_Expression_write(out, _item1448);
    }
}

_m_InvokeExpression_read(input: RecordIn): InvokeExpression {
    var _f1449 = _m_Expression_read(input);
    var _v1450 = Array<Expression>();
    var _n1451 = input.count();
    for (var _ in 0.._n1451) {
        _v1450.append(_m_Expression_read(input));
    }
    var _f1452 = _v1450;
    return InvokeExpression(_f1449, _f1452);
}

_m_MakeClosureExpression_write(out: RecordOut, value: MakeClosureExpression) {
    _m_Expression_write(out, value.value);
    out.text(value.closure);
    _m_TypeName_write(out, value.ty);
    out.loc(value.loc);
}

_m_MakeClosureExpression_read(input: RecordIn): MakeClosureExpression {
    var _f1454 = _m_Expression_read(input);
    var _f1455 = input.text();
    var _f1456 = _m_TypeName_read(input);
    var _f1457 = input.loc();
    return MakeClosureExpression(_f1454, _f1455, _f1456, _f1457);
}

_m_CallPointerExpression_write(out: RecordOut, value: CallPointerExpression) {
    _m_Expression_write(out, value.pointer);
    out.unsigned(value.args.count);
    for (var _item1459 in value.args) {
        _m_Expression_write(out, _item1459);
    }
}

_m_CallPointerExpression_read(input: RecordIn): CallPointerExpression {
    var _f1460 = _m_Expression_read(input);
    var _v1461 = Array<Expression>();
    var _n1462 = input.count();
    for (var _ in 0.._n1462) {
        _v1461.append(_m_Expression_read(input));
    }
    var _f1463 = _v1461;
    return CallPointerExpression(_f1460, _f1463);
}

_m_MoveExpression_write(out: RecordOut, value: MoveExpression) {
    _m_Expression_write(out, value.value);
    out.loc(value.loc);
}

_m_MoveExpression_read(input: RecordIn): MoveExpression {
    var _f1466 = _m_Expression_read(input);
    var _f1467 = input.loc();
    return MoveExpression(_f1466, _f1467);
}

_m_DestructureExpression_write(out: RecordOut, value: DestructureExpression) {
    _m_Expression_write(out, value.value);
    out.unsigned(value.count);
    out.loc(value.loc);
}

_m_DestructureExpression_read(input: RecordIn): DestructureExpression {
    var _f1468 = _m_Expression_read(input);
    var _f1469 = input.unsigned();
    var _f1470 = input.loc();
    return DestructureExpression(_f1468, _f1469, _f1470);
}

_m_StaticCaseExpression_write(out: RecordOut, value: StaticCaseExpression) {
    _m_TypeName_write(out, value.ty);
    out.signed(value.tag as long);
}

_m_StaticCaseExpression_read(input: RecordIn): StaticCaseExpression {
    var _f1473 = _m_TypeName_read(input);
    var _f1474 = input.signed();
    return StaticCaseExpression(_f1473, _f1474);
}

_m_StaticStringExpression_write(out: RecordOut, value: StaticStringExpression) {
    out.text(value.value);
    out.loc(value.loc);
}

_m_StaticStringExpression_read(input: RecordIn): StaticStringExpression {
    var _f1475 = input.text();
    var _f1476 = input.loc();
    return StaticStringExpression(_f1475, _f1476);
}

_m_SubjectExpression_write(out: RecordOut, value: SubjectExpression) {
    out.unsigned(value.id);
    _m_TypeName_write(out, value.ty);
    out.loc(value.loc);
}

_m_SubjectExpression_read(input: RecordIn): SubjectExpression {
    var _f1478 = input.unsigned();
    var _f1479 = _m_TypeName_read(input);
    var _f1480 = input.loc();
    return SubjectExpression(_f1478, _f1479, _f1480);
}

_m_ToTraitExpression_write(out: RecordOut, value: ToTraitExpression) {
    _m_Expression_write(out, value.value);
    _m_TypeName_write(out, value.from);
    _m_TypeName_write(out, value.to);
    out.loc(value.loc);
}

_m_ToTraitExpression_read(input: RecordIn): ToTraitExpression {
    var _f1481 = _m_Expression_read(input);
    var _f1482 = _m_TypeName_read(input);
    var _f1483 = _m_TypeName_read(input);
    var _f1484 = input.loc();
    return ToTraitExpression(_f1481, _f1482, _f1483, _f1484);
}

_m_FromTraitExpression_write(out: RecordOut, value: FromTraitExpression) {
    _m_Expression_write(out, value.value);
    _m_TypeName_write(out, value.from);
    _m_TypeName_write(out, value.to);
    out.unsigned(value.candidates.count);
    for (var _item1485 in value.candidates) {
        _m_TypeName_write(out, _item1485);
    }
    out.flag(value.test);
    out.loc(value.loc);
}

_m_FromTraitExpression_read(input: RecordIn): FromTraitExpression {
    var _f1486 = _m_Expression_read(input);
    var _f1487 = _m_TypeName_read(input);
    var _f1488 = _m_TypeName_read(input);
    var _v1489 = Array<TypeName>();
    var _n1490 = input.count();
    for (var _ in 0.._n1490) {
        _v1489.append(_m_TypeName_read(input));
    }
    var _f1491 = _v1489;
    var _f1492 = input.flag();
    var _f1493 = input.loc();
    return FromTraitExpression(_f1486, _f1487, _f1488, _f1491, _f1492, _f1493);
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
        var _f1356 = input.flag();
        return Expression.BoolLiteral(_f1356);
    }
    if (tag == 4) {
        var _f1357 = input.signed();
        return Expression.IntLiteral(_f1357);
    }
    if (tag == 5) {
        var _f1358 = input.number();
        return Expression.FloatLiteral(_f1358);
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
        var _f1383 = _m_TypeName_read(input);
        return Expression.SizeOf(_f1383);
    }
    if (tag == 15) {
        var _f1384 = _m_TypeName_read(input);
        return Expression.IsPod(_f1384);
    }
    if (tag == 16) {
        var _f1385 = _m_TypeName_read(input);
        return Expression.Default(_f1385);
    }
    if (tag == 17) {
        var _f1386 = _m_TypeName_read(input);
        return Expression.Allocate(_f1386);
    }
    if (tag == 18) {
        var _f1387 = _m_TypeName_read(input);
        var _f1388 = _m_Expression_read(input);
        return Expression.RefCount(_f1387, _f1388);
    }
    if (tag == 19) {
        var _f1389 = _m_TypeName_read(input);
        var _f1390 = _m_Expression_read(input);
        return Expression.Address(_f1389, _f1390);
    }
    if (tag == 20) {
        var _f1391 = _m_TypeName_read(input);
        var _f1392 = _m_Expression_read(input);
        return Expression.AtomicLoad(_f1391, _f1392);
    }
    if (tag == 21) {
        var _f1393 = _m_TypeName_read(input);
        var _f1394 = _m_Expression_read(input);
        var _f1395 = _m_Expression_read(input);
        return Expression.AtomicStore(_f1393, _f1394, _f1395);
    }
    if (tag == 22) {
        var _f1396 = _m_Expression_read(input);
        var _f1397 = _m_Expression_read(input);
        return Expression.ConstructAt(_f1396, _f1397);
    }
    if (tag == 23) {
        var _f1398 = _m_TypeName_read(input);
        var _f1399 = _m_Expression_read(input);
        var _f1400 = _m_Expression_read(input);
        var _f1401 = _m_Expression_read(input);
        return Expression.AtomicCmpXchg(_f1398, _f1399, _f1400, _f1401);
    }
    if (tag == 24) {
        var _f1402 = _m_AtomicFetchOp_read(input);
        var _f1403 = _m_TypeName_read(input);
        var _f1404 = _m_Expression_read(input);
        var _f1405 = _m_Expression_read(input);
        return Expression.AtomicFetch(_f1402, _f1403, _f1404, _f1405);
    }
    if (tag == 25) {
        return Expression.Simd(_m_SimdExpression_read(input));
    }
    if (tag == 26) {
        var _f1413 = _m_WeakOp_read(input);
        var _f1414 = _m_TypeName_read(input);
        var _f1415 = _m_Expression_read(input);
        return Expression.Weak(_f1413, _f1414, _f1415);
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
        var _f1453 = _m_ClosureLiteral_read(input);
        return Expression.ClosureLiteral(_f1453);
    }
    if (tag == 36) {
        return Expression.MakeClosure(_m_MakeClosureExpression_read(input));
    }
    if (tag == 37) {
        var _f1458 = input.text();
        return Expression.MethodAddress(_f1458);
    }
    if (tag == 38) {
        return Expression.CallPointer(_m_CallPointerExpression_read(input));
    }
    if (tag == 39) {
        var _f1464 = _m_Expression_read(input);
        return Expression.ForIterator(_f1464);
    }
    if (tag == 40) {
        var _f1465 = _m_Expression_read(input);
        return Expression.WithEntered(_f1465);
    }
    if (tag == 41) {
        return Expression.Move(_m_MoveExpression_read(input));
    }
    if (tag == 42) {
        return Expression.Destructure(_m_DestructureExpression_read(input));
    }
    if (tag == 43) {
        var _f1471 = _m_MatchArmTest_read(input);
        return Expression.MatchArm(_f1471);
    }
    if (tag == 44) {
        var _f1472 = _m_CaseValue_read(input);
        return Expression.CaseValue(_f1472);
    }
    if (tag == 45) {
        return Expression.StaticCase(_m_StaticCaseExpression_read(input));
    }
    if (tag == 46) {
        return Expression.StaticString(_m_StaticStringExpression_read(input));
    }
    if (tag == 47) {
        var _f1477 = _m_WithSubject_read(input);
        return Expression.WithSubject(_f1477);
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
        var _f1494 = _m_StaticValue_read(input);
        return Expression.StaticValue(_f1494);
    }
    if (tag == 53) {
        var _f1495 = _m_StaticMember_read(input);
        return Expression.StaticMember(_f1495);
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
        var _f1496 = _m_VariableDef_read(input);
        return Declaration.Variable(_f1496);
    }
    if (tag == 1) {
        var _f1497 = _m_FunctionDef_read(input);
        return Declaration.Function(_f1497);
    }
    if (tag == 2) {
        var _f1498 = _m_StructDef_read(input);
        return Declaration.Struct(_f1498);
    }
    if (tag == 3) {
        var _f1499 = _m_TraitDef_read(input);
        return Declaration.Trait(_f1499);
    }
    if (tag == 4) {
        var _f1500 = _m_ExtensionDef_read(input);
        return Declaration.Extension(_f1500);
    }
    if (tag == 5) {
        var _f1501 = _m_ExternDef_read(input);
        return Declaration.Extern(_f1501);
    }
    if (tag == 6) {
        var _f1502 = _m_TypeAliasDef_read(input);
        return Declaration.TypeAlias(_f1502);
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
    var _hs1508 = Array<String>();
    for (var _item1503 in value.imports) {
        var scratch = base.scratch();
        _a_Import_write(scratch, _item1503);
        _hs1508.append(base.hash_of(scratch));
    }
    var _seq1509 = base.sequence("imports");
    ulong _bj1510 = 0;
    var _news1511 = Array<ulong>();
    for (var _i1512 in 0.._hs1508.count) {
        if (_bj1510 < _seq1509.count and _hs1508[_i1512] == _seq1509[_bj1510]) {
            _bj1510 += 1;
        } else {
            _news1511.append(_i1512);
        }
    }
    if (_bj1510 == _seq1509.count) {
        out.unsigned(2);
        out.unsigned(_news1511.count);
        for (var _i1512 in _news1511) {
            out.unsigned(_i1512);
            _a_Import_write(out, value.imports[_i1512]);
            {
                var _own1513 = RecordOut();
                _own1513.blank_bodies = true;
                _own1513.blank_locs = true;
                _own1513.pending_as_bytes = true;
                _a_Import_write(_own1513, value.imports[_i1512]);
                base.own("imports", interface_text(_own1513));
            }
        }
        base.count("imports" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("imports" + " whole", 0);
        out.unsigned(value.imports.count);
        for (var _i1512 in 0..value.imports.count) {
            _a_Import_write(out, value.imports[_i1512]);
            {
                var _own1514 = RecordOut();
                _own1514.blank_bodies = true;
                _own1514.blank_locs = true;
                _own1514.pending_as_bytes = true;
                _a_Import_write(_own1514, value.imports[_i1512]);
                base.own("imports", interface_text(_own1514));
            }
        }
    }
    base.stat("imports", out.values.count - _mark);
    _mark = out.values.count;
    var _seq1524 = base.ref_structs;
    ulong _bj1525 = 0;
    var _news1527 = Array<ulong>();
    var _patches1528 = Array<(ulong, ulong)>();
    for (var _i1529 in 0..value.structs.count) {
        if (_bj1525 < _seq1524.count
            and value.structs[_i1529] === _seq1524[_bj1525]
            and !value.extended_checked.contains(value.structs[_i1529].name)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_StructDef_write(scratch, value.structs[_i1529]);
                base.verify_same("s", _bj1525, scratch, value.structs[_i1529].name);
            }
            _bj1525 += 1;
        } else if (_bj1525 < _seq1524.count
            and !(value.structs[_i1529] === _seq1524[_bj1525])
            and _same_m_StructDef(value.structs[_i1529], _seq1524[_bj1525], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_StructDef_write(scratch, value.structs[_i1529]);
                base.verify_same("s", _bj1525, scratch, value.structs[_i1529].name);
            }
            _bj1525 += 1;
        } else if (_bj1525 < _seq1524.count and value.structs[_i1529].name == _seq1524[_bj1525].name) {
            _patches1528.append((_i1529, _bj1525));
            _bj1525 += 1;
        } else {
            _news1527.append(_i1529);
        }
    }
    if (_bj1525 == _seq1524.count) {
        out.unsigned(2);
        out.unsigned(_patches1528.count);
        for (var (_i1529, _b) in _patches1528) {
            ulong _before = out.values.count;
            out.text(value.structs[_i1529].name);
            out.unsigned(_b);
            _patch_s_write(out, value.structs[_i1529], base, _b);
            base.count("s patched", out.values.count - _before);
            {
                var _own1530 = RecordOut();
                _own1530.blank_bodies = true;
                _own1530.blank_locs = true;
                _own1530.pending_as_bytes = true;
                var _s1531 = value.structs[_i1529];
                var _methods1532 = _s1531.method_members;
                _s1531.method_members = Array<FunctionDef>();
                var _fields1533 = _s1531.field_members;
                var split__fields1533 = splits_fields(_s1531);
                if (split__fields1533) {
                    _s1531.field_members = Array<VariableDef>();
                }
                _m_StructDef_write(_own1530, _s1531);
                _s1531.method_members = _methods1532;
                _s1531.field_members = _fields1533;
                base.own_named("structs", _s1531.name, interface_text(_own1530));
                for (var _m1534 in _methods1532) {
                    var _own1535 = RecordOut();
                    _own1535.blank_bodies = true;
                    _own1535.blank_locs = true;
                    _own1535.pending_as_bytes = true;
                    _m_FunctionDef_write(_own1535, _m1534);
                    base.own_method("structs", _s1531.name, _m1534.name, interface_text(_own1535));
                }
                if (_s1531.is_value()) {
                    for (var _m1534 in _s1531.constructors) {
                        var _own1535 = RecordOut();
                        _own1535.blank_locs = true;
                        _own1535.pending_as_bytes = true;
                        _m_FunctionDef_write(_own1535, _m1534);
                        base.own_method("structs", _s1531.name, "__ctor", interface_text(_own1535));
                    }
                }
                if (split__fields1533) {
                    var _order1537 = StringBuilder();
                    for (var _f1536 in _fields1533) {
                        var _own1538 = RecordOut();
                        _own1538.blank_locs = true;
                        _m_VariableDef_write(_own1538, _f1536);
                        base.own_method("structs", _s1531.name, "." + _f1536.name, interface_text(_own1538));
                        _order1537.append(_f1536.name);
                        _order1537.append(",");
                    }
                    base.own_method("structs", _s1531.name, ".#order", _order1537.to_string());
                }
            }
        }
        out.unsigned(_news1527.count);
        for (var _i1529 in _news1527) {
            ulong _before = out.values.count;
            out.unsigned(_i1529);
            _m_StructDef_write(out, value.structs[_i1529]);
            base.count("s new", out.values.count - _before);
            {
                var _own1539 = RecordOut();
                _own1539.blank_bodies = true;
                _own1539.blank_locs = true;
                _own1539.pending_as_bytes = true;
                var _s1540 = value.structs[_i1529];
                var _methods1541 = _s1540.method_members;
                _s1540.method_members = Array<FunctionDef>();
                var _fields1542 = _s1540.field_members;
                var split__fields1542 = splits_fields(_s1540);
                if (split__fields1542) {
                    _s1540.field_members = Array<VariableDef>();
                }
                _m_StructDef_write(_own1539, _s1540);
                _s1540.method_members = _methods1541;
                _s1540.field_members = _fields1542;
                base.own_named("structs", _s1540.name, interface_text(_own1539));
                for (var _m1543 in _methods1541) {
                    var _own1544 = RecordOut();
                    _own1544.blank_bodies = true;
                    _own1544.blank_locs = true;
                    _own1544.pending_as_bytes = true;
                    _m_FunctionDef_write(_own1544, _m1543);
                    base.own_method("structs", _s1540.name, _m1543.name, interface_text(_own1544));
                }
                if (_s1540.is_value()) {
                    for (var _m1543 in _s1540.constructors) {
                        var _own1544 = RecordOut();
                        _own1544.blank_locs = true;
                        _own1544.pending_as_bytes = true;
                        _m_FunctionDef_write(_own1544, _m1543);
                        base.own_method("structs", _s1540.name, "__ctor", interface_text(_own1544));
                    }
                }
                if (split__fields1542) {
                    var _order1546 = StringBuilder();
                    for (var _f1545 in _fields1542) {
                        var _own1547 = RecordOut();
                        _own1547.blank_locs = true;
                        _m_VariableDef_write(_own1547, _f1545);
                        base.own_method("structs", _s1540.name, "." + _f1545.name, interface_text(_own1547));
                        _order1546.append(_f1545.name);
                        _order1546.append(",");
                    }
                    base.own_method("structs", _s1540.name, ".#order", _order1546.to_string());
                }
            }
        }
        base.count("s merged", 0);
    } else {
        out.unsigned(1);
        base.count("s by place", 0);
        var _struct_hits1523 = HashSet<long>();
        var _slots1526 = HashMap<String, long>();
        for (var _i1529 in 0.._seq1524.count) {
            if (!_slots1526.contains(_seq1524[_i1529].name)) {
                _slots1526[_seq1524[_i1529].name] = _i1529 as long;
            }
        }
        out.unsigned(value.structs.count);
        for (var _i1529 in 0..value.structs.count) {
            var _item1522 = value.structs[_i1529];
            var _slot = _slots1526.try_get(_item1522.name);
            long named = _slot.is_value() ? _slot.value() : -1;
            long at = -1;
            if (named >= 0
                and _seq1524[named as ulong] === _item1522
                and !value.extended_checked.contains(_item1522.name)) {
                at = named;
            }
            ulong _before = out.values.count;
            if (at >= 0) {
                _struct_hits1523.insert(at);
                out.unsigned((at as ulong) * 2 + 1);
            } else if (named >= 0) {
                _struct_hits1523.insert(named);
                out.unsigned(2);
                out.unsigned(named as ulong);
                _patch_s_write(out, _item1522, base, named as ulong);
                base.count("s patched", out.values.count - _before);
            } else {
                out.unsigned(0);
                _m_StructDef_write(out, _item1522);
                base.count("s new", out.values.count - _before);
            }
        }
        base.missed("s", "s", _struct_hits1523.count);
    }
    base.stat("structs", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1561 = Array<String>();
    for (var _item1556 in value.traits) {
        var scratch = base.scratch();
        _m_TraitDef_write(scratch, _item1556);
        _hs1561.append(base.hash_of(scratch));
    }
    var _seq1562 = base.sequence("traits");
    ulong _bj1563 = 0;
    var _news1564 = Array<ulong>();
    for (var _i1565 in 0.._hs1561.count) {
        if (_bj1563 < _seq1562.count and _hs1561[_i1565] == _seq1562[_bj1563]) {
            _bj1563 += 1;
        } else {
            _news1564.append(_i1565);
        }
    }
    if (_bj1563 == _seq1562.count) {
        out.unsigned(2);
        out.unsigned(_news1564.count);
        for (var _i1565 in _news1564) {
            out.unsigned(_i1565);
            _m_TraitDef_write(out, value.traits[_i1565]);
            {
                var _own1566 = RecordOut();
                _own1566.blank_bodies = false;
                _own1566.blank_locs = true;
                _own1566.pending_as_bytes = true;
                _m_TraitDef_write(_own1566, value.traits[_i1565]);
                base.own("traits", interface_text(_own1566));
            }
        }
        base.count("traits" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("traits" + " whole", 0);
        out.unsigned(value.traits.count);
        for (var _i1565 in 0..value.traits.count) {
            _m_TraitDef_write(out, value.traits[_i1565]);
            {
                var _own1567 = RecordOut();
                _own1567.blank_bodies = false;
                _own1567.blank_locs = true;
                _own1567.pending_as_bytes = true;
                _m_TraitDef_write(_own1567, value.traits[_i1565]);
                base.own("traits", interface_text(_own1567));
            }
        }
    }
    base.stat("traits", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1580 = Array<String>();
    for (var _item1575 in value.extensions) {
        var scratch = base.scratch();
        _m_ExtensionDef_write(scratch, _item1575);
        _hs1580.append(base.hash_of(scratch));
    }
    var _seq1581 = base.sequence("extensions");
    ulong _bj1582 = 0;
    var _news1583 = Array<ulong>();
    for (var _i1584 in 0.._hs1580.count) {
        if (_bj1582 < _seq1581.count and _hs1580[_i1584] == _seq1581[_bj1582]) {
            _bj1582 += 1;
        } else {
            _news1583.append(_i1584);
        }
    }
    if (_bj1582 == _seq1581.count) {
        out.unsigned(2);
        out.unsigned(_news1583.count);
        for (var _i1584 in _news1583) {
            out.unsigned(_i1584);
            _m_ExtensionDef_write(out, value.extensions[_i1584]);
            {
                var _own1585 = RecordOut();
                _own1585.blank_bodies = true;
                _own1585.blank_locs = true;
                _own1585.pending_as_bytes = true;
                _m_ExtensionDef_write(_own1585, value.extensions[_i1584]);
                base.own("extensions", interface_text(_own1585));
            }
        }
        base.count("extensions" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("extensions" + " whole", 0);
        out.unsigned(value.extensions.count);
        for (var _i1584 in 0..value.extensions.count) {
            _m_ExtensionDef_write(out, value.extensions[_i1584]);
            {
                var _own1586 = RecordOut();
                _own1586.blank_bodies = true;
                _own1586.blank_locs = true;
                _own1586.pending_as_bytes = true;
                _m_ExtensionDef_write(_own1586, value.extensions[_i1584]);
                base.own("extensions", interface_text(_own1586));
            }
        }
    }
    base.stat("extensions", out.values.count - _mark);
    _mark = out.values.count;
    var _seq1599 = base.ref_functions;
    ulong _bj1600 = 0;
    var _news1601 = Array<ulong>();
    var _changed1595 = Array<(ulong, ulong)>();
    for (var _i1602 in 0..value.functions.count) {
        if (_bj1600 < _seq1599.count and value.functions[_i1602] === _seq1599[_bj1600]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.functions[_i1602]);
                base.verify_same("functions", _bj1600, scratch);
            }
            _bj1600 += 1;
        } else if (_bj1600 < _seq1599.count and _same_m_FunctionDef(value.functions[_i1602], _seq1599[_bj1600], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.functions[_i1602]);
                base.verify_same("functions", _bj1600, scratch);
            }
            _bj1600 += 1;
        } else if (_bj1600 < _seq1599.count and value.functions[_i1602].name == _seq1599[_bj1600].name) {
            _changed1595.append((_i1602, _bj1600));
            _bj1600 += 1;
        } else {
            _news1601.append(_i1602);
        }
    }
    if (_bj1600 == _seq1599.count) {
        out.unsigned(2);
        out.unsigned(_changed1595.count);
        for (var (_i1602, _b) in _changed1595) {
            out.text(value.functions[_i1602].name);
            out.unsigned(_b);
            _m_FunctionDef_write(out, value.functions[_i1602]);
            {
                var _own1603 = RecordOut();
                _own1603.blank_bodies = true;
                _own1603.blank_locs = true;
                _own1603.pending_as_bytes = true;
                _m_FunctionDef_write(_own1603, value.functions[_i1602]);
                base.own_function("functions", value.functions[_i1602], interface_text(_own1603));
            }
        }
        base.count("functions" + " changed", _changed1595.count);
        out.unsigned(_news1601.count);
        for (var _i1602 in _news1601) {
            out.unsigned(_i1602);
            _m_FunctionDef_write(out, value.functions[_i1602]);
            {
                var _own1604 = RecordOut();
                _own1604.blank_bodies = true;
                _own1604.blank_locs = true;
                _own1604.pending_as_bytes = true;
                _m_FunctionDef_write(_own1604, value.functions[_i1602]);
                base.own_function("functions", value.functions[_i1602], interface_text(_own1604));
            }
        }
        base.count("functions" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("functions" + " whole", 0);
        out.unsigned(value.functions.count);
        for (var _i1602 in 0..value.functions.count) {
            _m_FunctionDef_write(out, value.functions[_i1602]);
            {
                var _own1605 = RecordOut();
                _own1605.blank_bodies = true;
                _own1605.blank_locs = true;
                _own1605.pending_as_bytes = true;
                _m_FunctionDef_write(_own1605, value.functions[_i1602]);
                base.own_function("functions", value.functions[_i1602], interface_text(_own1605));
            }
        }
    }
    base.stat("functions", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1618 = Array<String>();
    for (var _item1613 in value.externs) {
        var scratch = base.scratch();
        _m_ExternDef_write(scratch, _item1613);
        _hs1618.append(base.hash_of(scratch));
    }
    var _seq1619 = base.sequence("externs");
    ulong _bj1620 = 0;
    var _news1621 = Array<ulong>();
    for (var _i1622 in 0.._hs1618.count) {
        if (_bj1620 < _seq1619.count and _hs1618[_i1622] == _seq1619[_bj1620]) {
            _bj1620 += 1;
        } else {
            _news1621.append(_i1622);
        }
    }
    if (_bj1620 == _seq1619.count) {
        out.unsigned(2);
        out.unsigned(_news1621.count);
        for (var _i1622 in _news1621) {
            out.unsigned(_i1622);
            _m_ExternDef_write(out, value.externs[_i1622]);
            {
                var _own1623 = RecordOut();
                _own1623.blank_bodies = true;
                _own1623.blank_locs = true;
                _own1623.pending_as_bytes = true;
                _m_ExternDef_write(_own1623, value.externs[_i1622]);
                base.own("externs", interface_text(_own1623));
            }
        }
        base.count("externs" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("externs" + " whole", 0);
        out.unsigned(value.externs.count);
        for (var _i1622 in 0..value.externs.count) {
            _m_ExternDef_write(out, value.externs[_i1622]);
            {
                var _own1624 = RecordOut();
                _own1624.blank_bodies = true;
                _own1624.blank_locs = true;
                _own1624.pending_as_bytes = true;
                _m_ExternDef_write(_own1624, value.externs[_i1622]);
                base.own("externs", interface_text(_own1624));
            }
        }
    }
    base.stat("externs", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1637 = Array<String>();
    for (var _item1632 in value.globals) {
        var scratch = base.scratch();
        _m_VariableDef_write(scratch, _item1632);
        _hs1637.append(base.hash_of(scratch));
    }
    var _seq1638 = base.sequence("globals");
    ulong _bj1639 = 0;
    var _news1640 = Array<ulong>();
    for (var _i1641 in 0.._hs1637.count) {
        if (_bj1639 < _seq1638.count and _hs1637[_i1641] == _seq1638[_bj1639]) {
            _bj1639 += 1;
        } else {
            _news1640.append(_i1641);
        }
    }
    if (_bj1639 == _seq1638.count) {
        out.unsigned(2);
        out.unsigned(_news1640.count);
        for (var _i1641 in _news1640) {
            out.unsigned(_i1641);
            _m_VariableDef_write(out, value.globals[_i1641]);
            {
                var _own1642 = RecordOut();
                _own1642.blank_bodies = true;
                _own1642.blank_locs = true;
                _own1642.pending_as_bytes = true;
                _m_VariableDef_write(_own1642, value.globals[_i1641]);
                base.own("globals", interface_text(_own1642));
            }
        }
        base.count("globals" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("globals" + " whole", 0);
        out.unsigned(value.globals.count);
        for (var _i1641 in 0..value.globals.count) {
            _m_VariableDef_write(out, value.globals[_i1641]);
            {
                var _own1643 = RecordOut();
                _own1643.blank_bodies = true;
                _own1643.blank_locs = true;
                _own1643.pending_as_bytes = true;
                _m_VariableDef_write(_own1643, value.globals[_i1641]);
                base.own("globals", interface_text(_own1643));
            }
        }
    }
    base.stat("globals", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1656 = Array<String>();
    for (var _item1651 in value.static_blocks) {
        var scratch = base.scratch();
        _m_ModuleStaticBlock_write(scratch, _item1651);
        _hs1656.append(base.hash_of(scratch));
    }
    var _seq1657 = base.sequence("static_blocks");
    ulong _bj1658 = 0;
    var _news1659 = Array<ulong>();
    for (var _i1660 in 0.._hs1656.count) {
        if (_bj1658 < _seq1657.count and _hs1656[_i1660] == _seq1657[_bj1658]) {
            _bj1658 += 1;
        } else {
            _news1659.append(_i1660);
        }
    }
    if (_bj1658 == _seq1657.count) {
        out.unsigned(2);
        out.unsigned(_news1659.count);
        for (var _i1660 in _news1659) {
            out.unsigned(_i1660);
            _m_ModuleStaticBlock_write(out, value.static_blocks[_i1660]);
            {
                var _own1661 = RecordOut();
                _own1661.blank_bodies = true;
                _own1661.blank_locs = true;
                _own1661.pending_as_bytes = true;
                _m_ModuleStaticBlock_write(_own1661, value.static_blocks[_i1660]);
                base.own("static_blocks", interface_text(_own1661));
            }
        }
        base.count("static_blocks" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("static_blocks" + " whole", 0);
        out.unsigned(value.static_blocks.count);
        for (var _i1660 in 0..value.static_blocks.count) {
            _m_ModuleStaticBlock_write(out, value.static_blocks[_i1660]);
            {
                var _own1662 = RecordOut();
                _own1662.blank_bodies = true;
                _own1662.blank_locs = true;
                _own1662.pending_as_bytes = true;
                _m_ModuleStaticBlock_write(_own1662, value.static_blocks[_i1660]);
                base.own("static_blocks", interface_text(_own1662));
            }
        }
    }
    base.stat("static_blocks", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1675 = Array<String>();
    for (var _item1670 in value.enums) {
        var scratch = base.scratch();
        _m_EnumDef_write(scratch, _item1670);
        _hs1675.append(base.hash_of(scratch));
    }
    var _seq1676 = base.sequence("enums");
    ulong _bj1677 = 0;
    var _news1678 = Array<ulong>();
    for (var _i1679 in 0.._hs1675.count) {
        if (_bj1677 < _seq1676.count and _hs1675[_i1679] == _seq1676[_bj1677]) {
            _bj1677 += 1;
        } else {
            _news1678.append(_i1679);
        }
    }
    if (_bj1677 == _seq1676.count) {
        out.unsigned(2);
        out.unsigned(_news1678.count);
        for (var _i1679 in _news1678) {
            out.unsigned(_i1679);
            _m_EnumDef_write(out, value.enums[_i1679]);
            {
                var _own1680 = RecordOut();
                _own1680.blank_bodies = true;
                _own1680.blank_locs = true;
                _own1680.pending_as_bytes = true;
                _m_EnumDef_write(_own1680, value.enums[_i1679]);
                base.own_named("enums", value.enums[_i1679].name, interface_text(_own1680));
            }
        }
        base.count("enums" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("enums" + " whole", 0);
        out.unsigned(value.enums.count);
        for (var _i1679 in 0..value.enums.count) {
            _m_EnumDef_write(out, value.enums[_i1679]);
            {
                var _own1681 = RecordOut();
                _own1681.blank_bodies = true;
                _own1681.blank_locs = true;
                _own1681.pending_as_bytes = true;
                _m_EnumDef_write(_own1681, value.enums[_i1679]);
                base.own_named("enums", value.enums[_i1679].name, interface_text(_own1681));
            }
        }
    }
    base.stat("enums", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1694 = Array<String>();
    for (var _item1689 in value.struct_specs) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item1689);
        _hs1694.append(base.hash_of(scratch));
    }
    var _seq1695 = base.sequence("struct_specs");
    ulong _bj1696 = 0;
    var _news1697 = Array<ulong>();
    for (var _i1698 in 0.._hs1694.count) {
        if (_bj1696 < _seq1695.count and _hs1694[_i1698] == _seq1695[_bj1696]) {
            _bj1696 += 1;
        } else {
            _news1697.append(_i1698);
        }
    }
    if (_bj1696 == _seq1695.count) {
        out.unsigned(2);
        out.unsigned(_news1697.count);
        for (var _i1698 in _news1697) {
            out.unsigned(_i1698);
            _m_TypeName_write(out, value.struct_specs[_i1698]);
            {
                var _own1699 = RecordOut();
                _own1699.blank_bodies = true;
                _own1699.blank_locs = true;
                _own1699.pending_as_bytes = true;
                _m_TypeName_write(_own1699, value.struct_specs[_i1698]);
                base.own("struct_specs", interface_text(_own1699));
            }
        }
        base.count("struct_specs" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("struct_specs" + " whole", 0);
        out.unsigned(value.struct_specs.count);
        for (var _i1698 in 0..value.struct_specs.count) {
            _m_TypeName_write(out, value.struct_specs[_i1698]);
            {
                var _own1700 = RecordOut();
                _own1700.blank_bodies = true;
                _own1700.blank_locs = true;
                _own1700.pending_as_bytes = true;
                _m_TypeName_write(_own1700, value.struct_specs[_i1698]);
                base.own("struct_specs", interface_text(_own1700));
            }
        }
    }
    base.stat("struct_specs", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1713 = Array<String>();
    for (var _item1708 in value.func_specs) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item1708);
        _hs1713.append(base.hash_of(scratch));
    }
    var _seq1714 = base.sequence("func_specs");
    ulong _bj1715 = 0;
    var _news1716 = Array<ulong>();
    for (var _i1717 in 0.._hs1713.count) {
        if (_bj1715 < _seq1714.count and _hs1713[_i1717] == _seq1714[_bj1715]) {
            _bj1715 += 1;
        } else {
            _news1716.append(_i1717);
        }
    }
    if (_bj1715 == _seq1714.count) {
        out.unsigned(2);
        out.unsigned(_news1716.count);
        for (var _i1717 in _news1716) {
            out.unsigned(_i1717);
            _m_TypeName_write(out, value.func_specs[_i1717]);
            {
                var _own1718 = RecordOut();
                _own1718.blank_bodies = true;
                _own1718.blank_locs = true;
                _own1718.pending_as_bytes = true;
                _m_TypeName_write(_own1718, value.func_specs[_i1717]);
                base.own("func_specs", interface_text(_own1718));
            }
        }
        base.count("func_specs" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("func_specs" + " whole", 0);
        out.unsigned(value.func_specs.count);
        for (var _i1717 in 0..value.func_specs.count) {
            _m_TypeName_write(out, value.func_specs[_i1717]);
            {
                var _own1719 = RecordOut();
                _own1719.blank_bodies = true;
                _own1719.blank_locs = true;
                _own1719.pending_as_bytes = true;
                _m_TypeName_write(_own1719, value.func_specs[_i1717]);
                base.own("func_specs", interface_text(_own1719));
            }
        }
    }
    base.stat("func_specs", out.values.count - _mark);
    _mark = out.values.count;
    var _hits1731 = HashSet<long>();
    out.unsigned(value.type_aliases.count);
    for (var _item1727 in value.type_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1727);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed("type_aliases", hash);
        if (at >= 0) {
            _hits1731.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_TypeAliasDef_write(out, _item1727);
        }
    }
    base.missed("type_aliases", "type_aliases", _hits1731.count);
    base.stat("type_aliases", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1741 = Array<String>();
    for (var _item1736 in value.withheld) {
        var scratch = base.scratch();
        _m_Withheld_write(scratch, _item1736);
        _hs1741.append(base.hash_of(scratch));
    }
    var _seq1742 = base.sequence("withheld");
    ulong _bj1743 = 0;
    var _news1744 = Array<ulong>();
    for (var _i1745 in 0.._hs1741.count) {
        if (_bj1743 < _seq1742.count and _hs1741[_i1745] == _seq1742[_bj1743]) {
            _bj1743 += 1;
        } else {
            _news1744.append(_i1745);
        }
    }
    if (_bj1743 == _seq1742.count) {
        out.unsigned(2);
        out.unsigned(_news1744.count);
        for (var _i1745 in _news1744) {
            out.unsigned(_i1745);
            _m_Withheld_write(out, value.withheld[_i1745]);
            {
                var _own1746 = RecordOut();
                _own1746.blank_bodies = true;
                _own1746.blank_locs = true;
                _own1746.pending_as_bytes = true;
                _m_Withheld_write(_own1746, value.withheld[_i1745]);
                base.own("withheld", interface_text(_own1746));
            }
        }
        base.count("withheld" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("withheld" + " whole", 0);
        out.unsigned(value.withheld.count);
        for (var _i1745 in 0..value.withheld.count) {
            _m_Withheld_write(out, value.withheld[_i1745]);
            {
                var _own1747 = RecordOut();
                _own1747.blank_bodies = true;
                _own1747.blank_locs = true;
                _own1747.pending_as_bytes = true;
                _m_Withheld_write(_own1747, value.withheld[_i1745]);
                base.own("withheld", interface_text(_own1747));
            }
        }
    }
    base.stat("withheld", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1760 = Array<String>();
    for (var _item1755 in value.properties) {
        var scratch = base.scratch();
        _m_PropertyDef_write(scratch, _item1755);
        _hs1760.append(base.hash_of(scratch));
    }
    var _seq1761 = base.sequence("properties");
    ulong _bj1762 = 0;
    var _news1763 = Array<ulong>();
    for (var _i1764 in 0.._hs1760.count) {
        if (_bj1762 < _seq1761.count and _hs1760[_i1764] == _seq1761[_bj1762]) {
            _bj1762 += 1;
        } else {
            _news1763.append(_i1764);
        }
    }
    if (_bj1762 == _seq1761.count) {
        out.unsigned(2);
        out.unsigned(_news1763.count);
        for (var _i1764 in _news1763) {
            out.unsigned(_i1764);
            _m_PropertyDef_write(out, value.properties[_i1764]);
            {
                var _own1765 = RecordOut();
                _own1765.blank_bodies = true;
                _own1765.blank_locs = true;
                _own1765.pending_as_bytes = true;
                _m_PropertyDef_write(_own1765, value.properties[_i1764]);
                base.own("properties", interface_text(_own1765));
            }
        }
        base.count("properties" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("properties" + " whole", 0);
        out.unsigned(value.properties.count);
        for (var _i1764 in 0..value.properties.count) {
            _m_PropertyDef_write(out, value.properties[_i1764]);
            {
                var _own1766 = RecordOut();
                _own1766.blank_bodies = true;
                _own1766.blank_locs = true;
                _own1766.pending_as_bytes = true;
                _m_PropertyDef_write(_own1766, value.properties[_i1764]);
                base.own("properties", interface_text(_own1766));
            }
        }
    }
    base.stat("properties", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1779 = Array<String>();
    for (var _item1774 in value.type_uses) {
        var scratch = base.scratch();
        _m_TypeUse_write(scratch, _item1774);
        _hs1779.append(base.hash_of(scratch));
    }
    var _seq1780 = base.sequence("type_uses");
    ulong _bj1781 = 0;
    var _news1782 = Array<ulong>();
    for (var _i1783 in 0.._hs1779.count) {
        if (_bj1781 < _seq1780.count and _hs1779[_i1783] == _seq1780[_bj1781]) {
            _bj1781 += 1;
        } else {
            _news1782.append(_i1783);
        }
    }
    if (_bj1781 == _seq1780.count) {
        out.unsigned(2);
        out.unsigned(_news1782.count);
        for (var _i1783 in _news1782) {
            out.unsigned(_i1783);
            _m_TypeUse_write(out, value.type_uses[_i1783]);
            {
                var _own1784 = RecordOut();
                _own1784.blank_bodies = true;
                _own1784.blank_locs = true;
                _own1784.pending_as_bytes = true;
                _m_TypeUse_write(_own1784, value.type_uses[_i1783]);
                base.own("type_uses", interface_text(_own1784));
            }
        }
        base.count("type_uses" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("type_uses" + " whole", 0);
        out.unsigned(value.type_uses.count);
        for (var _i1783 in 0..value.type_uses.count) {
            _m_TypeUse_write(out, value.type_uses[_i1783]);
            {
                var _own1785 = RecordOut();
                _own1785.blank_bodies = true;
                _own1785.blank_locs = true;
                _own1785.pending_as_bytes = true;
                _m_TypeUse_write(_own1785, value.type_uses[_i1783]);
                base.own("type_uses", interface_text(_own1785));
            }
        }
    }
    base.stat("type_uses", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1798 = Array<String>();
    for (var _item1793 in value.use_contexts) {
        var scratch = base.scratch();
        _m_UseContext_write(scratch, _item1793);
        _hs1798.append(base.hash_of(scratch));
    }
    var _seq1799 = base.sequence("use_contexts");
    ulong _bj1800 = 0;
    var _news1801 = Array<ulong>();
    for (var _i1802 in 0.._hs1798.count) {
        if (_bj1800 < _seq1799.count and _hs1798[_i1802] == _seq1799[_bj1800]) {
            _bj1800 += 1;
        } else {
            _news1801.append(_i1802);
        }
    }
    if (_bj1800 == _seq1799.count) {
        out.unsigned(2);
        out.unsigned(_news1801.count);
        for (var _i1802 in _news1801) {
            out.unsigned(_i1802);
            _m_UseContext_write(out, value.use_contexts[_i1802]);
            {
                var _own1803 = RecordOut();
                _own1803.blank_bodies = true;
                _own1803.blank_locs = true;
                _own1803.pending_as_bytes = true;
                _m_UseContext_write(_own1803, value.use_contexts[_i1802]);
                base.own("use_contexts", interface_text(_own1803));
            }
        }
        base.count("use_contexts" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("use_contexts" + " whole", 0);
        out.unsigned(value.use_contexts.count);
        for (var _i1802 in 0..value.use_contexts.count) {
            _m_UseContext_write(out, value.use_contexts[_i1802]);
            {
                var _own1804 = RecordOut();
                _own1804.blank_bodies = true;
                _own1804.blank_locs = true;
                _own1804.pending_as_bytes = true;
                _m_UseContext_write(_own1804, value.use_contexts[_i1802]);
                base.own("use_contexts", interface_text(_own1804));
            }
        }
    }
    base.stat("use_contexts", out.values.count - _mark);
    _mark = out.values.count;
    var _n1814 = base.size("literal_args");
    var _scratch1813 = base.scratch();
    if (value.literal_args.count >= _n1814) {
        for (var _i1815 in 0.._n1814) {
            var (_t1816, _t1817, _t1818) = value.literal_args[_i1815];
            _scratch1813.loc(_t1816);
            _scratch1813.unsigned(_t1817);
            _scratch1813.loc(_t1818);
        }
    }
    if (value.literal_args.count >= _n1814 and base.same_list("literal_args", _scratch1813)) {
        out.unsigned(1);
        out.unsigned(_n1814);
        out.unsigned(value.literal_args.count - _n1814);
        for (var _i1815 in _n1814..value.literal_args.count) {
            var (_t1819, _t1820, _t1821) = value.literal_args[_i1815];
            out.loc(_t1819);
            out.unsigned(_t1820);
            out.loc(_t1821);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.literal_args.count);
        for (var _item1822 in value.literal_args) {
            var (_t1823, _t1824, _t1825) = _item1822;
            out.loc(_t1823);
            out.unsigned(_t1824);
            out.loc(_t1825);
        }
        base.count("literal_args whole", 0);
    }
    base.stat("literal_args", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1848 = Array<String>();
    for (var _item1843 in value.constrained_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1843);
        _hs1848.append(base.hash_of(scratch));
    }
    var _seq1849 = base.sequence("constrained_aliases");
    ulong _bj1850 = 0;
    var _news1851 = Array<ulong>();
    for (var _i1852 in 0.._hs1848.count) {
        if (_bj1850 < _seq1849.count and _hs1848[_i1852] == _seq1849[_bj1850]) {
            _bj1850 += 1;
        } else {
            _news1851.append(_i1852);
        }
    }
    if (_bj1850 == _seq1849.count) {
        out.unsigned(2);
        out.unsigned(_news1851.count);
        for (var _i1852 in _news1851) {
            out.unsigned(_i1852);
            _m_TypeAliasDef_write(out, value.constrained_aliases[_i1852]);
            {
                var _own1853 = RecordOut();
                _own1853.blank_bodies = true;
                _own1853.blank_locs = true;
                _own1853.pending_as_bytes = true;
                _m_TypeAliasDef_write(_own1853, value.constrained_aliases[_i1852]);
                base.own("constrained_aliases", interface_text(_own1853));
            }
        }
        base.count("constrained_aliases" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("constrained_aliases" + " whole", 0);
        out.unsigned(value.constrained_aliases.count);
        for (var _i1852 in 0..value.constrained_aliases.count) {
            _m_TypeAliasDef_write(out, value.constrained_aliases[_i1852]);
            {
                var _own1854 = RecordOut();
                _own1854.blank_bodies = true;
                _own1854.blank_locs = true;
                _own1854.pending_as_bytes = true;
                _m_TypeAliasDef_write(_own1854, value.constrained_aliases[_i1852]);
                base.own("constrained_aliases", interface_text(_own1854));
            }
        }
    }
    base.stat("constrained_aliases", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1867 = Array<String>();
    for (var _item1862 in value.trait_types) {
        var scratch = base.scratch();
        _m_TraitType_write(scratch, _item1862);
        _hs1867.append(base.hash_of(scratch));
    }
    var _seq1868 = base.sequence("trait_types");
    ulong _bj1869 = 0;
    var _news1870 = Array<ulong>();
    for (var _i1871 in 0.._hs1867.count) {
        if (_bj1869 < _seq1868.count and _hs1867[_i1871] == _seq1868[_bj1869]) {
            _bj1869 += 1;
        } else {
            _news1870.append(_i1871);
        }
    }
    if (_bj1869 == _seq1868.count) {
        out.unsigned(2);
        out.unsigned(_news1870.count);
        for (var _i1871 in _news1870) {
            out.unsigned(_i1871);
            _m_TraitType_write(out, value.trait_types[_i1871]);
            {
                var _own1872 = RecordOut();
                _own1872.blank_bodies = true;
                _own1872.blank_locs = true;
                _own1872.pending_as_bytes = true;
                _m_TraitType_write(_own1872, value.trait_types[_i1871]);
                base.own("trait_types", interface_text(_own1872));
            }
        }
        base.count("trait_types" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("trait_types" + " whole", 0);
        out.unsigned(value.trait_types.count);
        for (var _i1871 in 0..value.trait_types.count) {
            _m_TraitType_write(out, value.trait_types[_i1871]);
            {
                var _own1873 = RecordOut();
                _own1873.blank_bodies = true;
                _own1873.blank_locs = true;
                _own1873.pending_as_bytes = true;
                _m_TraitType_write(_own1873, value.trait_types[_i1871]);
                base.own("trait_types", interface_text(_own1873));
            }
        }
    }
    base.stat("trait_types", out.values.count - _mark);
    _mark = out.values.count;
    out.unsigned(value.conversions.count);
    for (var _item1881 in value.conversions) {
        _m_Conversion_write(out, _item1881);
    }
    for (var _conv1882 in value.conversions) {
        var _own1883 = RecordOut();
        _own1883.blank_locs = true;
        _m_Conversion_write(_own1883, _conv1882);
        var _h = interface_text(_own1883);
        if (base.find_hashed("conversions", _h) < 0) {
            base.own("conversions", _h);
        }
    }
    base.stat("conversions", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept1891 = 0;
    var _news1892 = Map<String, Array<String>>();
    for (var (_key1888, _) in value.overload_sets) {
        var _kscratch1889 = base.scratch();
        _kscratch1889.text(_key1888);
        var _vscratch1890 = base.scratch();
        _vscratch1890.unsigned(value.overload_sets[_key1888].count);
        for (var _item1893 in value.overload_sets[_key1888]) {
            _vscratch1890.text(_item1893);
        }
        var _had = base.entry("overload_sets", _kscratch1889, _vscratch1890);
        if (_had >= 0) {
            _kept1891 += 1;
        }
        if (_had != 1) {
            _news1892[_key1888] = value.overload_sets[_key1888];
        }
    }
    if (_kept1891 == base.size("overload_sets")) {
        out.unsigned(1);
        var _keys1895 = Array<(u8[], u8[], String)>();
        for (var (_key1894, _) in _news1892) {
            var _scratch1896 = out.scratch();
            _scratch1896.text(_key1894);
            var _vscratch1898 = out.scratch();
            _vscratch1898.unsigned(_news1892[_key1894].count);
            for (var _item1899 in _news1892[_key1894]) {
                _vscratch1898.text(_item1899);
            }
            _keys1895.append((_scratch1896.finish(), _vscratch1898.finish(), _key1894));
        }
        _keys1895.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1895.count);
        for (var (_bytes1897, _, _key1894) in _keys1895) {
            out.text(_key1894);
            out.unsigned(_news1892[_key1894].count);
            for (var _item1900 in _news1892[_key1894]) {
                out.text(_item1900);
            }
        }
        for (var (_okey1901, _) in _news1892) {
            var _own1902 = RecordOut();
            _own1902.blank_bodies = true;
            _own1902.blank_locs = true;
            _own1902.pending_as_bytes = true;
            _own1902.text(_okey1901);
            _own1902.unsigned(_news1892[_okey1901].count);
            for (var _item1903 in _news1892[_okey1901]) {
                _own1902.text(_item1903);
            }
            base.own("overload_sets", interface_text(_own1902));
        }
    } else {
        out.unsigned(0);
        var _keys1905 = Array<(u8[], u8[], String)>();
        for (var (_key1904, _) in value.overload_sets) {
            var _scratch1906 = out.scratch();
            _scratch1906.text(_key1904);
            var _vscratch1908 = out.scratch();
            _vscratch1908.unsigned(value.overload_sets[_key1904].count);
            for (var _item1909 in value.overload_sets[_key1904]) {
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
        out.unsigned(_keys1905.count);
        for (var (_bytes1907, _, _key1904) in _keys1905) {
            out.text(_key1904);
            out.unsigned(value.overload_sets[_key1904].count);
            for (var _item1910 in value.overload_sets[_key1904]) {
                out.text(_item1910);
            }
        }
        for (var (_okey1911, _) in value.overload_sets) {
            var _own1912 = RecordOut();
            _own1912.blank_bodies = true;
            _own1912.blank_locs = true;
            _own1912.pending_as_bytes = true;
            _own1912.text(_okey1911);
            _own1912.unsigned(value.overload_sets[_okey1911].count);
            for (var _item1913 in value.overload_sets[_okey1911]) {
                _own1912.text(_item1913);
            }
            base.own("overload_sets", interface_text(_own1912));
        }
        base.count("overload_sets whole", 0);
    }
    base.stat("overload_sets", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept1931 = 0;
    var _news1932 = Map<String, Array<Array<String>>>();
    for (var (_key1928, _) in value.overload_unions) {
        var _kscratch1929 = base.scratch();
        _kscratch1929.text(_key1928);
        var _vscratch1930 = base.scratch();
        _vscratch1930.unsigned(value.overload_unions[_key1928].count);
        for (var _item1933 in value.overload_unions[_key1928]) {
            _vscratch1930.unsigned(_item1933.count);
            for (var _item1934 in _item1933) {
                _vscratch1930.text(_item1934);
            }
        }
        var _had = base.entry("overload_unions", _kscratch1929, _vscratch1930);
        if (_had >= 0) {
            _kept1931 += 1;
        }
        if (_had != 1) {
            _news1932[_key1928] = value.overload_unions[_key1928];
        }
    }
    if (_kept1931 == base.size("overload_unions")) {
        out.unsigned(1);
        var _keys1936 = Array<(u8[], u8[], String)>();
        for (var (_key1935, _) in _news1932) {
            var _scratch1937 = out.scratch();
            _scratch1937.text(_key1935);
            var _vscratch1939 = out.scratch();
            _vscratch1939.unsigned(_news1932[_key1935].count);
            for (var _item1940 in _news1932[_key1935]) {
                _vscratch1939.unsigned(_item1940.count);
                for (var _item1941 in _item1940) {
                    _vscratch1939.text(_item1941);
                }
            }
            _keys1936.append((_scratch1937.finish(), _vscratch1939.finish(), _key1935));
        }
        _keys1936.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1936.count);
        for (var (_bytes1938, _, _key1935) in _keys1936) {
            out.text(_key1935);
            out.unsigned(_news1932[_key1935].count);
            for (var _item1942 in _news1932[_key1935]) {
                out.unsigned(_item1942.count);
                for (var _item1943 in _item1942) {
                    out.text(_item1943);
                }
            }
        }
        for (var (_okey1944, _) in _news1932) {
            var _own1945 = RecordOut();
            _own1945.blank_bodies = true;
            _own1945.blank_locs = true;
            _own1945.pending_as_bytes = true;
            _own1945.text(_okey1944);
            _own1945.unsigned(_news1932[_okey1944].count);
            for (var _item1946 in _news1932[_okey1944]) {
                _own1945.unsigned(_item1946.count);
                for (var _item1947 in _item1946) {
                    _own1945.text(_item1947);
                }
            }
            base.own("overload_unions", interface_text(_own1945));
        }
    } else {
        out.unsigned(0);
        var _keys1949 = Array<(u8[], u8[], String)>();
        for (var (_key1948, _) in value.overload_unions) {
            var _scratch1950 = out.scratch();
            _scratch1950.text(_key1948);
            var _vscratch1952 = out.scratch();
            _vscratch1952.unsigned(value.overload_unions[_key1948].count);
            for (var _item1953 in value.overload_unions[_key1948]) {
                _vscratch1952.unsigned(_item1953.count);
                for (var _item1954 in _item1953) {
                    _vscratch1952.text(_item1954);
                }
            }
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
            out.text(_key1948);
            out.unsigned(value.overload_unions[_key1948].count);
            for (var _item1955 in value.overload_unions[_key1948]) {
                out.unsigned(_item1955.count);
                for (var _item1956 in _item1955) {
                    out.text(_item1956);
                }
            }
        }
        for (var (_okey1957, _) in value.overload_unions) {
            var _own1958 = RecordOut();
            _own1958.blank_bodies = true;
            _own1958.blank_locs = true;
            _own1958.pending_as_bytes = true;
            _own1958.text(_okey1957);
            _own1958.unsigned(value.overload_unions[_okey1957].count);
            for (var _item1959 in value.overload_unions[_okey1957]) {
                _own1958.unsigned(_item1959.count);
                for (var _item1960 in _item1959) {
                    _own1958.text(_item1960);
                }
            }
            base.own("overload_unions", interface_text(_own1958));
        }
        base.count("overload_unions whole", 0);
    }
    base.stat("overload_unions", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept1983 = 0;
    var _news1984 = Map<String, Map<String, Array<String>>>();
    for (var (_key1980, _) in value.method_overload_sets) {
        var _kscratch1981 = base.scratch();
        _kscratch1981.text(_key1980);
        var _vscratch1982 = base.scratch();
        var _keys1986 = Array<(u8[], u8[], String)>();
        for (var (_key1985, _) in value.method_overload_sets[_key1980]) {
            var _scratch1987 = _vscratch1982.scratch();
            _scratch1987.text(_key1985);
            var _vscratch1989 = _vscratch1982.scratch();
            _vscratch1989.unsigned(value.method_overload_sets[_key1980][_key1985].count);
            for (var _item1990 in value.method_overload_sets[_key1980][_key1985]) {
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
        _vscratch1982.unsigned(_keys1986.count);
        for (var (_bytes1988, _, _key1985) in _keys1986) {
            _vscratch1982.text(_key1985);
            _vscratch1982.unsigned(value.method_overload_sets[_key1980][_key1985].count);
            for (var _item1991 in value.method_overload_sets[_key1980][_key1985]) {
                _vscratch1982.text(_item1991);
            }
        }
        var _had = base.entry("method_overload_sets", _kscratch1981, _vscratch1982);
        if (_had >= 0) {
            _kept1983 += 1;
        }
        if (_had != 1) {
            _news1984[_key1980] = value.method_overload_sets[_key1980];
        }
    }
    if (_kept1983 == base.size("method_overload_sets")) {
        out.unsigned(1);
        var _keys1993 = Array<(u8[], u8[], String)>();
        for (var (_key1992, _) in _news1984) {
            var _scratch1994 = out.scratch();
            _scratch1994.text(_key1992);
            var _vscratch1996 = out.scratch();
            var _keys1998 = Array<(u8[], u8[], String)>();
            for (var (_key1997, _) in _news1984[_key1992]) {
                var _scratch1999 = _vscratch1996.scratch();
                _scratch1999.text(_key1997);
                var _vscratch2001 = _vscratch1996.scratch();
                _vscratch2001.unsigned(_news1984[_key1992][_key1997].count);
                for (var _item2002 in _news1984[_key1992][_key1997]) {
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
            _vscratch1996.unsigned(_keys1998.count);
            for (var (_bytes2000, _, _key1997) in _keys1998) {
                _vscratch1996.text(_key1997);
                _vscratch1996.unsigned(_news1984[_key1992][_key1997].count);
                for (var _item2003 in _news1984[_key1992][_key1997]) {
                    _vscratch1996.text(_item2003);
                }
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
            var _keys2005 = Array<(u8[], u8[], String)>();
            for (var (_key2004, _) in _news1984[_key1992]) {
                var _scratch2006 = out.scratch();
                _scratch2006.text(_key2004);
                var _vscratch2008 = out.scratch();
                _vscratch2008.unsigned(_news1984[_key1992][_key2004].count);
                for (var _item2009 in _news1984[_key1992][_key2004]) {
                    _vscratch2008.text(_item2009);
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
                out.unsigned(_news1984[_key1992][_key2004].count);
                for (var _item2010 in _news1984[_key1992][_key2004]) {
                    out.text(_item2010);
                }
            }
        }
        for (var (_okey2011, _) in _news1984) {
            var _own2012 = RecordOut();
            _own2012.blank_bodies = true;
            _own2012.blank_locs = true;
            _own2012.pending_as_bytes = true;
            _own2012.text(_okey2011);
            var _keys2014 = Array<(u8[], u8[], String)>();
            for (var (_key2013, _) in _news1984[_okey2011]) {
                var _scratch2015 = _own2012.scratch();
                _scratch2015.text(_key2013);
                var _vscratch2017 = _own2012.scratch();
                _vscratch2017.unsigned(_news1984[_okey2011][_key2013].count);
                for (var _item2018 in _news1984[_okey2011][_key2013]) {
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
            _own2012.unsigned(_keys2014.count);
            for (var (_bytes2016, _, _key2013) in _keys2014) {
                _own2012.text(_key2013);
                _own2012.unsigned(_news1984[_okey2011][_key2013].count);
                for (var _item2019 in _news1984[_okey2011][_key2013]) {
                    _own2012.text(_item2019);
                }
            }
            base.own("method_overload_sets", interface_text(_own2012));
        }
    } else {
        out.unsigned(0);
        var _keys2021 = Array<(u8[], u8[], String)>();
        for (var (_key2020, _) in value.method_overload_sets) {
            var _scratch2022 = out.scratch();
            _scratch2022.text(_key2020);
            var _vscratch2024 = out.scratch();
            var _keys2026 = Array<(u8[], u8[], String)>();
            for (var (_key2025, _) in value.method_overload_sets[_key2020]) {
                var _scratch2027 = _vscratch2024.scratch();
                _scratch2027.text(_key2025);
                var _vscratch2029 = _vscratch2024.scratch();
                _vscratch2029.unsigned(value.method_overload_sets[_key2020][_key2025].count);
                for (var _item2030 in value.method_overload_sets[_key2020][_key2025]) {
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
            _vscratch2024.unsigned(_keys2026.count);
            for (var (_bytes2028, _, _key2025) in _keys2026) {
                _vscratch2024.text(_key2025);
                _vscratch2024.unsigned(value.method_overload_sets[_key2020][_key2025].count);
                for (var _item2031 in value.method_overload_sets[_key2020][_key2025]) {
                    _vscratch2024.text(_item2031);
                }
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
            var _keys2033 = Array<(u8[], u8[], String)>();
            for (var (_key2032, _) in value.method_overload_sets[_key2020]) {
                var _scratch2034 = out.scratch();
                _scratch2034.text(_key2032);
                var _vscratch2036 = out.scratch();
                _vscratch2036.unsigned(value.method_overload_sets[_key2020][_key2032].count);
                for (var _item2037 in value.method_overload_sets[_key2020][_key2032]) {
                    _vscratch2036.text(_item2037);
                }
                _keys2033.append((_scratch2034.finish(), _vscratch2036.finish(), _key2032));
            }
            _keys2033.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            out.unsigned(_keys2033.count);
            for (var (_bytes2035, _, _key2032) in _keys2033) {
                out.text(_key2032);
                out.unsigned(value.method_overload_sets[_key2020][_key2032].count);
                for (var _item2038 in value.method_overload_sets[_key2020][_key2032]) {
                    out.text(_item2038);
                }
            }
        }
        for (var (_okey2039, _) in value.method_overload_sets) {
            var _own2040 = RecordOut();
            _own2040.blank_bodies = true;
            _own2040.blank_locs = true;
            _own2040.pending_as_bytes = true;
            _own2040.text(_okey2039);
            var _keys2042 = Array<(u8[], u8[], String)>();
            for (var (_key2041, _) in value.method_overload_sets[_okey2039]) {
                var _scratch2043 = _own2040.scratch();
                _scratch2043.text(_key2041);
                var _vscratch2045 = _own2040.scratch();
                _vscratch2045.unsigned(value.method_overload_sets[_okey2039][_key2041].count);
                for (var _item2046 in value.method_overload_sets[_okey2039][_key2041]) {
                    _vscratch2045.text(_item2046);
                }
                _keys2042.append((_scratch2043.finish(), _vscratch2045.finish(), _key2041));
            }
            _keys2042.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            _own2040.unsigned(_keys2042.count);
            for (var (_bytes2044, _, _key2041) in _keys2042) {
                _own2040.text(_key2041);
                _own2040.unsigned(value.method_overload_sets[_okey2039][_key2041].count);
                for (var _item2047 in value.method_overload_sets[_okey2039][_key2041]) {
                    _own2040.text(_item2047);
                }
            }
            base.own("method_overload_sets", interface_text(_own2040));
        }
        base.count("method_overload_sets whole", 0);
    }
    base.stat("method_overload_sets", out.values.count - _mark);
    _mark = out.values.count;
    _m_ExtensionScopes_write(out, value.extension_scopes);
    base.stat("extension_scopes", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2078 = 0;
    var _news2079 = HashSet<Loc>();
    for (var _key2075 in value.private_functions) {
        var _kscratch2076 = base.scratch();
        _kscratch2076.loc(_key2075);
        var _vscratch2077 = base.scratch();
        var _had = base.entry("private_functions", _kscratch2076, _vscratch2077);
        if (_had >= 0) {
            _kept2078 += 1;
        }
        if (_had != 1) {
            _news2079.insert(_key2075);
        }
    }
    if (_kept2078 == base.size("private_functions")) {
        out.unsigned(1);
        var _keys2081 = Array<(u8[], u8[], Loc)>();
        for (var _key2080 in _news2079) {
            var _scratch2082 = out.scratch();
            _scratch2082.loc(_key2080);
            var _vscratch2084 = out.scratch();
            _keys2081.append((_scratch2082.finish(), _vscratch2084.finish(), _key2080));
        }
        _keys2081.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2081.count);
        for (var (_bytes2083, _, _key2080) in _keys2081) {
            out.loc(_key2080);
        }
        for (var _okey2085 in _news2079) {
            var _own2086 = RecordOut();
            _own2086.blank_bodies = true;
            _own2086.blank_locs = true;
            _own2086.pending_as_bytes = true;
            _own2086.loc(_okey2085);
            base.own_at("private_functions", _okey2085, interface_text(_own2086));
        }
    } else {
        out.unsigned(0);
        var _keys2088 = Array<(u8[], u8[], Loc)>();
        for (var _key2087 in value.private_functions) {
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
        for (var _okey2092 in value.private_functions) {
            var _own2093 = RecordOut();
            _own2093.blank_bodies = true;
            _own2093.blank_locs = true;
            _own2093.pending_as_bytes = true;
            _own2093.loc(_okey2092);
            base.own_at("private_functions", _okey2092, interface_text(_own2093));
        }
        base.count("private_functions whole", 0);
    }
    base.stat("private_functions", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2104 = 0;
    var _news2105 = HashSet<Loc>();
    for (var _key2101 in value.file_private_functions) {
        var _kscratch2102 = base.scratch();
        _kscratch2102.loc(_key2101);
        var _vscratch2103 = base.scratch();
        var _had = base.entry("file_private_functions", _kscratch2102, _vscratch2103);
        if (_had >= 0) {
            _kept2104 += 1;
        }
        if (_had != 1) {
            _news2105.insert(_key2101);
        }
    }
    if (_kept2104 == base.size("file_private_functions")) {
        out.unsigned(1);
        var _keys2107 = Array<(u8[], u8[], Loc)>();
        for (var _key2106 in _news2105) {
            var _scratch2108 = out.scratch();
            _scratch2108.loc(_key2106);
            var _vscratch2110 = out.scratch();
            _keys2107.append((_scratch2108.finish(), _vscratch2110.finish(), _key2106));
        }
        _keys2107.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2107.count);
        for (var (_bytes2109, _, _key2106) in _keys2107) {
            out.loc(_key2106);
        }
        for (var _okey2111 in _news2105) {
            var _own2112 = RecordOut();
            _own2112.blank_bodies = true;
            _own2112.blank_locs = true;
            _own2112.pending_as_bytes = true;
            _own2112.loc(_okey2111);
            base.own_at("file_private_functions", _okey2111, interface_text(_own2112));
        }
    } else {
        out.unsigned(0);
        var _keys2114 = Array<(u8[], u8[], Loc)>();
        for (var _key2113 in value.file_private_functions) {
            var _scratch2115 = out.scratch();
            _scratch2115.loc(_key2113);
            var _vscratch2117 = out.scratch();
            _keys2114.append((_scratch2115.finish(), _vscratch2117.finish(), _key2113));
        }
        _keys2114.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2114.count);
        for (var (_bytes2116, _, _key2113) in _keys2114) {
            out.loc(_key2113);
        }
        for (var _okey2118 in value.file_private_functions) {
            var _own2119 = RecordOut();
            _own2119.blank_bodies = true;
            _own2119.blank_locs = true;
            _own2119.pending_as_bytes = true;
            _own2119.loc(_okey2118);
            base.own_at("file_private_functions", _okey2118, interface_text(_own2119));
        }
        base.count("file_private_functions whole", 0);
    }
    base.stat("file_private_functions", out.values.count - _mark);
    _mark = out.values.count;
    var _n2129 = base.size("call_targets");
    var _scratch2128 = base.scratch();
    if (value.call_targets.count >= _n2129) {
        for (var _i2130 in 0.._n2129) {
            var (_t2131, _t2132) = value.call_targets[_i2130];
            _scratch2128.loc(_t2131);
            _scratch2128.text(_t2132);
        }
    }
    if (value.call_targets.count >= _n2129 and base.same_list("call_targets", _scratch2128)) {
        out.unsigned(1);
        out.unsigned(_n2129);
        out.unsigned(value.call_targets.count - _n2129);
        for (var _i2130 in _n2129..value.call_targets.count) {
            var (_t2133, _t2134) = value.call_targets[_i2130];
            out.loc(_t2133);
            out.text(_t2134);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.call_targets.count);
        for (var _item2135 in value.call_targets) {
            var (_t2136, _t2137) = _item2135;
            out.loc(_t2136);
            out.text(_t2137);
        }
        base.count("call_targets whole", 0);
    }
    base.stat("call_targets", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2154 = 0;
    var _news2155 = Array<(Loc, String)>();
    for (var _item2152 in value.argument_names) {
        var _escratch2153 = base.scratch();
        var (_t2156, _t2157) = _item2152;
        _escratch2153.loc(_t2156);
        _escratch2153.text(_t2157);
        if (base.entry("argument_names", _escratch2153, base.scratch()) >= 0) {
            _kept2154 += 1;
        } else {
            _news2155.append(_item2152);
        }
    }
    if (_kept2154 == base.size("argument_names")) {
        out.unsigned(1);
        out.unsigned(_news2155.count);
        for (var _item2158 in _news2155) {
            var (_t2159, _t2160) = _item2158;
            out.loc(_t2159);
            out.text(_t2160);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.argument_names.count);
        for (var _item2161 in value.argument_names) {
            var (_t2162, _t2163) = _item2161;
            out.loc(_t2162);
            out.text(_t2163);
        }
        base.count("argument_names whole", 0);
    }
    base.stat("argument_names", out.values.count - _mark);
    _mark = out.values.count;
    var _n2178 = base.size("namespaces");
    var _scratch2177 = base.scratch();
    if (value.namespaces.count >= _n2178) {
        for (var _i2179 in 0.._n2178) {
            _scratch2177.text(value.namespaces[_i2179]);
        }
    }
    if (value.namespaces.count >= _n2178 and base.same_list("namespaces", _scratch2177)) {
        out.unsigned(1);
        out.unsigned(_n2178);
        out.unsigned(value.namespaces.count - _n2178);
        for (var _i2179 in _n2178..value.namespaces.count) {
            out.text(value.namespaces[_i2179]);
            {
                var _own2180 = RecordOut();
                _own2180.blank_bodies = true;
                _own2180.blank_locs = true;
                _own2180.pending_as_bytes = true;
                _own2180.text(value.namespaces[_i2179]);
                base.own("namespaces", interface_text(_own2180));
            }
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.namespaces.count);
        for (var _item2181 in value.namespaces) {
            out.text(_item2181);
        }
        for (var _i2179 in 0..value.namespaces.count) {
            {
                var _own2182 = RecordOut();
                _own2182.blank_bodies = true;
                _own2182.blank_locs = true;
                _own2182.pending_as_bytes = true;
                _own2182.text(value.namespaces[_i2179]);
                base.own("namespaces", interface_text(_own2182));
            }
        }
        base.count("namespaces whole", 0);
    }
    base.stat("namespaces", out.values.count - _mark);
    _mark = out.values.count;
    var _n2193 = base.size("cached_files");
    var _scratch2192 = base.scratch();
    if (value.cached_files.count >= _n2193) {
        for (var _i2194 in 0.._n2193) {
            _scratch2192.flag(value.cached_files[_i2194]);
        }
    }
    if (value.cached_files.count >= _n2193 and base.same_list("cached_files", _scratch2192)) {
        out.unsigned(1);
        out.unsigned(_n2193);
        out.unsigned(value.cached_files.count - _n2193);
        for (var _i2194 in _n2193..value.cached_files.count) {
            out.flag(value.cached_files[_i2194]);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.cached_files.count);
        for (var _item2195 in value.cached_files) {
            out.flag(_item2195);
        }
        base.count("cached_files whole", 0);
    }
    base.stat("cached_files", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2207 = 0;
    var _news2208 = HashMap<Loc, String>();
    for (var (_key2204, _) in value.recorded_summaries) {
        var _kscratch2205 = base.scratch();
        _kscratch2205.loc(_key2204);
        var _vscratch2206 = base.scratch();
        _vscratch2206.text(value.recorded_summaries[_key2204]);
        var _had = base.entry("recorded_summaries", _kscratch2205, _vscratch2206);
        if (_had >= 0) {
            _kept2207 += 1;
        }
        if (_had != 1) {
            _news2208[_key2204] = value.recorded_summaries[_key2204];
        }
    }
    if (_kept2207 == base.size("recorded_summaries")) {
        out.unsigned(1);
        var _keys2210 = Array<(u8[], u8[], Loc)>();
        for (var (_key2209, _) in _news2208) {
            var _scratch2211 = out.scratch();
            _scratch2211.loc(_key2209);
            var _vscratch2213 = out.scratch();
            _vscratch2213.text(_news2208[_key2209]);
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
            out.loc(_key2209);
            out.text(_news2208[_key2209]);
        }
    } else {
        out.unsigned(0);
        var _keys2215 = Array<(u8[], u8[], Loc)>();
        for (var (_key2214, _) in value.recorded_summaries) {
            var _scratch2216 = out.scratch();
            _scratch2216.loc(_key2214);
            var _vscratch2218 = out.scratch();
            _vscratch2218.text(value.recorded_summaries[_key2214]);
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
            out.text(value.recorded_summaries[_key2214]);
        }
        base.count("recorded_summaries whole", 0);
    }
    base.stat("recorded_summaries", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2231 = 0;
    var _news2232 = HashSet<Loc>();
    for (var _key2228 in value.stripped) {
        var _kscratch2229 = base.scratch();
        _kscratch2229.loc(_key2228);
        var _vscratch2230 = base.scratch();
        var _had = base.entry("stripped", _kscratch2229, _vscratch2230);
        if (_had >= 0) {
            _kept2231 += 1;
        }
        if (_had != 1) {
            _news2232.insert(_key2228);
        }
    }
    if (_kept2231 == base.size("stripped")) {
        out.unsigned(1);
        var _keys2234 = Array<(u8[], u8[], Loc)>();
        for (var _key2233 in _news2232) {
            var _scratch2235 = out.scratch();
            _scratch2235.loc(_key2233);
            var _vscratch2237 = out.scratch();
            _keys2234.append((_scratch2235.finish(), _vscratch2237.finish(), _key2233));
        }
        _keys2234.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2234.count);
        for (var (_bytes2236, _, _key2233) in _keys2234) {
            out.loc(_key2233);
        }
    } else {
        out.unsigned(0);
        var _keys2239 = Array<(u8[], u8[], Loc)>();
        for (var _key2238 in value.stripped) {
            var _scratch2240 = out.scratch();
            _scratch2240.loc(_key2238);
            var _vscratch2242 = out.scratch();
            _keys2239.append((_scratch2240.finish(), _vscratch2242.finish(), _key2238));
        }
        _keys2239.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2239.count);
        for (var (_bytes2241, _, _key2238) in _keys2239) {
            out.loc(_key2238);
        }
        base.count("stripped whole", 0);
    }
    base.stat("stripped", out.values.count - _mark);
    _mark = out.values.count;
    out.flag(value.templates.frozen);
    var _seq2252 = base.ref_templates;
    ulong _bj2253 = 0;
    var _news2255 = Array<ulong>();
    var _patches2256 = Array<(ulong, ulong)>();
    for (var _i2257 in 0..value.templates.structs.count) {
        if (_bj2253 < _seq2252.count
            and value.templates.structs[_i2257] === _seq2252[_bj2253]
            and !value.extended_checked.contains(value.templates.structs[_i2257].name)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_StructDef_write(scratch, value.templates.structs[_i2257]);
                base.verify_same("t", _bj2253, scratch, value.templates.structs[_i2257].name);
            }
            _bj2253 += 1;
        } else if (_bj2253 < _seq2252.count
            and !(value.templates.structs[_i2257] === _seq2252[_bj2253])
            and _same_m_StructDef(value.templates.structs[_i2257], _seq2252[_bj2253], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_StructDef_write(scratch, value.templates.structs[_i2257]);
                base.verify_same("t", _bj2253, scratch, value.templates.structs[_i2257].name);
            }
            _bj2253 += 1;
        } else if (_bj2253 < _seq2252.count and value.templates.structs[_i2257].name == _seq2252[_bj2253].name) {
            _patches2256.append((_i2257, _bj2253));
            _bj2253 += 1;
        } else {
            _news2255.append(_i2257);
        }
    }
    if (_bj2253 == _seq2252.count) {
        out.unsigned(2);
        out.unsigned(_patches2256.count);
        for (var (_i2257, _b) in _patches2256) {
            ulong _before = out.values.count;
            out.text(value.templates.structs[_i2257].name);
            out.unsigned(_b);
            _patch_t_write(out, value.templates.structs[_i2257], base, _b);
            base.count("t patched", out.values.count - _before);
            {
                var _own2258 = RecordOut();
                _own2258.blank_bodies = false;
                _own2258.blank_locs = true;
                _own2258.pending_as_bytes = true;
                _m_StructDef_write(_own2258, value.templates.structs[_i2257]);
                base.own("templates structs", interface_text(_own2258));
            }
        }
        out.unsigned(_news2255.count);
        for (var _i2257 in _news2255) {
            ulong _before = out.values.count;
            out.unsigned(_i2257);
            _m_StructDef_write(out, value.templates.structs[_i2257]);
            base.count("t new", out.values.count - _before);
            {
                var _own2259 = RecordOut();
                _own2259.blank_bodies = false;
                _own2259.blank_locs = true;
                _own2259.pending_as_bytes = true;
                _m_StructDef_write(_own2259, value.templates.structs[_i2257]);
                base.own("templates structs", interface_text(_own2259));
            }
        }
        base.count("t merged", 0);
    } else {
        out.unsigned(1);
        base.count("t by place", 0);
        var _struct_hits2251 = HashSet<long>();
        var _slots2254 = HashMap<String, long>();
        for (var _i2257 in 0.._seq2252.count) {
            if (!_slots2254.contains(_seq2252[_i2257].name)) {
                _slots2254[_seq2252[_i2257].name] = _i2257 as long;
            }
        }
        out.unsigned(value.templates.structs.count);
        for (var _i2257 in 0..value.templates.structs.count) {
            var _item2250 = value.templates.structs[_i2257];
            var _slot = _slots2254.try_get(_item2250.name);
            long named = _slot.is_value() ? _slot.value() : -1;
            long at = -1;
            if (named >= 0
                and _seq2252[named as ulong] === _item2250
                and !value.extended_checked.contains(_item2250.name)) {
                at = named;
            }
            ulong _before = out.values.count;
            if (at >= 0) {
                _struct_hits2251.insert(at);
                out.unsigned((at as ulong) * 2 + 1);
            } else if (named >= 0) {
                _struct_hits2251.insert(named);
                out.unsigned(2);
                out.unsigned(named as ulong);
                _patch_t_write(out, _item2250, base, named as ulong);
                base.count("t patched", out.values.count - _before);
            } else {
                out.unsigned(0);
                _m_StructDef_write(out, _item2250);
                base.count("t new", out.values.count - _before);
            }
        }
        base.missed("t", "t", _struct_hits2251.count);
    }
    var _seq2273 = base.ref_template_functions;
    ulong _bj2274 = 0;
    var _news2275 = Array<ulong>();
    var _changed2269 = Array<(ulong, ulong)>();
    for (var _i2276 in 0..value.templates.functions.count) {
        if (_bj2274 < _seq2273.count and value.templates.functions[_i2276] === _seq2273[_bj2274]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.templates.functions[_i2276]);
                base.verify_same("tf", _bj2274, scratch);
            }
            _bj2274 += 1;
        } else if (_bj2274 < _seq2273.count
            and _same_m_FunctionDef(value.templates.functions[_i2276], _seq2273[_bj2274], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.templates.functions[_i2276]);
                base.verify_same("tf", _bj2274, scratch);
            }
            _bj2274 += 1;
        } else if (_bj2274 < _seq2273.count and value.templates.functions[_i2276].name == _seq2273[_bj2274].name) {
            _changed2269.append((_i2276, _bj2274));
            _bj2274 += 1;
        } else {
            _news2275.append(_i2276);
        }
    }
    if (_bj2274 == _seq2273.count) {
        out.unsigned(2);
        out.unsigned(_changed2269.count);
        for (var (_i2276, _b) in _changed2269) {
            out.text(value.templates.functions[_i2276].name);
            out.unsigned(_b);
            _m_FunctionDef_write(out, value.templates.functions[_i2276]);
            {
                var _own2277 = RecordOut();
                _own2277.blank_bodies = false;
                _own2277.blank_locs = true;
                _own2277.pending_as_bytes = true;
                _m_FunctionDef_write(_own2277, value.templates.functions[_i2276]);
                base.own("templates functions", interface_text(_own2277));
            }
        }
        base.count("tf" + " changed", _changed2269.count);
        out.unsigned(_news2275.count);
        for (var _i2276 in _news2275) {
            out.unsigned(_i2276);
            _m_FunctionDef_write(out, value.templates.functions[_i2276]);
            {
                var _own2278 = RecordOut();
                _own2278.blank_bodies = false;
                _own2278.blank_locs = true;
                _own2278.pending_as_bytes = true;
                _m_FunctionDef_write(_own2278, value.templates.functions[_i2276]);
                base.own("templates functions", interface_text(_own2278));
            }
        }
        base.count("tf" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("tf" + " whole", 0);
        out.unsigned(value.templates.functions.count);
        for (var _i2276 in 0..value.templates.functions.count) {
            _m_FunctionDef_write(out, value.templates.functions[_i2276]);
            {
                var _own2279 = RecordOut();
                _own2279.blank_bodies = false;
                _own2279.blank_locs = true;
                _own2279.pending_as_bytes = true;
                _m_FunctionDef_write(_own2279, value.templates.functions[_i2276]);
                base.own("templates functions", interface_text(_own2279));
            }
        }
    }
    base.stat("templates", out.values.count - _mark);
    _mark = out.values.count;
    base.write_checked(out, value.checked);
    base.stat("checked", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2292 = 0;
    var _news2293 = HashMap<String, SpecRequest>();
    for (var (_key2289, _) in value.spec_requests) {
        var _kscratch2290 = base.scratch();
        _kscratch2290.text(_key2289);
        var _vscratch2291 = base.scratch();
        _m_SpecRequest_write(_vscratch2291, value.spec_requests[_key2289]);
        var _had = base.entry("spec_requests", _kscratch2290, _vscratch2291);
        if (_had >= 0) {
            _kept2292 += 1;
        }
        if (_had != 1) {
            _news2293[_key2289] = value.spec_requests[_key2289];
        }
    }
    if (_kept2292 == base.size("spec_requests")) {
        out.unsigned(1);
        var _keys2295 = Array<(u8[], u8[], String)>();
        for (var (_key2294, _) in _news2293) {
            var _scratch2296 = out.scratch();
            _scratch2296.text(_key2294);
            var _vscratch2298 = out.scratch();
            _m_SpecRequest_write(_vscratch2298, _news2293[_key2294]);
            _keys2295.append((_scratch2296.finish(), _vscratch2298.finish(), _key2294));
        }
        _keys2295.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2295.count);
        for (var (_bytes2297, _, _key2294) in _keys2295) {
            out.text(_key2294);
            _m_SpecRequest_write(out, _news2293[_key2294]);
        }
        for (var (_okey2299, _) in _news2293) {
            var _own2300 = RecordOut();
            _own2300.blank_bodies = true;
            _own2300.blank_locs = true;
            _own2300.pending_as_bytes = true;
            _own2300.text(_okey2299);
            _m_SpecRequest_write(_own2300, _news2293[_okey2299]);
            base.own("spec_requests", interface_text(_own2300));
        }
    } else {
        out.unsigned(0);
        var _keys2302 = Array<(u8[], u8[], String)>();
        for (var (_key2301, _) in value.spec_requests) {
            var _scratch2303 = out.scratch();
            _scratch2303.text(_key2301);
            var _vscratch2305 = out.scratch();
            _m_SpecRequest_write(_vscratch2305, value.spec_requests[_key2301]);
            _keys2302.append((_scratch2303.finish(), _vscratch2305.finish(), _key2301));
        }
        _keys2302.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2302.count);
        for (var (_bytes2304, _, _key2301) in _keys2302) {
            out.text(_key2301);
            _m_SpecRequest_write(out, value.spec_requests[_key2301]);
        }
        for (var (_okey2306, _) in value.spec_requests) {
            var _own2307 = RecordOut();
            _own2307.blank_bodies = true;
            _own2307.blank_locs = true;
            _own2307.pending_as_bytes = true;
            _own2307.text(_okey2306);
            _m_SpecRequest_write(_own2307, value.spec_requests[_okey2306]);
            base.own("spec_requests", interface_text(_own2307));
        }
        base.count("spec_requests whole", 0);
    }
    base.stat("spec_requests", out.values.count - _mark);
    _mark = out.values.count;
    out.flag(value.record_summaries);
    base.stat("record_summaries", out.values.count - _mark);
    _mark = out.values.count;
    var _n2320 = base.size("summaries_to_record");
    var _scratch2319 = base.scratch();
    if (value.summaries_to_record.count >= _n2320) {
        for (var _i2321 in 0.._n2320) {
            var (_t2322, _t2323) = value.summaries_to_record[_i2321];
            _scratch2319.loc(_t2322);
            _scratch2319.text(_t2323);
        }
    }
    if (value.summaries_to_record.count >= _n2320 and base.same_list("summaries_to_record", _scratch2319)) {
        out.unsigned(1);
        out.unsigned(_n2320);
        out.unsigned(value.summaries_to_record.count - _n2320);
        for (var _i2321 in _n2320..value.summaries_to_record.count) {
            var (_t2324, _t2325) = value.summaries_to_record[_i2321];
            out.loc(_t2324);
            out.text(_t2325);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.summaries_to_record.count);
        for (var _item2326 in value.summaries_to_record) {
            var (_t2327, _t2328) = _item2326;
            out.loc(_t2327);
            out.text(_t2328);
        }
        base.count("summaries_to_record whole", 0);
    }
    base.stat("summaries_to_record", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2346 = 0;
    var _news2347 = HashMap<String, Array<bool>>();
    for (var (_key2343, _) in value.caller_copies) {
        var _kscratch2344 = base.scratch();
        _kscratch2344.text(_key2343);
        var _vscratch2345 = base.scratch();
        _vscratch2345.unsigned(value.caller_copies[_key2343].count);
        for (var _item2348 in value.caller_copies[_key2343]) {
            _vscratch2345.flag(_item2348);
        }
        var _had = base.entry("caller_copies", _kscratch2344, _vscratch2345);
        if (_had >= 0) {
            _kept2346 += 1;
        }
        if (_had != 1) {
            _news2347[_key2343] = value.caller_copies[_key2343];
        }
    }
    if (_kept2346 == base.size("caller_copies")) {
        out.unsigned(1);
        var _keys2350 = Array<(u8[], u8[], String)>();
        for (var (_key2349, _) in _news2347) {
            var _scratch2351 = out.scratch();
            _scratch2351.text(_key2349);
            var _vscratch2353 = out.scratch();
            _vscratch2353.unsigned(_news2347[_key2349].count);
            for (var _item2354 in _news2347[_key2349]) {
                _vscratch2353.flag(_item2354);
            }
            _keys2350.append((_scratch2351.finish(), _vscratch2353.finish(), _key2349));
        }
        _keys2350.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2350.count);
        for (var (_bytes2352, _, _key2349) in _keys2350) {
            out.text(_key2349);
            out.unsigned(_news2347[_key2349].count);
            for (var _item2355 in _news2347[_key2349]) {
                out.flag(_item2355);
            }
        }
        for (var (_okey2356, _) in _news2347) {
            var _own2357 = RecordOut();
            _own2357.blank_bodies = true;
            _own2357.blank_locs = true;
            _own2357.pending_as_bytes = true;
            _own2357.text(_okey2356);
            _own2357.unsigned(_news2347[_okey2356].count);
            for (var _item2358 in _news2347[_okey2356]) {
                _own2357.flag(_item2358);
            }
            base.own("caller_copies", interface_text(_own2357));
        }
    } else {
        out.unsigned(0);
        var _keys2360 = Array<(u8[], u8[], String)>();
        for (var (_key2359, _) in value.caller_copies) {
            var _scratch2361 = out.scratch();
            _scratch2361.text(_key2359);
            var _vscratch2363 = out.scratch();
            _vscratch2363.unsigned(value.caller_copies[_key2359].count);
            for (var _item2364 in value.caller_copies[_key2359]) {
                _vscratch2363.flag(_item2364);
            }
            _keys2360.append((_scratch2361.finish(), _vscratch2363.finish(), _key2359));
        }
        _keys2360.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2360.count);
        for (var (_bytes2362, _, _key2359) in _keys2360) {
            out.text(_key2359);
            out.unsigned(value.caller_copies[_key2359].count);
            for (var _item2365 in value.caller_copies[_key2359]) {
                out.flag(_item2365);
            }
        }
        for (var (_okey2366, _) in value.caller_copies) {
            var _own2367 = RecordOut();
            _own2367.blank_bodies = true;
            _own2367.blank_locs = true;
            _own2367.pending_as_bytes = true;
            _own2367.text(_okey2366);
            _own2367.unsigned(value.caller_copies[_okey2366].count);
            for (var _item2368 in value.caller_copies[_okey2366]) {
                _own2367.flag(_item2368);
            }
            base.own("caller_copies", interface_text(_own2367));
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
    var _f1515 = Array<ast.Import>();
    var _mode1518 = input.unsigned();
    if (_mode1518 == 2) {
        var _changed1504 = HashMap<ulong, ast.Import>();
        ulong _bi1519 = 0;
        var _n1516 = input.count();
        for (var _ in 0.._n1516) {
            var _at1520 = input.unsigned();
            while (_f1515.count < _at1520 or (input.merging and _bi1519 < base.imports.count)) {
                var _c = _changed1504.try_get(_bi1519);
                _f1515.append(_c.is_value() ? _c.value() : base.imports[_bi1519]);
                _bi1519 += 1;
            }
            _f1515.append(_a_Import_read(input));
        }
        while (_bi1519 < base.imports.count) {
            var _c = _changed1504.try_get(_bi1519);
            _f1515.append(_c.is_value() ? _c.value() : base.imports[_bi1519]);
            _bi1519 += 1;
        }
    } else if (_mode1518 == 3) {
        var _n1516 = input.count();
        for (var _ in 0.._n1516) {
            _f1515.append(_a_Import_read(input));
        }
    } else {
        var _n1516 = input.count();
        if (input.merging) {
            input.error = "imports" + " written by place";
        }
        for (var _ in 0.._n1516) {
            var _tag1517 = input.unsigned();
            if (_tag1517 & 1 == 1) {
                if (!input.merging) {
                    _f1515.append(base.imports[_tag1517 >> 1]);
                }
            } else {
                var _read = _a_Import_read(input);
                if (!input.merging or true) {
                    _f1515.append(_read);
                }
            }
        }
    }
    var _f1548 = Array<StructDef>();
    var _mode1551 = input.unsigned();
    if (_mode1551 == 2) {
        var _patched1554 = HashMap<ulong, StructDef>();
        var _n1549 = input.count();
        for (var _ in 0.._n1549) {
            var _name = input.text();
            var _slot = input.unsigned();
            if (input.merging) {
                _slot = struct_named(base.structs, _name);
            }
            if (_slot >= base.structs.count) {
                input.error = $"no struct {_name} to patch";
                break;
            }
            _patched1554[_slot] = _patch_s_read(input, base.structs[_slot]);
        }
        ulong _bi1552 = 0;
        var _added = input.count();
        for (var _ in 0.._added) {
            var _at1553 = input.unsigned();
            while (_f1548.count < _at1553 or (input.merging and _bi1552 < base.structs.count)) {
                var _p = _patched1554.try_get(_bi1552);
                _f1548.append(_p.is_value() ? _p.value() : base.structs[_bi1552]);
                _bi1552 += 1;
            }
            _f1548.append(_m_StructDef_read_lazy(input));
        }
        while (_bi1552 < base.structs.count) {
            var _p = _patched1554.try_get(_bi1552);
            _f1548.append(_p.is_value() ? _p.value() : base.structs[_bi1552]);
            _bi1552 += 1;
        }
    } else {
        if (input.merging) {
            input.error = "structs written by place";
        }
        var _n1549 = input.count();
        for (var _ in 0.._n1549) {
            var _tag1550 = input.unsigned();
            if (_tag1550 & 1 == 1) {
                _f1548.append(base.structs[(_tag1550 >> 1) < base.structs.count ? _tag1550 >> 1 : 0]);
            } else if (_tag1550 == 2) {
                var _was = base.structs[input.unsigned()];
                _f1548.append(_patch_s_read(input, _was));
            } else {
                _f1548.append(_m_StructDef_read_lazy(input));
            }
        }
    }
    var _f1568 = Array<TraitDef>();
    var _mode1571 = input.unsigned();
    if (_mode1571 == 2) {
        var _changed1557 = HashMap<ulong, TraitDef>();
        ulong _bi1572 = 0;
        var _n1569 = input.count();
        for (var _ in 0.._n1569) {
            var _at1573 = input.unsigned();
            while (_f1568.count < _at1573 or (input.merging and _bi1572 < base.traits.count)) {
                var _c = _changed1557.try_get(_bi1572);
                _f1568.append(_c.is_value() ? _c.value() : base.traits[_bi1572]);
                _bi1572 += 1;
            }
            _f1568.append(_m_TraitDef_read(input));
        }
        while (_bi1572 < base.traits.count) {
            var _c = _changed1557.try_get(_bi1572);
            _f1568.append(_c.is_value() ? _c.value() : base.traits[_bi1572]);
            _bi1572 += 1;
        }
    } else if (_mode1571 == 3) {
        var _n1569 = input.count();
        for (var _ in 0.._n1569) {
            _f1568.append(_m_TraitDef_read(input));
        }
    } else {
        var _n1569 = input.count();
        if (input.merging) {
            input.error = "traits" + " written by place";
        }
        for (var _ in 0.._n1569) {
            var _tag1570 = input.unsigned();
            if (_tag1570 & 1 == 1) {
                if (!input.merging) {
                    _f1568.append(base.traits[_tag1570 >> 1]);
                }
            } else {
                var _read = _m_TraitDef_read(input);
                if (!input.merging or true) {
                    _f1568.append(_read);
                }
            }
        }
    }
    var _f1587 = Array<ExtensionDef>();
    var _mode1590 = input.unsigned();
    if (_mode1590 == 2) {
        var _changed1576 = HashMap<ulong, ExtensionDef>();
        ulong _bi1591 = 0;
        var _n1588 = input.count();
        for (var _ in 0.._n1588) {
            var _at1592 = input.unsigned();
            while (_f1587.count < _at1592 or (input.merging and _bi1591 < base.extensions.count)) {
                var _c = _changed1576.try_get(_bi1591);
                _f1587.append(_c.is_value() ? _c.value() : base.extensions[_bi1591]);
                _bi1591 += 1;
            }
            _f1587.append(_m_ExtensionDef_read(input));
        }
        while (_bi1591 < base.extensions.count) {
            var _c = _changed1576.try_get(_bi1591);
            _f1587.append(_c.is_value() ? _c.value() : base.extensions[_bi1591]);
            _bi1591 += 1;
        }
    } else if (_mode1590 == 3) {
        var _n1588 = input.count();
        for (var _ in 0.._n1588) {
            _f1587.append(_m_ExtensionDef_read(input));
        }
    } else {
        var _n1588 = input.count();
        if (input.merging) {
            input.error = "extensions" + " written by place";
        }
        for (var _ in 0.._n1588) {
            var _tag1589 = input.unsigned();
            if (_tag1589 & 1 == 1) {
                if (!input.merging) {
                    _f1587.append(base.extensions[_tag1589 >> 1]);
                }
            } else {
                var _read = _m_ExtensionDef_read(input);
                if (!input.merging or true) {
                    _f1587.append(_read);
                }
            }
        }
    }
    var _f1606 = Array<FunctionDef>();
    var _mode1609 = input.unsigned();
    if (_mode1609 == 2) {
        var _changed1595 = HashMap<ulong, FunctionDef>();
        var _nc1597 = input.count();
        for (var _ in 0.._nc1597) {
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
                _changed1595[_slot] = _el;
            } else {
                input.error = $"no {_name} to change";
            }
        }
        ulong _bi1610 = 0;
        var _n1607 = input.count();
        for (var _ in 0.._n1607) {
            var _at1611 = input.unsigned();
            while (_f1606.count < _at1611 or (input.merging and _bi1610 < base.functions.count)) {
                var _c = _changed1595.try_get(_bi1610);
                _f1606.append(_c.is_value() ? _c.value() : base.functions[_bi1610]);
                _bi1610 += 1;
            }
            _f1606.append(_m_FunctionDef_read_lazy(input));
        }
        while (_bi1610 < base.functions.count) {
            var _c = _changed1595.try_get(_bi1610);
            _f1606.append(_c.is_value() ? _c.value() : base.functions[_bi1610]);
            _bi1610 += 1;
        }
    } else if (_mode1609 == 3) {
        var _n1607 = input.count();
        for (var _ in 0.._n1607) {
            _f1606.append(_m_FunctionDef_read_lazy(input));
        }
    } else {
        var _n1607 = input.count();
        if (input.merging) {
            input.error = "functions" + " written by place";
        }
        for (var _ in 0.._n1607) {
            var _tag1608 = input.unsigned();
            if (_tag1608 & 1 == 1) {
                if (!input.merging) {
                    _f1606.append(base.functions[_tag1608 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read_lazy(input);
                if (!input.merging or true) {
                    _f1606.append(_read);
                }
            }
        }
    }
    var _f1625 = Array<ExternDef>();
    var _mode1628 = input.unsigned();
    if (_mode1628 == 2) {
        var _changed1614 = HashMap<ulong, ExternDef>();
        ulong _bi1629 = 0;
        var _n1626 = input.count();
        for (var _ in 0.._n1626) {
            var _at1630 = input.unsigned();
            while (_f1625.count < _at1630 or (input.merging and _bi1629 < base.externs.count)) {
                var _c = _changed1614.try_get(_bi1629);
                _f1625.append(_c.is_value() ? _c.value() : base.externs[_bi1629]);
                _bi1629 += 1;
            }
            _f1625.append(_m_ExternDef_read(input));
        }
        while (_bi1629 < base.externs.count) {
            var _c = _changed1614.try_get(_bi1629);
            _f1625.append(_c.is_value() ? _c.value() : base.externs[_bi1629]);
            _bi1629 += 1;
        }
    } else if (_mode1628 == 3) {
        var _n1626 = input.count();
        for (var _ in 0.._n1626) {
            _f1625.append(_m_ExternDef_read(input));
        }
    } else {
        var _n1626 = input.count();
        if (input.merging) {
            input.error = "externs" + " written by place";
        }
        for (var _ in 0.._n1626) {
            var _tag1627 = input.unsigned();
            if (_tag1627 & 1 == 1) {
                if (!input.merging) {
                    _f1625.append(base.externs[_tag1627 >> 1]);
                }
            } else {
                var _read = _m_ExternDef_read(input);
                if (!input.merging or true) {
                    _f1625.append(_read);
                }
            }
        }
    }
    var _f1644 = Array<VariableDef>();
    var _mode1647 = input.unsigned();
    if (_mode1647 == 2) {
        var _changed1633 = HashMap<ulong, VariableDef>();
        ulong _bi1648 = 0;
        var _n1645 = input.count();
        for (var _ in 0.._n1645) {
            var _at1649 = input.unsigned();
            while (_f1644.count < _at1649 or (input.merging and _bi1648 < base.globals.count)) {
                var _c = _changed1633.try_get(_bi1648);
                _f1644.append(_c.is_value() ? _c.value() : base.globals[_bi1648]);
                _bi1648 += 1;
            }
            _f1644.append(_m_VariableDef_read(input));
        }
        while (_bi1648 < base.globals.count) {
            var _c = _changed1633.try_get(_bi1648);
            _f1644.append(_c.is_value() ? _c.value() : base.globals[_bi1648]);
            _bi1648 += 1;
        }
    } else if (_mode1647 == 3) {
        var _n1645 = input.count();
        for (var _ in 0.._n1645) {
            _f1644.append(_m_VariableDef_read(input));
        }
    } else {
        var _n1645 = input.count();
        if (input.merging) {
            input.error = "globals" + " written by place";
        }
        for (var _ in 0.._n1645) {
            var _tag1646 = input.unsigned();
            if (_tag1646 & 1 == 1) {
                if (!input.merging) {
                    _f1644.append(base.globals[_tag1646 >> 1]);
                }
            } else {
                var _read = _m_VariableDef_read(input);
                if (!input.merging or true) {
                    _f1644.append(_read);
                }
            }
        }
    }
    var _f1663 = Array<ModuleStaticBlock>();
    var _mode1666 = input.unsigned();
    if (_mode1666 == 2) {
        var _changed1652 = HashMap<ulong, ModuleStaticBlock>();
        ulong _bi1667 = 0;
        var _n1664 = input.count();
        for (var _ in 0.._n1664) {
            var _at1668 = input.unsigned();
            while (_f1663.count < _at1668 or (input.merging and _bi1667 < base.static_blocks.count)) {
                var _c = _changed1652.try_get(_bi1667);
                _f1663.append(_c.is_value() ? _c.value() : base.static_blocks[_bi1667]);
                _bi1667 += 1;
            }
            _f1663.append(_m_ModuleStaticBlock_read(input));
        }
        while (_bi1667 < base.static_blocks.count) {
            var _c = _changed1652.try_get(_bi1667);
            _f1663.append(_c.is_value() ? _c.value() : base.static_blocks[_bi1667]);
            _bi1667 += 1;
        }
    } else if (_mode1666 == 3) {
        var _n1664 = input.count();
        for (var _ in 0.._n1664) {
            _f1663.append(_m_ModuleStaticBlock_read(input));
        }
    } else {
        var _n1664 = input.count();
        if (input.merging) {
            input.error = "static_blocks" + " written by place";
        }
        for (var _ in 0.._n1664) {
            var _tag1665 = input.unsigned();
            if (_tag1665 & 1 == 1) {
                if (!input.merging) {
                    _f1663.append(base.static_blocks[_tag1665 >> 1]);
                }
            } else {
                var _read = _m_ModuleStaticBlock_read(input);
                if (!input.merging or true) {
                    _f1663.append(_read);
                }
            }
        }
    }
    var _f1682 = Array<EnumDef>();
    var _mode1685 = input.unsigned();
    if (_mode1685 == 2) {
        var _changed1671 = HashMap<ulong, EnumDef>();
        ulong _bi1686 = 0;
        var _n1683 = input.count();
        for (var _ in 0.._n1683) {
            var _at1687 = input.unsigned();
            while (_f1682.count < _at1687 or (input.merging and _bi1686 < base.enums.count)) {
                var _c = _changed1671.try_get(_bi1686);
                _f1682.append(_c.is_value() ? _c.value() : base.enums[_bi1686]);
                _bi1686 += 1;
            }
            _f1682.append(_m_EnumDef_read(input));
        }
        while (_bi1686 < base.enums.count) {
            var _c = _changed1671.try_get(_bi1686);
            _f1682.append(_c.is_value() ? _c.value() : base.enums[_bi1686]);
            _bi1686 += 1;
        }
    } else if (_mode1685 == 3) {
        var _n1683 = input.count();
        for (var _ in 0.._n1683) {
            _f1682.append(_m_EnumDef_read(input));
        }
    } else {
        var _n1683 = input.count();
        if (input.merging) {
            input.error = "enums" + " written by place";
        }
        for (var _ in 0.._n1683) {
            var _tag1684 = input.unsigned();
            if (_tag1684 & 1 == 1) {
                if (!input.merging) {
                    _f1682.append(base.enums[_tag1684 >> 1]);
                }
            } else {
                var _read = _m_EnumDef_read(input);
                if (!input.merging or true) {
                    _f1682.append(_read);
                }
            }
        }
    }
    var _f1701 = Array<TypeName>();
    var _mode1704 = input.unsigned();
    if (_mode1704 == 2) {
        var _changed1690 = HashMap<ulong, TypeName>();
        ulong _bi1705 = 0;
        var _n1702 = input.count();
        for (var _ in 0.._n1702) {
            var _at1706 = input.unsigned();
            while (_f1701.count < _at1706 or (input.merging and _bi1705 < base.struct_specs.count)) {
                var _c = _changed1690.try_get(_bi1705);
                _f1701.append(_c.is_value() ? _c.value() : base.struct_specs[_bi1705]);
                _bi1705 += 1;
            }
            _f1701.append(_m_TypeName_read(input));
        }
        while (_bi1705 < base.struct_specs.count) {
            var _c = _changed1690.try_get(_bi1705);
            _f1701.append(_c.is_value() ? _c.value() : base.struct_specs[_bi1705]);
            _bi1705 += 1;
        }
    } else if (_mode1704 == 3) {
        var _n1702 = input.count();
        for (var _ in 0.._n1702) {
            _f1701.append(_m_TypeName_read(input));
        }
    } else {
        var _n1702 = input.count();
        if (input.merging) {
            input.error = "struct_specs" + " written by place";
        }
        for (var _ in 0.._n1702) {
            var _tag1703 = input.unsigned();
            if (_tag1703 & 1 == 1) {
                if (!input.merging) {
                    _f1701.append(base.struct_specs[_tag1703 >> 1]);
                }
            } else {
                var _read = _m_TypeName_read(input);
                if (!input.merging or true) {
                    _f1701.append(_read);
                }
            }
        }
    }
    var _f1720 = Array<TypeName>();
    var _mode1723 = input.unsigned();
    if (_mode1723 == 2) {
        var _changed1709 = HashMap<ulong, TypeName>();
        ulong _bi1724 = 0;
        var _n1721 = input.count();
        for (var _ in 0.._n1721) {
            var _at1725 = input.unsigned();
            while (_f1720.count < _at1725 or (input.merging and _bi1724 < base.func_specs.count)) {
                var _c = _changed1709.try_get(_bi1724);
                _f1720.append(_c.is_value() ? _c.value() : base.func_specs[_bi1724]);
                _bi1724 += 1;
            }
            _f1720.append(_m_TypeName_read(input));
        }
        while (_bi1724 < base.func_specs.count) {
            var _c = _changed1709.try_get(_bi1724);
            _f1720.append(_c.is_value() ? _c.value() : base.func_specs[_bi1724]);
            _bi1724 += 1;
        }
    } else if (_mode1723 == 3) {
        var _n1721 = input.count();
        for (var _ in 0.._n1721) {
            _f1720.append(_m_TypeName_read(input));
        }
    } else {
        var _n1721 = input.count();
        if (input.merging) {
            input.error = "func_specs" + " written by place";
        }
        for (var _ in 0.._n1721) {
            var _tag1722 = input.unsigned();
            if (_tag1722 & 1 == 1) {
                if (!input.merging) {
                    _f1720.append(base.func_specs[_tag1722 >> 1]);
                }
            } else {
                var _read = _m_TypeName_read(input);
                if (!input.merging or true) {
                    _f1720.append(_read);
                }
            }
        }
    }
    var _f1732 = Array<TypeAliasDef>();
    var _n1733 = input.count();
    if (input.merging) {
        for (var _b in base.type_aliases) {
            _f1732.append(_b);
        }
    }
    for (var _ in 0.._n1733) {
        var _tag1734 = input.unsigned();
        if (_tag1734 & 1 == 1) {
            if (!input.merging) {
                _f1732.append(base.type_aliases[_tag1734 >> 1]);
            }
        } else {
            var _read = _m_TypeAliasDef_read(input);
            if (!input.merging or false) {
                _f1732.append(_read);
            }
        }
    }
    var _f1748 = Array<Withheld>();
    var _mode1751 = input.unsigned();
    if (_mode1751 == 2) {
        var _changed1737 = HashMap<ulong, Withheld>();
        ulong _bi1752 = 0;
        var _n1749 = input.count();
        for (var _ in 0.._n1749) {
            var _at1753 = input.unsigned();
            while (_f1748.count < _at1753 or (input.merging and _bi1752 < base.withheld.count)) {
                var _c = _changed1737.try_get(_bi1752);
                _f1748.append(_c.is_value() ? _c.value() : base.withheld[_bi1752]);
                _bi1752 += 1;
            }
            _f1748.append(_m_Withheld_read(input));
        }
        while (_bi1752 < base.withheld.count) {
            var _c = _changed1737.try_get(_bi1752);
            _f1748.append(_c.is_value() ? _c.value() : base.withheld[_bi1752]);
            _bi1752 += 1;
        }
    } else if (_mode1751 == 3) {
        var _n1749 = input.count();
        for (var _ in 0.._n1749) {
            _f1748.append(_m_Withheld_read(input));
        }
    } else {
        var _n1749 = input.count();
        if (input.merging) {
            input.error = "withheld" + " written by place";
        }
        for (var _ in 0.._n1749) {
            var _tag1750 = input.unsigned();
            if (_tag1750 & 1 == 1) {
                if (!input.merging) {
                    _f1748.append(base.withheld[_tag1750 >> 1]);
                }
            } else {
                var _read = _m_Withheld_read(input);
                if (!input.merging or true) {
                    _f1748.append(_read);
                }
            }
        }
    }
    var _f1767 = Array<PropertyDef>();
    var _mode1770 = input.unsigned();
    if (_mode1770 == 2) {
        var _changed1756 = HashMap<ulong, PropertyDef>();
        ulong _bi1771 = 0;
        var _n1768 = input.count();
        for (var _ in 0.._n1768) {
            var _at1772 = input.unsigned();
            while (_f1767.count < _at1772 or (input.merging and _bi1771 < base.properties.count)) {
                var _c = _changed1756.try_get(_bi1771);
                _f1767.append(_c.is_value() ? _c.value() : base.properties[_bi1771]);
                _bi1771 += 1;
            }
            _f1767.append(_m_PropertyDef_read(input));
        }
        while (_bi1771 < base.properties.count) {
            var _c = _changed1756.try_get(_bi1771);
            _f1767.append(_c.is_value() ? _c.value() : base.properties[_bi1771]);
            _bi1771 += 1;
        }
    } else if (_mode1770 == 3) {
        var _n1768 = input.count();
        for (var _ in 0.._n1768) {
            _f1767.append(_m_PropertyDef_read(input));
        }
    } else {
        var _n1768 = input.count();
        if (input.merging) {
            input.error = "properties" + " written by place";
        }
        for (var _ in 0.._n1768) {
            var _tag1769 = input.unsigned();
            if (_tag1769 & 1 == 1) {
                if (!input.merging) {
                    _f1767.append(base.properties[_tag1769 >> 1]);
                }
            } else {
                var _read = _m_PropertyDef_read(input);
                if (!input.merging or true) {
                    _f1767.append(_read);
                }
            }
        }
    }
    var _f1786 = Array<TypeUse>();
    var _mode1789 = input.unsigned();
    if (_mode1789 == 2) {
        var _changed1775 = HashMap<ulong, TypeUse>();
        ulong _bi1790 = 0;
        var _n1787 = input.count();
        for (var _ in 0.._n1787) {
            var _at1791 = input.unsigned();
            while (_f1786.count < _at1791 or (input.merging and _bi1790 < base.type_uses.count)) {
                var _c = _changed1775.try_get(_bi1790);
                _f1786.append(_c.is_value() ? _c.value() : base.type_uses[_bi1790]);
                _bi1790 += 1;
            }
            _f1786.append(_m_TypeUse_read(input));
        }
        while (_bi1790 < base.type_uses.count) {
            var _c = _changed1775.try_get(_bi1790);
            _f1786.append(_c.is_value() ? _c.value() : base.type_uses[_bi1790]);
            _bi1790 += 1;
        }
    } else if (_mode1789 == 3) {
        var _n1787 = input.count();
        for (var _ in 0.._n1787) {
            _f1786.append(_m_TypeUse_read(input));
        }
    } else {
        var _n1787 = input.count();
        if (input.merging) {
            input.error = "type_uses" + " written by place";
        }
        for (var _ in 0.._n1787) {
            var _tag1788 = input.unsigned();
            if (_tag1788 & 1 == 1) {
                if (!input.merging) {
                    _f1786.append(base.type_uses[_tag1788 >> 1]);
                }
            } else {
                var _read = _m_TypeUse_read(input);
                if (!input.merging or true) {
                    _f1786.append(_read);
                }
            }
        }
    }
    var _f1805 = Array<UseContext>();
    var _mode1808 = input.unsigned();
    if (_mode1808 == 2) {
        var _changed1794 = HashMap<ulong, UseContext>();
        ulong _bi1809 = 0;
        var _n1806 = input.count();
        for (var _ in 0.._n1806) {
            var _at1810 = input.unsigned();
            while (_f1805.count < _at1810 or (input.merging and _bi1809 < base.use_contexts.count)) {
                var _c = _changed1794.try_get(_bi1809);
                _f1805.append(_c.is_value() ? _c.value() : base.use_contexts[_bi1809]);
                _bi1809 += 1;
            }
            _f1805.append(_m_UseContext_read(input));
        }
        while (_bi1809 < base.use_contexts.count) {
            var _c = _changed1794.try_get(_bi1809);
            _f1805.append(_c.is_value() ? _c.value() : base.use_contexts[_bi1809]);
            _bi1809 += 1;
        }
    } else if (_mode1808 == 3) {
        var _n1806 = input.count();
        for (var _ in 0.._n1806) {
            _f1805.append(_m_UseContext_read(input));
        }
    } else {
        var _n1806 = input.count();
        if (input.merging) {
            input.error = "use_contexts" + " written by place";
        }
        for (var _ in 0.._n1806) {
            var _tag1807 = input.unsigned();
            if (_tag1807 & 1 == 1) {
                if (!input.merging) {
                    _f1805.append(base.use_contexts[_tag1807 >> 1]);
                }
            } else {
                var _read = _m_UseContext_read(input);
                if (!input.merging or true) {
                    _f1805.append(_read);
                }
            }
        }
    }
    var _f1826 = Array<(Loc, ulong, Loc)>();
    var _tag1827 = input.unsigned();
    if (_tag1827 == 1) {
        input.unsigned();
        for (var _i1815 in 0..base.literal_args.count) {
            _f1826.append(base.literal_args[_i1815]);
        }
        var _more1829 = input.count();
        for (var _ in 0.._more1829) {
            var _t1830 = input.loc();
            var _t1831 = input.unsigned();
            var _t1832 = input.loc();
            _f1826.append((_t1830, _t1831, _t1832));
        }
    } else {
        var _v1833 = Array<(Loc, ulong, Loc)>();
        var _n1834 = input.count();
        for (var _ in 0.._n1834) {
            var _t1835 = input.loc();
            var _t1836 = input.unsigned();
            var _t1837 = input.loc();
            _v1833.append((_t1835, _t1836, _t1837));
        }
        _f1826 = _v1833;
    }
    var _f1855 = Array<TypeAliasDef>();
    var _mode1858 = input.unsigned();
    if (_mode1858 == 2) {
        var _changed1844 = HashMap<ulong, TypeAliasDef>();
        ulong _bi1859 = 0;
        var _n1856 = input.count();
        for (var _ in 0.._n1856) {
            var _at1860 = input.unsigned();
            while (_f1855.count < _at1860 or (input.merging and _bi1859 < base.constrained_aliases.count)) {
                var _c = _changed1844.try_get(_bi1859);
                _f1855.append(_c.is_value() ? _c.value() : base.constrained_aliases[_bi1859]);
                _bi1859 += 1;
            }
            _f1855.append(_m_TypeAliasDef_read(input));
        }
        while (_bi1859 < base.constrained_aliases.count) {
            var _c = _changed1844.try_get(_bi1859);
            _f1855.append(_c.is_value() ? _c.value() : base.constrained_aliases[_bi1859]);
            _bi1859 += 1;
        }
    } else if (_mode1858 == 3) {
        var _n1856 = input.count();
        for (var _ in 0.._n1856) {
            _f1855.append(_m_TypeAliasDef_read(input));
        }
    } else {
        var _n1856 = input.count();
        if (input.merging) {
            input.error = "constrained_aliases" + " written by place";
        }
        for (var _ in 0.._n1856) {
            var _tag1857 = input.unsigned();
            if (_tag1857 & 1 == 1) {
                if (!input.merging) {
                    _f1855.append(base.constrained_aliases[_tag1857 >> 1]);
                }
            } else {
                var _read = _m_TypeAliasDef_read(input);
                if (!input.merging or true) {
                    _f1855.append(_read);
                }
            }
        }
    }
    var _f1874 = Array<TraitType>();
    var _mode1877 = input.unsigned();
    if (_mode1877 == 2) {
        var _changed1863 = HashMap<ulong, TraitType>();
        ulong _bi1878 = 0;
        var _n1875 = input.count();
        for (var _ in 0.._n1875) {
            var _at1879 = input.unsigned();
            while (_f1874.count < _at1879 or (input.merging and _bi1878 < base.trait_types.count)) {
                var _c = _changed1863.try_get(_bi1878);
                _f1874.append(_c.is_value() ? _c.value() : base.trait_types[_bi1878]);
                _bi1878 += 1;
            }
            _f1874.append(_m_TraitType_read(input));
        }
        while (_bi1878 < base.trait_types.count) {
            var _c = _changed1863.try_get(_bi1878);
            _f1874.append(_c.is_value() ? _c.value() : base.trait_types[_bi1878]);
            _bi1878 += 1;
        }
    } else if (_mode1877 == 3) {
        var _n1875 = input.count();
        for (var _ in 0.._n1875) {
            _f1874.append(_m_TraitType_read(input));
        }
    } else {
        var _n1875 = input.count();
        if (input.merging) {
            input.error = "trait_types" + " written by place";
        }
        for (var _ in 0.._n1875) {
            var _tag1876 = input.unsigned();
            if (_tag1876 & 1 == 1) {
                if (!input.merging) {
                    _f1874.append(base.trait_types[_tag1876 >> 1]);
                }
            } else {
                var _read = _m_TraitType_read(input);
                if (!input.merging or true) {
                    _f1874.append(_read);
                }
            }
        }
    }
    var _v1885 = Array<Conversion>();
    var _n1886 = input.count();
    for (var _ in 0.._n1886) {
        _v1885.append(_m_Conversion_read(input));
    }
    var _f1887 = _v1885;
    var _f1914 = Map<String, Array<String>>();
    var _tag1915 = input.unsigned();
    if (_tag1915 == 1) {
        for (var (_bk1916, _bv) in base.overload_sets) {
            _f1914[_bk1916] = _bv;
        }
        var _v1917 = Map<String, Array<String>>();
        var _n1918 = input.count();
        for (var _ in 0.._n1918) {
            var _k1919 = input.text();
            var _v1920 = Array<String>();
            var _n1921 = input.count();
            for (var _ in 0.._n1921) {
                _v1920.append(input.text());
            }
            _v1917[_k1919] = _v1920;
        }
        for (var (_bk1916, _av) in _v1917) {
            _f1914[_bk1916] = _av;
        }
    } else {
        var _v1922 = Map<String, Array<String>>();
        var _n1923 = input.count();
        for (var _ in 0.._n1923) {
            var _k1924 = input.text();
            var _v1925 = Array<String>();
            var _n1926 = input.count();
            for (var _ in 0.._n1926) {
                _v1925.append(input.text());
            }
            _v1922[_k1924] = _v1925;
        }
        _f1914 = _v1922;
    }
    var _f1961 = Map<String, Array<Array<String>>>();
    var _tag1962 = input.unsigned();
    if (_tag1962 == 1) {
        for (var (_bk1963, _bv) in base.overload_unions) {
            _f1961[_bk1963] = _bv;
        }
        var _v1964 = Map<String, Array<Array<String>>>();
        var _n1965 = input.count();
        for (var _ in 0.._n1965) {
            var _k1966 = input.text();
            var _v1967 = Array<Array<String>>();
            var _n1968 = input.count();
            for (var _ in 0.._n1968) {
                var _v1969 = Array<String>();
                var _n1970 = input.count();
                for (var _ in 0.._n1970) {
                    _v1969.append(input.text());
                }
                _v1967.append(_v1969);
            }
            _v1964[_k1966] = _v1967;
        }
        for (var (_bk1963, _av) in _v1964) {
            _f1961[_bk1963] = _av;
        }
    } else {
        var _v1971 = Map<String, Array<Array<String>>>();
        var _n1972 = input.count();
        for (var _ in 0.._n1972) {
            var _k1973 = input.text();
            var _v1974 = Array<Array<String>>();
            var _n1975 = input.count();
            for (var _ in 0.._n1975) {
                var _v1976 = Array<String>();
                var _n1977 = input.count();
                for (var _ in 0.._n1977) {
                    _v1976.append(input.text());
                }
                _v1974.append(_v1976);
            }
            _v1971[_k1973] = _v1974;
        }
        _f1961 = _v1971;
    }
    var _f2048 = Map<String, Map<String, Array<String>>>();
    var _tag2049 = input.unsigned();
    if (_tag2049 == 1) {
        for (var (_bk2050, _bv) in base.method_overload_sets) {
            _f2048[_bk2050] = _bv;
        }
        var _v2051 = Map<String, Map<String, Array<String>>>();
        var _n2052 = input.count();
        for (var _ in 0.._n2052) {
            var _k2053 = input.text();
            var _v2054 = Map<String, Array<String>>();
            var _n2055 = input.count();
            for (var _ in 0.._n2055) {
                var _k2056 = input.text();
                var _v2057 = Array<String>();
                var _n2058 = input.count();
                for (var _ in 0.._n2058) {
                    _v2057.append(input.text());
                }
                _v2054[_k2056] = _v2057;
            }
            _v2051[_k2053] = _v2054;
        }
        for (var (_bk2050, _av) in _v2051) {
            _f2048[_bk2050] = _av;
        }
    } else {
        var _v2059 = Map<String, Map<String, Array<String>>>();
        var _n2060 = input.count();
        for (var _ in 0.._n2060) {
            var _k2061 = input.text();
            var _v2062 = Map<String, Array<String>>();
            var _n2063 = input.count();
            for (var _ in 0.._n2063) {
                var _k2064 = input.text();
                var _v2065 = Array<String>();
                var _n2066 = input.count();
                for (var _ in 0.._n2066) {
                    _v2065.append(input.text());
                }
                _v2062[_k2064] = _v2065;
            }
            _v2059[_k2061] = _v2062;
        }
        _f2048 = _v2059;
    }
    var _f2074 = _m_ExtensionScopes_read(input);
    var _f2094 = HashSet<Loc>();
    var _tag2095 = input.unsigned();
    if (_tag2095 == 1) {
        for (var _bk2096 in base.private_functions) {
            _f2094.insert(_bk2096);
        }
        var _v2097 = HashSet<Loc>();
        var _n2098 = input.count();
        for (var _ in 0.._n2098) {
            _v2097.insert(input.loc());
        }
        for (var _bk2096 in _v2097) {
            _f2094.insert(_bk2096);
        }
    } else {
        var _v2099 = HashSet<Loc>();
        var _n2100 = input.count();
        for (var _ in 0.._n2100) {
            _v2099.insert(input.loc());
        }
        _f2094 = _v2099;
    }
    var _f2120 = HashSet<Loc>();
    var _tag2121 = input.unsigned();
    if (_tag2121 == 1) {
        for (var _bk2122 in base.file_private_functions) {
            _f2120.insert(_bk2122);
        }
        var _v2123 = HashSet<Loc>();
        var _n2124 = input.count();
        for (var _ in 0.._n2124) {
            _v2123.insert(input.loc());
        }
        for (var _bk2122 in _v2123) {
            _f2120.insert(_bk2122);
        }
    } else {
        var _v2125 = HashSet<Loc>();
        var _n2126 = input.count();
        for (var _ in 0.._n2126) {
            _v2125.insert(input.loc());
        }
        _f2120 = _v2125;
    }
    var _f2138 = Array<(Loc, String)>();
    var _tag2139 = input.unsigned();
    if (_tag2139 == 1) {
        input.unsigned();
        for (var _i2130 in 0..base.call_targets.count) {
            _f2138.append(base.call_targets[_i2130]);
        }
        var _more2141 = input.count();
        for (var _ in 0.._more2141) {
            var _t2142 = input.loc();
            var _t2143 = input.text();
            _f2138.append((_t2142, _t2143));
        }
    } else {
        var _v2144 = Array<(Loc, String)>();
        var _n2145 = input.count();
        for (var _ in 0.._n2145) {
            var _t2146 = input.loc();
            var _t2147 = input.text();
            _v2144.append((_t2146, _t2147));
        }
        _f2138 = _v2144;
    }
    var _f2164 = Array<(Loc, String)>();
    var _tag2165 = input.unsigned();
    if (_tag2165 == 1) {
        var _v2166 = Array<(Loc, String)>();
        var _n2167 = input.count();
        for (var _ in 0.._n2167) {
            var _t2168 = input.loc();
            var _t2169 = input.text();
            _v2166.append((_t2168, _t2169));
        }
        _f2164 = merge_by_place(base.argument_names, _v2166);
    } else {
        var _v2170 = Array<(Loc, String)>();
        var _n2171 = input.count();
        for (var _ in 0.._n2171) {
            var _t2172 = input.loc();
            var _t2173 = input.text();
            _v2170.append((_t2172, _t2173));
        }
        _f2164 = _v2170;
    }
    var _f2183 = Array<String>();
    var _tag2184 = input.unsigned();
    if (_tag2184 == 1) {
        input.unsigned();
        for (var _i2179 in 0..base.namespaces.count) {
            _f2183.append(base.namespaces[_i2179]);
        }
        var _more2186 = input.count();
        for (var _ in 0.._more2186) {
            _f2183.append(input.text());
        }
    } else {
        var _v2187 = Array<String>();
        var _n2188 = input.count();
        for (var _ in 0.._n2188) {
            _v2187.append(input.text());
        }
        _f2183 = _v2187;
    }
    var _f2196 = Array<bool>();
    var _tag2197 = input.unsigned();
    if (_tag2197 == 1) {
        input.unsigned();
        for (var _i2194 in 0..base.cached_files.count) {
            _f2196.append(base.cached_files[_i2194]);
        }
        var _more2199 = input.count();
        for (var _ in 0.._more2199) {
            _f2196.append(input.flag());
        }
    } else {
        var _v2200 = Array<bool>();
        var _n2201 = input.count();
        for (var _ in 0.._n2201) {
            _v2200.append(input.flag());
        }
        _f2196 = _v2200;
    }
    var _f2219 = HashMap<Loc, String>();
    var _tag2220 = input.unsigned();
    if (_tag2220 == 1) {
        for (var (_bk2221, _bv) in base.recorded_summaries) {
            _f2219[_bk2221] = _bv;
        }
        var _v2222 = HashMap<Loc, String>();
        var _n2223 = input.count();
        for (var _ in 0.._n2223) {
            var _k2224 = input.loc();
            _v2222[_k2224] = input.text();
        }
        for (var (_bk2221, _av) in _v2222) {
            _f2219[_bk2221] = _av;
        }
    } else {
        var _v2225 = HashMap<Loc, String>();
        var _n2226 = input.count();
        for (var _ in 0.._n2226) {
            var _k2227 = input.loc();
            _v2225[_k2227] = input.text();
        }
        _f2219 = _v2225;
    }
    var _f2243 = HashSet<Loc>();
    var _tag2244 = input.unsigned();
    if (_tag2244 == 1) {
        for (var _bk2245 in base.stripped) {
            _f2243.insert(_bk2245);
        }
        var _v2246 = HashSet<Loc>();
        var _n2247 = input.count();
        for (var _ in 0.._n2247) {
            _v2246.insert(input.loc());
        }
        for (var _bk2245 in _v2246) {
            _f2243.insert(_bk2245);
        }
    } else {
        var _v2248 = HashSet<Loc>();
        var _n2249 = input.count();
        for (var _ in 0.._n2249) {
            _v2248.insert(input.loc());
        }
        _f2243 = _v2248;
    }
    var _frozen = input.flag();
    var _f2260 = Array<StructDef>();
    var _mode2263 = input.unsigned();
    if (_mode2263 == 2) {
        var _patched2266 = HashMap<ulong, StructDef>();
        var _n2261 = input.count();
        for (var _ in 0.._n2261) {
            var _name = input.text();
            var _slot = input.unsigned();
            if (input.merging) {
                _slot = struct_named(base.templates.structs, _name);
            }
            if (_slot >= base.templates.structs.count) {
                input.error = $"no struct {_name} to patch";
                break;
            }
            _patched2266[_slot] = _patch_t_read(input, base.templates.structs[_slot]);
        }
        ulong _bi2264 = 0;
        var _added = input.count();
        for (var _ in 0.._added) {
            var _at2265 = input.unsigned();
            while (_f2260.count < _at2265 or (input.merging and _bi2264 < base.templates.structs.count)) {
                var _p = _patched2266.try_get(_bi2264);
                _f2260.append(_p.is_value() ? _p.value() : base.templates.structs[_bi2264]);
                _bi2264 += 1;
            }
            _f2260.append(_m_StructDef_read(input));
        }
        while (_bi2264 < base.templates.structs.count) {
            var _p = _patched2266.try_get(_bi2264);
            _f2260.append(_p.is_value() ? _p.value() : base.templates.structs[_bi2264]);
            _bi2264 += 1;
        }
    } else {
        if (input.merging) {
            input.error = "structs written by place";
        }
        var _n2261 = input.count();
        for (var _ in 0.._n2261) {
            var _tag2262 = input.unsigned();
            if (_tag2262 & 1 == 1) {
                _f2260.append(
                    base.templates.structs[(_tag2262 >> 1) < base.templates.structs.count ? _tag2262 >> 1 : 0]
                );
            } else if (_tag2262 == 2) {
                var _was = base.templates.structs[input.unsigned()];
                _f2260.append(_patch_t_read(input, _was));
            } else {
                _f2260.append(_m_StructDef_read(input));
            }
        }
    }
    var _f2280 = Array<FunctionDef>();
    var _mode2283 = input.unsigned();
    if (_mode2283 == 2) {
        var _changed2269 = HashMap<ulong, FunctionDef>();
        var _nc2271 = input.count();
        for (var _ in 0.._nc2271) {
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
                _changed2269[_slot] = _el;
            } else {
                input.error = $"no {_name} to change";
            }
        }
        ulong _bi2284 = 0;
        var _n2281 = input.count();
        for (var _ in 0.._n2281) {
            var _at2285 = input.unsigned();
            while (_f2280.count < _at2285 or (input.merging and _bi2284 < base.templates.functions.count)) {
                var _c = _changed2269.try_get(_bi2284);
                _f2280.append(_c.is_value() ? _c.value() : base.templates.functions[_bi2284]);
                _bi2284 += 1;
            }
            _f2280.append(_m_FunctionDef_read(input));
        }
        while (_bi2284 < base.templates.functions.count) {
            var _c = _changed2269.try_get(_bi2284);
            _f2280.append(_c.is_value() ? _c.value() : base.templates.functions[_bi2284]);
            _bi2284 += 1;
        }
    } else if (_mode2283 == 3) {
        var _n2281 = input.count();
        for (var _ in 0.._n2281) {
            _f2280.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2281 = input.count();
        if (input.merging) {
            input.error = "tf" + " written by place";
        }
        for (var _ in 0.._n2281) {
            var _tag2282 = input.unsigned();
            if (_tag2282 & 1 == 1) {
                if (!input.merging) {
                    _f2280.append(base.templates.functions[_tag2282 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2280.append(_read);
                }
            }
        }
    }
    var _f2287 = Templates(_frozen, _f2260, _f2280);
    var _f2288 = DeltaBase.read_checked(input, base.checked);
    var _f2308 = HashMap<String, SpecRequest>();
    var _tag2309 = input.unsigned();
    if (_tag2309 == 1) {
        for (var (_bk2310, _bv) in base.spec_requests) {
            _f2308[_bk2310] = _bv;
        }
        var _v2311 = HashMap<String, SpecRequest>();
        var _n2312 = input.count();
        for (var _ in 0.._n2312) {
            var _k2313 = input.text();
            _v2311[_k2313] = _m_SpecRequest_read(input);
        }
        for (var (_bk2310, _av) in _v2311) {
            _f2308[_bk2310] = _av;
        }
    } else {
        var _v2314 = HashMap<String, SpecRequest>();
        var _n2315 = input.count();
        for (var _ in 0.._n2315) {
            var _k2316 = input.text();
            _v2314[_k2316] = _m_SpecRequest_read(input);
        }
        _f2308 = _v2314;
    }
    var _f2317 = input.flag();
    var _f2329 = Array<(Loc, String)>();
    var _tag2330 = input.unsigned();
    if (_tag2330 == 1) {
        input.unsigned();
        for (var _i2321 in 0..base.summaries_to_record.count) {
            _f2329.append(base.summaries_to_record[_i2321]);
        }
        var _more2332 = input.count();
        for (var _ in 0.._more2332) {
            var _t2333 = input.loc();
            var _t2334 = input.text();
            _f2329.append((_t2333, _t2334));
        }
    } else {
        var _v2335 = Array<(Loc, String)>();
        var _n2336 = input.count();
        for (var _ in 0.._n2336) {
            var _t2337 = input.loc();
            var _t2338 = input.text();
            _v2335.append((_t2337, _t2338));
        }
        _f2329 = _v2335;
    }
    var _f2369 = HashMap<String, Array<bool>>();
    var _tag2370 = input.unsigned();
    if (_tag2370 == 1) {
        for (var (_bk2371, _bv) in base.caller_copies) {
            _f2369[_bk2371] = _bv;
        }
        var _v2372 = HashMap<String, Array<bool>>();
        var _n2373 = input.count();
        for (var _ in 0.._n2373) {
            var _k2374 = input.text();
            var _v2375 = Array<bool>();
            var _n2376 = input.count();
            for (var _ in 0.._n2376) {
                _v2375.append(input.flag());
            }
            _v2372[_k2374] = _v2375;
        }
        for (var (_bk2371, _av) in _v2372) {
            _f2369[_bk2371] = _av;
        }
    } else {
        var _v2377 = HashMap<String, Array<bool>>();
        var _n2378 = input.count();
        for (var _ in 0.._n2378) {
            var _k2379 = input.text();
            var _v2380 = Array<bool>();
            var _n2381 = input.count();
            for (var _ in 0.._n2381) {
                _v2380.append(input.flag());
            }
            _v2377[_k2379] = _v2380;
        }
        _f2369 = _v2377;
    }
    var _f2383 = input.flag();
    return Module(
        _f1515,
        _f1548,
        _f1568,
        _f1587,
        _f1606,
        _f1625,
        _f1644,
        _f1663,
        _f1682,
        _f1701,
        _f1720,
        _f1732,
        _f1748,
        _f1767,
        _f1786,
        _f1805,
        _f1826,
        _f1855,
        _f1874,
        _f1887,
        _f1914,
        _f1961,
        _f2048,
        _f2074,
        _f2094,
        _f2120,
        _f2138,
        _f2164,
        _f2183,
        _f2196,
        _f2219,
        _f2243,
        _f2287,
        _f2288,
        _f2308,
        _f2317,
        _f2329,
        _f2369,
        _f2383
    );
}

_m_Module_index(value: Module, base: DeltaBase) {
    ulong _j1521 = 0;
    for (var _item1503 in value.imports) {
        var scratch = base.scratch();
        _a_Import_write(scratch, _item1503);
        base.add("imports", scratch, _j1521);
        _j1521 += 1;
    }
    if (base.verifying) {
        ulong _j1555 = 0;
        for (var _item1522 in value.structs) {
            var scratch = base.scratch();
            _m_StructDef_write(scratch, _item1522);
            base.add("s", scratch, _j1555);
            base.name("s", _item1522.name, _j1555);
            _patch_s_index(_item1522, base, _j1555);
            _j1555 += 1;
        }
    }
    base.ref_structs = value.structs.clone();
    base.ref_struct_parts = Array<StructDef>();
    for (var _item1522 in value.structs) {
        base.ref_struct_parts.append(_m_StructDef_shallow(_item1522));
    }
    ulong _j1574 = 0;
    for (var _item1556 in value.traits) {
        var scratch = base.scratch();
        _m_TraitDef_write(scratch, _item1556);
        base.add("traits", scratch, _j1574);
        _j1574 += 1;
    }
    ulong _j1593 = 0;
    for (var _item1575 in value.extensions) {
        var scratch = base.scratch();
        _m_ExtensionDef_write(scratch, _item1575);
        base.add("extensions", scratch, _j1593);
        _j1593 += 1;
    }
    if (base.verifying) {
        ulong _j1612 = 0;
        for (var _item1594 in value.functions) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item1594);
            base.add("functions", scratch, _j1612);
            base.name("functions", _item1594.name, _j1612);
            _j1612 += 1;
        }
    }
    base.ref_functions = value.functions.clone();
    ulong _j1631 = 0;
    for (var _item1613 in value.externs) {
        var scratch = base.scratch();
        _m_ExternDef_write(scratch, _item1613);
        base.add("externs", scratch, _j1631);
        _j1631 += 1;
    }
    ulong _j1650 = 0;
    for (var _item1632 in value.globals) {
        var scratch = base.scratch();
        _m_VariableDef_write(scratch, _item1632);
        base.add("globals", scratch, _j1650);
        _j1650 += 1;
    }
    ulong _j1669 = 0;
    for (var _item1651 in value.static_blocks) {
        var scratch = base.scratch();
        _m_ModuleStaticBlock_write(scratch, _item1651);
        base.add("static_blocks", scratch, _j1669);
        _j1669 += 1;
    }
    ulong _j1688 = 0;
    for (var _item1670 in value.enums) {
        var scratch = base.scratch();
        _m_EnumDef_write(scratch, _item1670);
        base.add("enums", scratch, _j1688);
        _j1688 += 1;
    }
    ulong _j1707 = 0;
    for (var _item1689 in value.struct_specs) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item1689);
        base.add("struct_specs", scratch, _j1707);
        _j1707 += 1;
    }
    ulong _j1726 = 0;
    for (var _item1708 in value.func_specs) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item1708);
        base.add("func_specs", scratch, _j1726);
        _j1726 += 1;
    }
    ulong _j1735 = 0;
    for (var _item1727 in value.type_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1727);
        base.add("type_aliases", scratch, _j1735);
        _j1735 += 1;
    }
    ulong _j1754 = 0;
    for (var _item1736 in value.withheld) {
        var scratch = base.scratch();
        _m_Withheld_write(scratch, _item1736);
        base.add("withheld", scratch, _j1754);
        _j1754 += 1;
    }
    ulong _j1773 = 0;
    for (var _item1755 in value.properties) {
        var scratch = base.scratch();
        _m_PropertyDef_write(scratch, _item1755);
        base.add("properties", scratch, _j1773);
        _j1773 += 1;
    }
    ulong _j1792 = 0;
    for (var _item1774 in value.type_uses) {
        var scratch = base.scratch();
        _m_TypeUse_write(scratch, _item1774);
        base.add("type_uses", scratch, _j1792);
        _j1792 += 1;
    }
    ulong _j1811 = 0;
    for (var _item1793 in value.use_contexts) {
        var scratch = base.scratch();
        _m_UseContext_write(scratch, _item1793);
        base.add("use_contexts", scratch, _j1811);
        _j1811 += 1;
    }
    var _xscratch1838 = base.scratch();
    for (var _xitem1839 in value.literal_args) {
        var (_t1840, _t1841, _t1842) = _xitem1839;
        _xscratch1838.loc(_t1840);
        _xscratch1838.unsigned(_t1841);
        _xscratch1838.loc(_t1842);
    }
    base.keep_list("literal_args", value.literal_args.count, _xscratch1838);
    ulong _j1861 = 0;
    for (var _item1843 in value.constrained_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1843);
        base.add("constrained_aliases", scratch, _j1861);
        _j1861 += 1;
    }
    ulong _j1880 = 0;
    for (var _item1862 in value.trait_types) {
        var scratch = base.scratch();
        _m_TraitType_write(scratch, _item1862);
        base.add("trait_types", scratch, _j1880);
        _j1880 += 1;
    }
    ulong _cj1884 = 0;
    for (var _conv1882 in value.conversions) {
        var _own1883 = RecordOut();
        _own1883.blank_locs = true;
        _m_Conversion_write(_own1883, _conv1882);
        base.add_hashed("conversions", interface_text(_own1883), _cj1884);
        _cj1884 += 1;
    }
    for (var (_key1888, _) in value.overload_sets) {
        var _kscratch1889 = base.scratch();
        _kscratch1889.text(_key1888);
        var _vscratch1890 = base.scratch();
        _vscratch1890.unsigned(value.overload_sets[_key1888].count);
        for (var _item1927 in value.overload_sets[_key1888]) {
            _vscratch1890.text(_item1927);
        }
        base.keep_entry("overload_sets", _kscratch1889, _vscratch1890);
    }
    for (var (_key1928, _) in value.overload_unions) {
        var _kscratch1929 = base.scratch();
        _kscratch1929.text(_key1928);
        var _vscratch1930 = base.scratch();
        _vscratch1930.unsigned(value.overload_unions[_key1928].count);
        for (var _item1978 in value.overload_unions[_key1928]) {
            _vscratch1930.unsigned(_item1978.count);
            for (var _item1979 in _item1978) {
                _vscratch1930.text(_item1979);
            }
        }
        base.keep_entry("overload_unions", _kscratch1929, _vscratch1930);
    }
    for (var (_key1980, _) in value.method_overload_sets) {
        var _kscratch1981 = base.scratch();
        _kscratch1981.text(_key1980);
        var _vscratch1982 = base.scratch();
        var _keys2068 = Array<(u8[], u8[], String)>();
        for (var (_key2067, _) in value.method_overload_sets[_key1980]) {
            var _scratch2069 = _vscratch1982.scratch();
            _scratch2069.text(_key2067);
            var _vscratch2071 = _vscratch1982.scratch();
            _vscratch2071.unsigned(value.method_overload_sets[_key1980][_key2067].count);
            for (var _item2072 in value.method_overload_sets[_key1980][_key2067]) {
                _vscratch2071.text(_item2072);
            }
            _keys2068.append((_scratch2069.finish(), _vscratch2071.finish(), _key2067));
        }
        _keys2068.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        _vscratch1982.unsigned(_keys2068.count);
        for (var (_bytes2070, _, _key2067) in _keys2068) {
            _vscratch1982.text(_key2067);
            _vscratch1982.unsigned(value.method_overload_sets[_key1980][_key2067].count);
            for (var _item2073 in value.method_overload_sets[_key1980][_key2067]) {
                _vscratch1982.text(_item2073);
            }
        }
        base.keep_entry("method_overload_sets", _kscratch1981, _vscratch1982);
    }
    for (var _key2075 in value.private_functions) {
        var _kscratch2076 = base.scratch();
        _kscratch2076.loc(_key2075);
        var _vscratch2077 = base.scratch();
        base.keep_entry("private_functions", _kscratch2076, _vscratch2077);
    }
    for (var _key2101 in value.file_private_functions) {
        var _kscratch2102 = base.scratch();
        _kscratch2102.loc(_key2101);
        var _vscratch2103 = base.scratch();
        base.keep_entry("file_private_functions", _kscratch2102, _vscratch2103);
    }
    var _xscratch2148 = base.scratch();
    for (var _xitem2149 in value.call_targets) {
        var (_t2150, _t2151) = _xitem2149;
        _xscratch2148.loc(_t2150);
        _xscratch2148.text(_t2151);
    }
    base.keep_list("call_targets", value.call_targets.count, _xscratch2148);
    for (var _item2152 in value.argument_names) {
        var _escratch2153 = base.scratch();
        var (_t2174, _t2175) = _item2152;
        _escratch2153.loc(_t2174);
        _escratch2153.text(_t2175);
        base.keep_entry("argument_names", _escratch2153, base.scratch());
    }
    var _xscratch2189 = base.scratch();
    for (var _xitem2190 in value.namespaces) {
        _xscratch2189.text(_xitem2190);
    }
    base.keep_list("namespaces", value.namespaces.count, _xscratch2189);
    var _xscratch2202 = base.scratch();
    for (var _xitem2203 in value.cached_files) {
        _xscratch2202.flag(_xitem2203);
    }
    base.keep_list("cached_files", value.cached_files.count, _xscratch2202);
    for (var (_key2204, _) in value.recorded_summaries) {
        var _kscratch2205 = base.scratch();
        _kscratch2205.loc(_key2204);
        var _vscratch2206 = base.scratch();
        _vscratch2206.text(value.recorded_summaries[_key2204]);
        base.keep_entry("recorded_summaries", _kscratch2205, _vscratch2206);
    }
    for (var _key2228 in value.stripped) {
        var _kscratch2229 = base.scratch();
        _kscratch2229.loc(_key2228);
        var _vscratch2230 = base.scratch();
        base.keep_entry("stripped", _kscratch2229, _vscratch2230);
    }
    if (base.verifying) {
        ulong _j2267 = 0;
        for (var _item2250 in value.templates.structs) {
            var scratch = base.scratch();
            _m_StructDef_write(scratch, _item2250);
            base.add("t", scratch, _j2267);
            base.name("t", _item2250.name, _j2267);
            _patch_t_index(_item2250, base, _j2267);
            _j2267 += 1;
        }
    }
    base.ref_templates = value.templates.structs.clone();
    base.ref_template_parts = Array<StructDef>();
    for (var _item2250 in value.templates.structs) {
        base.ref_template_parts.append(_m_StructDef_shallow(_item2250));
    }
    if (base.verifying) {
        ulong _j2286 = 0;
        for (var _item2268 in value.templates.functions) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2268);
            base.add("tf", scratch, _j2286);
            base.name("tf", _item2268.name, _j2286);
            _j2286 += 1;
        }
    }
    base.ref_template_functions = value.templates.functions.clone();
    base.keep_checked(value.checked);
    for (var (_key2289, _) in value.spec_requests) {
        var _kscratch2290 = base.scratch();
        _kscratch2290.text(_key2289);
        var _vscratch2291 = base.scratch();
        _m_SpecRequest_write(_vscratch2291, value.spec_requests[_key2289]);
        base.keep_entry("spec_requests", _kscratch2290, _vscratch2291);
    }
    var _xscratch2339 = base.scratch();
    for (var _xitem2340 in value.summaries_to_record) {
        var (_t2341, _t2342) = _xitem2340;
        _xscratch2339.loc(_t2341);
        _xscratch2339.text(_t2342);
    }
    base.keep_list("summaries_to_record", value.summaries_to_record.count, _xscratch2339);
    for (var (_key2343, _) in value.caller_copies) {
        var _kscratch2344 = base.scratch();
        _kscratch2344.text(_key2343);
        var _vscratch2345 = base.scratch();
        _vscratch2345.unsigned(value.caller_copies[_key2343].count);
        for (var _item2382 in value.caller_copies[_key2343]) {
            _vscratch2345.flag(_item2382);
        }
        base.keep_entry("caller_copies", _kscratch2344, _vscratch2345);
    }
}

_m_Module_index_resumed(value: Module, base: DeltaBase) {
    ulong _j1735 = 0;
    for (var _item1727 in value.type_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1727);
        base.add("type_aliases", scratch, _j1735);
        _j1735 += 1;
    }
    for (var (_key2204, _) in value.recorded_summaries) {
        var _kscratch2205 = base.scratch();
        _kscratch2205.loc(_key2204);
        var _vscratch2206 = base.scratch();
        _vscratch2206.text(value.recorded_summaries[_key2204]);
        base.keep_entry("recorded_summaries", _kscratch2205, _vscratch2206);
    }
    var _xscratch2339 = base.scratch();
    for (var _xitem2340 in value.summaries_to_record) {
        var (_t2341, _t2342) = _xitem2340;
        _xscratch2339.loc(_t2341);
        _xscratch2339.text(_t2342);
    }
    base.keep_list("summaries_to_record", value.summaries_to_record.count, _xscratch2339);
}

_patch_s_write(out: RecordOut, value: StructDef, base: DeltaBase, slot: ulong) {
    out.text(value.name);
    _m_TypeName_write(out, value.ty);
    var _seq2391 = base.ref_struct_parts[slot].generic_params;
    ulong _bj2392 = 0;
    var _news2393 = Array<ulong>();
    for (var _i2394 in 0..value.generic_params.count) {
        if (_bj2392 < _seq2391.count and value.generic_params[_i2394] === _seq2391[_bj2392]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_GenericParam_write(scratch, value.generic_params[_i2394]);
                base.verify_same($"s.{slot}.generic_params", _bj2392, scratch);
            }
            _bj2392 += 1;
        } else if (_bj2392 < _seq2391.count
            and _same_m_GenericParam(value.generic_params[_i2394], _seq2391[_bj2392], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_GenericParam_write(scratch, value.generic_params[_i2394]);
                base.verify_same($"s.{slot}.generic_params", _bj2392, scratch);
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
            _m_GenericParam_write(out, value.generic_params[_i2394]);
        }
        base.count("s.*.generic_params" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.generic_params" + " whole", 0);
        out.unsigned(value.generic_params.count);
        for (var _i2394 in 0..value.generic_params.count) {
            _m_GenericParam_write(out, value.generic_params[_i2394]);
        }
    }
    var _seq2407 = base.ref_struct_parts[slot].field_members;
    ulong _bj2408 = 0;
    var _news2409 = Array<ulong>();
    for (var _i2410 in 0..value.field_members.count) {
        if (_bj2408 < _seq2407.count and value.field_members[_i2410] === _seq2407[_bj2408]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_VariableDef_write(scratch, value.field_members[_i2410]);
                base.verify_same($"s.{slot}.field_members", _bj2408, scratch);
            }
            _bj2408 += 1;
        } else if (_bj2408 < _seq2407.count
            and _same_m_VariableDef(value.field_members[_i2410], _seq2407[_bj2408], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_VariableDef_write(scratch, value.field_members[_i2410]);
                base.verify_same($"s.{slot}.field_members", _bj2408, scratch);
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
            _m_VariableDef_write(out, value.field_members[_i2410]);
        }
        base.count("s.*.field_members" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.field_members" + " whole", 0);
        out.unsigned(value.field_members.count);
        for (var _i2410 in 0..value.field_members.count) {
            _m_VariableDef_write(out, value.field_members[_i2410]);
        }
    }
    var _seq2423 = base.ref_struct_parts[slot].method_members;
    ulong _bj2424 = 0;
    var _news2425 = Array<ulong>();
    for (var _i2426 in 0..value.method_members.count) {
        if (_bj2424 < _seq2423.count and value.method_members[_i2426] === _seq2423[_bj2424]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.method_members[_i2426]);
                base.verify_same($"s.{slot}.method_members", _bj2424, scratch);
            }
            _bj2424 += 1;
        } else if (_bj2424 < _seq2423.count
            and _same_m_FunctionDef(value.method_members[_i2426], _seq2423[_bj2424], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.method_members[_i2426]);
                base.verify_same($"s.{slot}.method_members", _bj2424, scratch);
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
            _m_FunctionDef_write(out, value.method_members[_i2426]);
        }
        base.count("s.*.method_members" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.method_members" + " whole", 0);
        out.unsigned(value.method_members.count);
        for (var _i2426 in 0..value.method_members.count) {
            _m_FunctionDef_write(out, value.method_members[_i2426]);
        }
    }
    var _seq2439 = base.ref_struct_parts[slot].generic_methods;
    ulong _bj2440 = 0;
    var _news2441 = Array<ulong>();
    for (var _i2442 in 0..value.generic_methods.count) {
        if (_bj2440 < _seq2439.count and value.generic_methods[_i2442] === _seq2439[_bj2440]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.generic_methods[_i2442]);
                base.verify_same($"s.{slot}.generic_methods", _bj2440, scratch);
            }
            _bj2440 += 1;
        } else if (_bj2440 < _seq2439.count
            and _same_m_FunctionDef(value.generic_methods[_i2442], _seq2439[_bj2440], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.generic_methods[_i2442]);
                base.verify_same($"s.{slot}.generic_methods", _bj2440, scratch);
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
            _m_FunctionDef_write(out, value.generic_methods[_i2442]);
        }
        base.count("s.*.generic_methods" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.generic_methods" + " whole", 0);
        out.unsigned(value.generic_methods.count);
        for (var _i2442 in 0..value.generic_methods.count) {
            _m_FunctionDef_write(out, value.generic_methods[_i2442]);
        }
    }
    var _seq2455 = base.ref_struct_parts[slot].constructors;
    ulong _bj2456 = 0;
    var _news2457 = Array<ulong>();
    for (var _i2458 in 0..value.constructors.count) {
        if (_bj2456 < _seq2455.count and value.constructors[_i2458] === _seq2455[_bj2456]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.constructors[_i2458]);
                base.verify_same($"s.{slot}.constructors", _bj2456, scratch);
            }
            _bj2456 += 1;
        } else if (_bj2456 < _seq2455.count
            and _same_m_FunctionDef(value.constructors[_i2458], _seq2455[_bj2456], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.constructors[_i2458]);
                base.verify_same($"s.{slot}.constructors", _bj2456, scratch);
            }
            _bj2456 += 1;
        } else {
            _news2457.append(_i2458);
        }
    }
    if (_bj2456 == _seq2455.count) {
        out.unsigned(2);
        out.unsigned(_news2457.count);
        for (var _i2458 in _news2457) {
            out.unsigned(_i2458);
            _m_FunctionDef_write(out, value.constructors[_i2458]);
        }
        base.count("s.*.constructors" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.constructors" + " whole", 0);
        out.unsigned(value.constructors.count);
        for (var _i2458 in 0..value.constructors.count) {
            _m_FunctionDef_write(out, value.constructors[_i2458]);
        }
    }
    _m_FunctionDef_write(out, value.destructor);
    _m_FunctionDef_write(out, value.acquire);
    _m_FunctionDef_write(out, value.release);
    var _seq2474 = base.ref_struct_parts[slot].traits;
    ulong _bj2475 = 0;
    var _news2476 = Array<ulong>();
    for (var _i2477 in 0..value.traits.count) {
        if (_bj2475 < _seq2474.count and value.traits[_i2477] === _seq2474[_bj2475]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_TypeName_write(scratch, value.traits[_i2477]);
                base.verify_same($"s.{slot}.traits", _bj2475, scratch);
            }
            _bj2475 += 1;
        } else if (_bj2475 < _seq2474.count and _same_m_TypeName(value.traits[_i2477], _seq2474[_bj2475], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_TypeName_write(scratch, value.traits[_i2477]);
                base.verify_same($"s.{slot}.traits", _bj2475, scratch);
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
            _m_TypeName_write(out, value.traits[_i2477]);
        }
        base.count("s.*.traits" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.traits" + " whole", 0);
        out.unsigned(value.traits.count);
        for (var _i2477 in 0..value.traits.count) {
            _m_TypeName_write(out, value.traits[_i2477]);
        }
    }
    var _seq2490 = base.ref_struct_parts[slot].attributes;
    ulong _bj2491 = 0;
    var _news2492 = Array<ulong>();
    for (var _i2493 in 0..value.attributes.count) {
        if (_bj2491 < _seq2490.count and value.attributes[_i2493] === _seq2490[_bj2491]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _a_Attribute_write(scratch, value.attributes[_i2493]);
                base.verify_same($"s.{slot}.attributes", _bj2491, scratch);
            }
            _bj2491 += 1;
        } else if (_bj2491 < _seq2490.count and _same_a_Attribute(value.attributes[_i2493], _seq2490[_bj2491], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _a_Attribute_write(scratch, value.attributes[_i2493]);
                base.verify_same($"s.{slot}.attributes", _bj2491, scratch);
            }
            _bj2491 += 1;
        } else {
            _news2492.append(_i2493);
        }
    }
    if (_bj2491 == _seq2490.count) {
        out.unsigned(2);
        out.unsigned(_news2492.count);
        for (var _i2493 in _news2492) {
            out.unsigned(_i2493);
            _a_Attribute_write(out, value.attributes[_i2493]);
        }
        base.count("s.*.attributes" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.attributes" + " whole", 0);
        out.unsigned(value.attributes.count);
        for (var _i2493 in 0..value.attributes.count) {
            _a_Attribute_write(out, value.attributes[_i2493]);
        }
    }
    out.loc(value.loc);
    if (value.enum_cases.is_value()) {
        out.unsigned(1);
        out.unsigned(value.enum_cases.value().count);
        for (var _item2502 in value.enum_cases.value()) {
            _m_EnumCaseDef_write(out, _item2502);
        }
    } else {
        out.unsigned(0);
    }
}

_patch_s_read(input: RecordIn, was: StructDef): StructDef {
    var _f2384 = input.text();
    var _f2385 = _m_TypeName_read(input);
    var _f2395 = Array<GenericParam>();
    var _mode2398 = input.unsigned();
    if (_mode2398 == 2) {
        var _changed2387 = HashMap<ulong, GenericParam>();
        ulong _bi2399 = 0;
        var _n2396 = input.count();
        for (var _ in 0.._n2396) {
            var _at2400 = input.unsigned();
            while (_f2395.count < _at2400 or (input.merging and _bi2399 < was.generic_params.count)) {
                var _c = _changed2387.try_get(_bi2399);
                _f2395.append(_c.is_value() ? _c.value() : was.generic_params[_bi2399]);
                _bi2399 += 1;
            }
            _f2395.append(_m_GenericParam_read(input));
        }
        while (_bi2399 < was.generic_params.count) {
            var _c = _changed2387.try_get(_bi2399);
            _f2395.append(_c.is_value() ? _c.value() : was.generic_params[_bi2399]);
            _bi2399 += 1;
        }
    } else if (_mode2398 == 3) {
        var _n2396 = input.count();
        for (var _ in 0.._n2396) {
            _f2395.append(_m_GenericParam_read(input));
        }
    } else {
        var _n2396 = input.count();
        if (input.merging) {
            input.error = "s.*.generic_params" + " written by place";
        }
        for (var _ in 0.._n2396) {
            var _tag2397 = input.unsigned();
            if (_tag2397 & 1 == 1) {
                if (!input.merging) {
                    _f2395.append(was.generic_params[_tag2397 >> 1]);
                }
            } else {
                var _read = _m_GenericParam_read(input);
                if (!input.merging or true) {
                    _f2395.append(_read);
                }
            }
        }
    }
    var _f2411 = Array<VariableDef>();
    var _mode2414 = input.unsigned();
    if (_mode2414 == 2) {
        var _changed2403 = HashMap<ulong, VariableDef>();
        ulong _bi2415 = 0;
        var _n2412 = input.count();
        for (var _ in 0.._n2412) {
            var _at2416 = input.unsigned();
            while (_f2411.count < _at2416 or (input.merging and _bi2415 < was.field_members.count)) {
                var _c = _changed2403.try_get(_bi2415);
                _f2411.append(_c.is_value() ? _c.value() : was.field_members[_bi2415]);
                _bi2415 += 1;
            }
            _f2411.append(_m_VariableDef_read(input));
        }
        while (_bi2415 < was.field_members.count) {
            var _c = _changed2403.try_get(_bi2415);
            _f2411.append(_c.is_value() ? _c.value() : was.field_members[_bi2415]);
            _bi2415 += 1;
        }
    } else if (_mode2414 == 3) {
        var _n2412 = input.count();
        for (var _ in 0.._n2412) {
            _f2411.append(_m_VariableDef_read(input));
        }
    } else {
        var _n2412 = input.count();
        if (input.merging) {
            input.error = "s.*.field_members" + " written by place";
        }
        for (var _ in 0.._n2412) {
            var _tag2413 = input.unsigned();
            if (_tag2413 & 1 == 1) {
                if (!input.merging) {
                    _f2411.append(was.field_members[_tag2413 >> 1]);
                }
            } else {
                var _read = _m_VariableDef_read(input);
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
            while (_f2427.count < _at2432 or (input.merging and _bi2431 < was.method_members.count)) {
                var _c = _changed2419.try_get(_bi2431);
                _f2427.append(_c.is_value() ? _c.value() : was.method_members[_bi2431]);
                _bi2431 += 1;
            }
            _f2427.append(_m_FunctionDef_read(input));
        }
        while (_bi2431 < was.method_members.count) {
            var _c = _changed2419.try_get(_bi2431);
            _f2427.append(_c.is_value() ? _c.value() : was.method_members[_bi2431]);
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
            input.error = "s.*.method_members" + " written by place";
        }
        for (var _ in 0.._n2428) {
            var _tag2429 = input.unsigned();
            if (_tag2429 & 1 == 1) {
                if (!input.merging) {
                    _f2427.append(was.method_members[_tag2429 >> 1]);
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
            while (_f2443.count < _at2448 or (input.merging and _bi2447 < was.generic_methods.count)) {
                var _c = _changed2435.try_get(_bi2447);
                _f2443.append(_c.is_value() ? _c.value() : was.generic_methods[_bi2447]);
                _bi2447 += 1;
            }
            _f2443.append(_m_FunctionDef_read(input));
        }
        while (_bi2447 < was.generic_methods.count) {
            var _c = _changed2435.try_get(_bi2447);
            _f2443.append(_c.is_value() ? _c.value() : was.generic_methods[_bi2447]);
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
            input.error = "s.*.generic_methods" + " written by place";
        }
        for (var _ in 0.._n2444) {
            var _tag2445 = input.unsigned();
            if (_tag2445 & 1 == 1) {
                if (!input.merging) {
                    _f2443.append(was.generic_methods[_tag2445 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2443.append(_read);
                }
            }
        }
    }
    var _f2459 = Array<FunctionDef>();
    var _mode2462 = input.unsigned();
    if (_mode2462 == 2) {
        var _changed2451 = HashMap<ulong, FunctionDef>();
        ulong _bi2463 = 0;
        var _n2460 = input.count();
        for (var _ in 0.._n2460) {
            var _at2464 = input.unsigned();
            while (_f2459.count < _at2464 or (input.merging and _bi2463 < was.constructors.count)) {
                var _c = _changed2451.try_get(_bi2463);
                _f2459.append(_c.is_value() ? _c.value() : was.constructors[_bi2463]);
                _bi2463 += 1;
            }
            _f2459.append(_m_FunctionDef_read(input));
        }
        while (_bi2463 < was.constructors.count) {
            var _c = _changed2451.try_get(_bi2463);
            _f2459.append(_c.is_value() ? _c.value() : was.constructors[_bi2463]);
            _bi2463 += 1;
        }
    } else if (_mode2462 == 3) {
        var _n2460 = input.count();
        for (var _ in 0.._n2460) {
            _f2459.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2460 = input.count();
        if (input.merging) {
            input.error = "s.*.constructors" + " written by place";
        }
        for (var _ in 0.._n2460) {
            var _tag2461 = input.unsigned();
            if (_tag2461 & 1 == 1) {
                if (!input.merging) {
                    _f2459.append(was.constructors[_tag2461 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2459.append(_read);
                }
            }
        }
    }
    var _f2466 = _m_FunctionDef_read(input);
    var _f2467 = _m_FunctionDef_read(input);
    var _f2468 = _m_FunctionDef_read(input);
    var _f2478 = Array<TypeName>();
    var _mode2481 = input.unsigned();
    if (_mode2481 == 2) {
        var _changed2470 = HashMap<ulong, TypeName>();
        ulong _bi2482 = 0;
        var _n2479 = input.count();
        for (var _ in 0.._n2479) {
            var _at2483 = input.unsigned();
            while (_f2478.count < _at2483 or (input.merging and _bi2482 < was.traits.count)) {
                var _c = _changed2470.try_get(_bi2482);
                _f2478.append(_c.is_value() ? _c.value() : was.traits[_bi2482]);
                _bi2482 += 1;
            }
            _f2478.append(_m_TypeName_read(input));
        }
        while (_bi2482 < was.traits.count) {
            var _c = _changed2470.try_get(_bi2482);
            _f2478.append(_c.is_value() ? _c.value() : was.traits[_bi2482]);
            _bi2482 += 1;
        }
    } else if (_mode2481 == 3) {
        var _n2479 = input.count();
        for (var _ in 0.._n2479) {
            _f2478.append(_m_TypeName_read(input));
        }
    } else {
        var _n2479 = input.count();
        if (input.merging) {
            input.error = "s.*.traits" + " written by place";
        }
        for (var _ in 0.._n2479) {
            var _tag2480 = input.unsigned();
            if (_tag2480 & 1 == 1) {
                if (!input.merging) {
                    _f2478.append(was.traits[_tag2480 >> 1]);
                }
            } else {
                var _read = _m_TypeName_read(input);
                if (!input.merging or true) {
                    _f2478.append(_read);
                }
            }
        }
    }
    var _f2494 = Array<ast.Attribute>();
    var _mode2497 = input.unsigned();
    if (_mode2497 == 2) {
        var _changed2486 = HashMap<ulong, ast.Attribute>();
        ulong _bi2498 = 0;
        var _n2495 = input.count();
        for (var _ in 0.._n2495) {
            var _at2499 = input.unsigned();
            while (_f2494.count < _at2499 or (input.merging and _bi2498 < was.attributes.count)) {
                var _c = _changed2486.try_get(_bi2498);
                _f2494.append(_c.is_value() ? _c.value() : was.attributes[_bi2498]);
                _bi2498 += 1;
            }
            _f2494.append(_a_Attribute_read(input));
        }
        while (_bi2498 < was.attributes.count) {
            var _c = _changed2486.try_get(_bi2498);
            _f2494.append(_c.is_value() ? _c.value() : was.attributes[_bi2498]);
            _bi2498 += 1;
        }
    } else if (_mode2497 == 3) {
        var _n2495 = input.count();
        for (var _ in 0.._n2495) {
            _f2494.append(_a_Attribute_read(input));
        }
    } else {
        var _n2495 = input.count();
        if (input.merging) {
            input.error = "s.*.attributes" + " written by place";
        }
        for (var _ in 0.._n2495) {
            var _tag2496 = input.unsigned();
            if (_tag2496 & 1 == 1) {
                if (!input.merging) {
                    _f2494.append(was.attributes[_tag2496 >> 1]);
                }
            } else {
                var _read = _a_Attribute_read(input);
                if (!input.merging or true) {
                    _f2494.append(_read);
                }
            }
        }
    }
    var _f2501 = input.loc();
    var _o2503 = Optional<Array<EnumCaseDef>>.Empty;
    if (input.unsigned() == 1) {
        var _v2504 = Array<EnumCaseDef>();
        var _n2505 = input.count();
        for (var _ in 0.._n2505) {
            _v2504.append(_m_EnumCaseDef_read(input));
        }
        _o2503 = Optional<Array<EnumCaseDef>>.Value(_v2504);
    }
    var _f2506 = _o2503;
    return StructDef(
        _f2384, _f2385, _f2395, _f2411, _f2427, _f2443, _f2459, _f2466, _f2467, _f2468, _f2478, _f2494, _f2501, _f2506
    );
}

_patch_s_index(value: StructDef, base: DeltaBase, slot: ulong) {
    if (base.verifying) {
        ulong _j2401 = 0;
        for (var _item2386 in value.generic_params) {
            var scratch = base.scratch();
            _m_GenericParam_write(scratch, _item2386);
            base.add($"s.{slot}.generic_params", scratch, _j2401);
            _j2401 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2417 = 0;
        for (var _item2402 in value.field_members) {
            var scratch = base.scratch();
            _m_VariableDef_write(scratch, _item2402);
            base.add($"s.{slot}.field_members", scratch, _j2417);
            _j2417 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2433 = 0;
        for (var _item2418 in value.method_members) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2418);
            base.add($"s.{slot}.method_members", scratch, _j2433);
            _j2433 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2449 = 0;
        for (var _item2434 in value.generic_methods) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2434);
            base.add($"s.{slot}.generic_methods", scratch, _j2449);
            _j2449 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2465 = 0;
        for (var _item2450 in value.constructors) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2450);
            base.add($"s.{slot}.constructors", scratch, _j2465);
            _j2465 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2484 = 0;
        for (var _item2469 in value.traits) {
            var scratch = base.scratch();
            _m_TypeName_write(scratch, _item2469);
            base.add($"s.{slot}.traits", scratch, _j2484);
            _j2484 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2500 = 0;
        for (var _item2485 in value.attributes) {
            var scratch = base.scratch();
            _a_Attribute_write(scratch, _item2485);
            base.add($"s.{slot}.attributes", scratch, _j2500);
            _j2500 += 1;
        }
    }
}

_patch_t_write(out: RecordOut, value: StructDef, base: DeltaBase, slot: ulong) {
    out.text(value.name);
    _m_TypeName_write(out, value.ty);
    var _seq2514 = base.ref_template_parts[slot].generic_params;
    ulong _bj2515 = 0;
    var _news2516 = Array<ulong>();
    for (var _i2517 in 0..value.generic_params.count) {
        if (_bj2515 < _seq2514.count and value.generic_params[_i2517] === _seq2514[_bj2515]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_GenericParam_write(scratch, value.generic_params[_i2517]);
                base.verify_same($"t.{slot}.generic_params", _bj2515, scratch);
            }
            _bj2515 += 1;
        } else if (_bj2515 < _seq2514.count
            and _same_m_GenericParam(value.generic_params[_i2517], _seq2514[_bj2515], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_GenericParam_write(scratch, value.generic_params[_i2517]);
                base.verify_same($"t.{slot}.generic_params", _bj2515, scratch);
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
    var _seq2530 = base.ref_template_parts[slot].field_members;
    ulong _bj2531 = 0;
    var _news2532 = Array<ulong>();
    for (var _i2533 in 0..value.field_members.count) {
        if (_bj2531 < _seq2530.count and value.field_members[_i2533] === _seq2530[_bj2531]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_VariableDef_write(scratch, value.field_members[_i2533]);
                base.verify_same($"t.{slot}.field_members", _bj2531, scratch);
            }
            _bj2531 += 1;
        } else if (_bj2531 < _seq2530.count
            and _same_m_VariableDef(value.field_members[_i2533], _seq2530[_bj2531], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_VariableDef_write(scratch, value.field_members[_i2533]);
                base.verify_same($"t.{slot}.field_members", _bj2531, scratch);
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
            _m_VariableDef_write(out, value.field_members[_i2533]);
        }
        base.count("t.*.field_members" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.field_members" + " whole", 0);
        out.unsigned(value.field_members.count);
        for (var _i2533 in 0..value.field_members.count) {
            _m_VariableDef_write(out, value.field_members[_i2533]);
        }
    }
    var _seq2546 = base.ref_template_parts[slot].method_members;
    ulong _bj2547 = 0;
    var _news2548 = Array<ulong>();
    for (var _i2549 in 0..value.method_members.count) {
        if (_bj2547 < _seq2546.count and value.method_members[_i2549] === _seq2546[_bj2547]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.method_members[_i2549]);
                base.verify_same($"t.{slot}.method_members", _bj2547, scratch);
            }
            _bj2547 += 1;
        } else if (_bj2547 < _seq2546.count
            and _same_m_FunctionDef(value.method_members[_i2549], _seq2546[_bj2547], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.method_members[_i2549]);
                base.verify_same($"t.{slot}.method_members", _bj2547, scratch);
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
            _m_FunctionDef_write(out, value.method_members[_i2549]);
        }
        base.count("t.*.method_members" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.method_members" + " whole", 0);
        out.unsigned(value.method_members.count);
        for (var _i2549 in 0..value.method_members.count) {
            _m_FunctionDef_write(out, value.method_members[_i2549]);
        }
    }
    var _seq2562 = base.ref_template_parts[slot].generic_methods;
    ulong _bj2563 = 0;
    var _news2564 = Array<ulong>();
    for (var _i2565 in 0..value.generic_methods.count) {
        if (_bj2563 < _seq2562.count and value.generic_methods[_i2565] === _seq2562[_bj2563]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.generic_methods[_i2565]);
                base.verify_same($"t.{slot}.generic_methods", _bj2563, scratch);
            }
            _bj2563 += 1;
        } else if (_bj2563 < _seq2562.count
            and _same_m_FunctionDef(value.generic_methods[_i2565], _seq2562[_bj2563], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.generic_methods[_i2565]);
                base.verify_same($"t.{slot}.generic_methods", _bj2563, scratch);
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
            _m_FunctionDef_write(out, value.generic_methods[_i2565]);
        }
        base.count("t.*.generic_methods" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.generic_methods" + " whole", 0);
        out.unsigned(value.generic_methods.count);
        for (var _i2565 in 0..value.generic_methods.count) {
            _m_FunctionDef_write(out, value.generic_methods[_i2565]);
        }
    }
    var _seq2578 = base.ref_template_parts[slot].constructors;
    ulong _bj2579 = 0;
    var _news2580 = Array<ulong>();
    for (var _i2581 in 0..value.constructors.count) {
        if (_bj2579 < _seq2578.count and value.constructors[_i2581] === _seq2578[_bj2579]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.constructors[_i2581]);
                base.verify_same($"t.{slot}.constructors", _bj2579, scratch);
            }
            _bj2579 += 1;
        } else if (_bj2579 < _seq2578.count
            and _same_m_FunctionDef(value.constructors[_i2581], _seq2578[_bj2579], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.constructors[_i2581]);
                base.verify_same($"t.{slot}.constructors", _bj2579, scratch);
            }
            _bj2579 += 1;
        } else {
            _news2580.append(_i2581);
        }
    }
    if (_bj2579 == _seq2578.count) {
        out.unsigned(2);
        out.unsigned(_news2580.count);
        for (var _i2581 in _news2580) {
            out.unsigned(_i2581);
            _m_FunctionDef_write(out, value.constructors[_i2581]);
        }
        base.count("t.*.constructors" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.constructors" + " whole", 0);
        out.unsigned(value.constructors.count);
        for (var _i2581 in 0..value.constructors.count) {
            _m_FunctionDef_write(out, value.constructors[_i2581]);
        }
    }
    _m_FunctionDef_write(out, value.destructor);
    _m_FunctionDef_write(out, value.acquire);
    _m_FunctionDef_write(out, value.release);
    var _seq2597 = base.ref_template_parts[slot].traits;
    ulong _bj2598 = 0;
    var _news2599 = Array<ulong>();
    for (var _i2600 in 0..value.traits.count) {
        if (_bj2598 < _seq2597.count and value.traits[_i2600] === _seq2597[_bj2598]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_TypeName_write(scratch, value.traits[_i2600]);
                base.verify_same($"t.{slot}.traits", _bj2598, scratch);
            }
            _bj2598 += 1;
        } else if (_bj2598 < _seq2597.count and _same_m_TypeName(value.traits[_i2600], _seq2597[_bj2598], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_TypeName_write(scratch, value.traits[_i2600]);
                base.verify_same($"t.{slot}.traits", _bj2598, scratch);
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
            _m_TypeName_write(out, value.traits[_i2600]);
        }
        base.count("t.*.traits" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.traits" + " whole", 0);
        out.unsigned(value.traits.count);
        for (var _i2600 in 0..value.traits.count) {
            _m_TypeName_write(out, value.traits[_i2600]);
        }
    }
    var _seq2613 = base.ref_template_parts[slot].attributes;
    ulong _bj2614 = 0;
    var _news2615 = Array<ulong>();
    for (var _i2616 in 0..value.attributes.count) {
        if (_bj2614 < _seq2613.count and value.attributes[_i2616] === _seq2613[_bj2614]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _a_Attribute_write(scratch, value.attributes[_i2616]);
                base.verify_same($"t.{slot}.attributes", _bj2614, scratch);
            }
            _bj2614 += 1;
        } else if (_bj2614 < _seq2613.count and _same_a_Attribute(value.attributes[_i2616], _seq2613[_bj2614], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _a_Attribute_write(scratch, value.attributes[_i2616]);
                base.verify_same($"t.{slot}.attributes", _bj2614, scratch);
            }
            _bj2614 += 1;
        } else {
            _news2615.append(_i2616);
        }
    }
    if (_bj2614 == _seq2613.count) {
        out.unsigned(2);
        out.unsigned(_news2615.count);
        for (var _i2616 in _news2615) {
            out.unsigned(_i2616);
            _a_Attribute_write(out, value.attributes[_i2616]);
        }
        base.count("t.*.attributes" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.attributes" + " whole", 0);
        out.unsigned(value.attributes.count);
        for (var _i2616 in 0..value.attributes.count) {
            _a_Attribute_write(out, value.attributes[_i2616]);
        }
    }
    out.loc(value.loc);
    if (value.enum_cases.is_value()) {
        out.unsigned(1);
        out.unsigned(value.enum_cases.value().count);
        for (var _item2625 in value.enum_cases.value()) {
            _m_EnumCaseDef_write(out, _item2625);
        }
    } else {
        out.unsigned(0);
    }
}

_patch_t_read(input: RecordIn, was: StructDef): StructDef {
    var _f2507 = input.text();
    var _f2508 = _m_TypeName_read(input);
    var _f2518 = Array<GenericParam>();
    var _mode2521 = input.unsigned();
    if (_mode2521 == 2) {
        var _changed2510 = HashMap<ulong, GenericParam>();
        ulong _bi2522 = 0;
        var _n2519 = input.count();
        for (var _ in 0.._n2519) {
            var _at2523 = input.unsigned();
            while (_f2518.count < _at2523 or (input.merging and _bi2522 < was.generic_params.count)) {
                var _c = _changed2510.try_get(_bi2522);
                _f2518.append(_c.is_value() ? _c.value() : was.generic_params[_bi2522]);
                _bi2522 += 1;
            }
            _f2518.append(_m_GenericParam_read(input));
        }
        while (_bi2522 < was.generic_params.count) {
            var _c = _changed2510.try_get(_bi2522);
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
    var _f2534 = Array<VariableDef>();
    var _mode2537 = input.unsigned();
    if (_mode2537 == 2) {
        var _changed2526 = HashMap<ulong, VariableDef>();
        ulong _bi2538 = 0;
        var _n2535 = input.count();
        for (var _ in 0.._n2535) {
            var _at2539 = input.unsigned();
            while (_f2534.count < _at2539 or (input.merging and _bi2538 < was.field_members.count)) {
                var _c = _changed2526.try_get(_bi2538);
                _f2534.append(_c.is_value() ? _c.value() : was.field_members[_bi2538]);
                _bi2538 += 1;
            }
            _f2534.append(_m_VariableDef_read(input));
        }
        while (_bi2538 < was.field_members.count) {
            var _c = _changed2526.try_get(_bi2538);
            _f2534.append(_c.is_value() ? _c.value() : was.field_members[_bi2538]);
            _bi2538 += 1;
        }
    } else if (_mode2537 == 3) {
        var _n2535 = input.count();
        for (var _ in 0.._n2535) {
            _f2534.append(_m_VariableDef_read(input));
        }
    } else {
        var _n2535 = input.count();
        if (input.merging) {
            input.error = "t.*.field_members" + " written by place";
        }
        for (var _ in 0.._n2535) {
            var _tag2536 = input.unsigned();
            if (_tag2536 & 1 == 1) {
                if (!input.merging) {
                    _f2534.append(was.field_members[_tag2536 >> 1]);
                }
            } else {
                var _read = _m_VariableDef_read(input);
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
            while (_f2550.count < _at2555 or (input.merging and _bi2554 < was.method_members.count)) {
                var _c = _changed2542.try_get(_bi2554);
                _f2550.append(_c.is_value() ? _c.value() : was.method_members[_bi2554]);
                _bi2554 += 1;
            }
            _f2550.append(_m_FunctionDef_read(input));
        }
        while (_bi2554 < was.method_members.count) {
            var _c = _changed2542.try_get(_bi2554);
            _f2550.append(_c.is_value() ? _c.value() : was.method_members[_bi2554]);
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
            input.error = "t.*.method_members" + " written by place";
        }
        for (var _ in 0.._n2551) {
            var _tag2552 = input.unsigned();
            if (_tag2552 & 1 == 1) {
                if (!input.merging) {
                    _f2550.append(was.method_members[_tag2552 >> 1]);
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
            while (_f2566.count < _at2571 or (input.merging and _bi2570 < was.generic_methods.count)) {
                var _c = _changed2558.try_get(_bi2570);
                _f2566.append(_c.is_value() ? _c.value() : was.generic_methods[_bi2570]);
                _bi2570 += 1;
            }
            _f2566.append(_m_FunctionDef_read(input));
        }
        while (_bi2570 < was.generic_methods.count) {
            var _c = _changed2558.try_get(_bi2570);
            _f2566.append(_c.is_value() ? _c.value() : was.generic_methods[_bi2570]);
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
            input.error = "t.*.generic_methods" + " written by place";
        }
        for (var _ in 0.._n2567) {
            var _tag2568 = input.unsigned();
            if (_tag2568 & 1 == 1) {
                if (!input.merging) {
                    _f2566.append(was.generic_methods[_tag2568 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2566.append(_read);
                }
            }
        }
    }
    var _f2582 = Array<FunctionDef>();
    var _mode2585 = input.unsigned();
    if (_mode2585 == 2) {
        var _changed2574 = HashMap<ulong, FunctionDef>();
        ulong _bi2586 = 0;
        var _n2583 = input.count();
        for (var _ in 0.._n2583) {
            var _at2587 = input.unsigned();
            while (_f2582.count < _at2587 or (input.merging and _bi2586 < was.constructors.count)) {
                var _c = _changed2574.try_get(_bi2586);
                _f2582.append(_c.is_value() ? _c.value() : was.constructors[_bi2586]);
                _bi2586 += 1;
            }
            _f2582.append(_m_FunctionDef_read(input));
        }
        while (_bi2586 < was.constructors.count) {
            var _c = _changed2574.try_get(_bi2586);
            _f2582.append(_c.is_value() ? _c.value() : was.constructors[_bi2586]);
            _bi2586 += 1;
        }
    } else if (_mode2585 == 3) {
        var _n2583 = input.count();
        for (var _ in 0.._n2583) {
            _f2582.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2583 = input.count();
        if (input.merging) {
            input.error = "t.*.constructors" + " written by place";
        }
        for (var _ in 0.._n2583) {
            var _tag2584 = input.unsigned();
            if (_tag2584 & 1 == 1) {
                if (!input.merging) {
                    _f2582.append(was.constructors[_tag2584 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2582.append(_read);
                }
            }
        }
    }
    var _f2589 = _m_FunctionDef_read(input);
    var _f2590 = _m_FunctionDef_read(input);
    var _f2591 = _m_FunctionDef_read(input);
    var _f2601 = Array<TypeName>();
    var _mode2604 = input.unsigned();
    if (_mode2604 == 2) {
        var _changed2593 = HashMap<ulong, TypeName>();
        ulong _bi2605 = 0;
        var _n2602 = input.count();
        for (var _ in 0.._n2602) {
            var _at2606 = input.unsigned();
            while (_f2601.count < _at2606 or (input.merging and _bi2605 < was.traits.count)) {
                var _c = _changed2593.try_get(_bi2605);
                _f2601.append(_c.is_value() ? _c.value() : was.traits[_bi2605]);
                _bi2605 += 1;
            }
            _f2601.append(_m_TypeName_read(input));
        }
        while (_bi2605 < was.traits.count) {
            var _c = _changed2593.try_get(_bi2605);
            _f2601.append(_c.is_value() ? _c.value() : was.traits[_bi2605]);
            _bi2605 += 1;
        }
    } else if (_mode2604 == 3) {
        var _n2602 = input.count();
        for (var _ in 0.._n2602) {
            _f2601.append(_m_TypeName_read(input));
        }
    } else {
        var _n2602 = input.count();
        if (input.merging) {
            input.error = "t.*.traits" + " written by place";
        }
        for (var _ in 0.._n2602) {
            var _tag2603 = input.unsigned();
            if (_tag2603 & 1 == 1) {
                if (!input.merging) {
                    _f2601.append(was.traits[_tag2603 >> 1]);
                }
            } else {
                var _read = _m_TypeName_read(input);
                if (!input.merging or true) {
                    _f2601.append(_read);
                }
            }
        }
    }
    var _f2617 = Array<ast.Attribute>();
    var _mode2620 = input.unsigned();
    if (_mode2620 == 2) {
        var _changed2609 = HashMap<ulong, ast.Attribute>();
        ulong _bi2621 = 0;
        var _n2618 = input.count();
        for (var _ in 0.._n2618) {
            var _at2622 = input.unsigned();
            while (_f2617.count < _at2622 or (input.merging and _bi2621 < was.attributes.count)) {
                var _c = _changed2609.try_get(_bi2621);
                _f2617.append(_c.is_value() ? _c.value() : was.attributes[_bi2621]);
                _bi2621 += 1;
            }
            _f2617.append(_a_Attribute_read(input));
        }
        while (_bi2621 < was.attributes.count) {
            var _c = _changed2609.try_get(_bi2621);
            _f2617.append(_c.is_value() ? _c.value() : was.attributes[_bi2621]);
            _bi2621 += 1;
        }
    } else if (_mode2620 == 3) {
        var _n2618 = input.count();
        for (var _ in 0.._n2618) {
            _f2617.append(_a_Attribute_read(input));
        }
    } else {
        var _n2618 = input.count();
        if (input.merging) {
            input.error = "t.*.attributes" + " written by place";
        }
        for (var _ in 0.._n2618) {
            var _tag2619 = input.unsigned();
            if (_tag2619 & 1 == 1) {
                if (!input.merging) {
                    _f2617.append(was.attributes[_tag2619 >> 1]);
                }
            } else {
                var _read = _a_Attribute_read(input);
                if (!input.merging or true) {
                    _f2617.append(_read);
                }
            }
        }
    }
    var _f2624 = input.loc();
    var _o2626 = Optional<Array<EnumCaseDef>>.Empty;
    if (input.unsigned() == 1) {
        var _v2627 = Array<EnumCaseDef>();
        var _n2628 = input.count();
        for (var _ in 0.._n2628) {
            _v2627.append(_m_EnumCaseDef_read(input));
        }
        _o2626 = Optional<Array<EnumCaseDef>>.Value(_v2627);
    }
    var _f2629 = _o2626;
    return StructDef(
        _f2507, _f2508, _f2518, _f2534, _f2550, _f2566, _f2582, _f2589, _f2590, _f2591, _f2601, _f2617, _f2624, _f2629
    );
}

_patch_t_index(value: StructDef, base: DeltaBase, slot: ulong) {
    if (base.verifying) {
        ulong _j2524 = 0;
        for (var _item2509 in value.generic_params) {
            var scratch = base.scratch();
            _m_GenericParam_write(scratch, _item2509);
            base.add($"t.{slot}.generic_params", scratch, _j2524);
            _j2524 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2540 = 0;
        for (var _item2525 in value.field_members) {
            var scratch = base.scratch();
            _m_VariableDef_write(scratch, _item2525);
            base.add($"t.{slot}.field_members", scratch, _j2540);
            _j2540 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2556 = 0;
        for (var _item2541 in value.method_members) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2541);
            base.add($"t.{slot}.method_members", scratch, _j2556);
            _j2556 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2572 = 0;
        for (var _item2557 in value.generic_methods) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2557);
            base.add($"t.{slot}.generic_methods", scratch, _j2572);
            _j2572 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2588 = 0;
        for (var _item2573 in value.constructors) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2573);
            base.add($"t.{slot}.constructors", scratch, _j2588);
            _j2588 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2607 = 0;
        for (var _item2592 in value.traits) {
            var scratch = base.scratch();
            _m_TypeName_write(scratch, _item2592);
            base.add($"t.{slot}.traits", scratch, _j2607);
            _j2607 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2623 = 0;
        for (var _item2608 in value.attributes) {
            var scratch = base.scratch();
            _a_Attribute_write(scratch, _item2608);
            base.add($"t.{slot}.attributes", scratch, _j2623);
            _j2623 += 1;
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
        for (var _item2630 in value.imports) {
            _a_Import_write(out, _item2630);
        }
        found.append(("imports", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.structs.count);
        for (var _item2631 in value.structs) {
            _m_StructDef_write(out, _item2631);
        }
        found.append(("structs", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.blank_bodies = false;
        out.unsigned(value.traits.count);
        for (var _item2632 in value.traits) {
            _m_TraitDef_write(out, _item2632);
        }
        found.append(("traits", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.extensions.count);
        for (var _item2633 in value.extensions) {
            _m_ExtensionDef_write(out, _item2633);
        }
        found.append(("extensions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.functions.count);
        for (var _item2634 in value.functions) {
            _m_FunctionDef_write(out, _item2634);
        }
        found.append(("functions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.externs.count);
        for (var _item2635 in value.externs) {
            _m_ExternDef_write(out, _item2635);
        }
        found.append(("externs", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.globals.count);
        for (var _item2636 in value.globals) {
            _m_VariableDef_write(out, _item2636);
        }
        found.append(("globals", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.static_blocks.count);
        for (var _item2637 in value.static_blocks) {
            _m_ModuleStaticBlock_write(out, _item2637);
        }
        found.append(("static_blocks", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.enums.count);
        for (var _item2638 in value.enums) {
            _m_EnumDef_write(out, _item2638);
        }
        found.append(("enums", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.struct_specs.count);
        for (var _item2639 in value.struct_specs) {
            _m_TypeName_write(out, _item2639);
        }
        found.append(("struct_specs", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.func_specs.count);
        for (var _item2640 in value.func_specs) {
            _m_TypeName_write(out, _item2640);
        }
        found.append(("func_specs", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.type_aliases.count);
        for (var _item2641 in value.type_aliases) {
            _m_TypeAliasDef_write(out, _item2641);
        }
        found.append(("type_aliases", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.withheld.count);
        for (var _item2642 in value.withheld) {
            _m_Withheld_write(out, _item2642);
        }
        found.append(("withheld", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.properties.count);
        for (var _item2643 in value.properties) {
            _m_PropertyDef_write(out, _item2643);
        }
        found.append(("properties", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.type_uses.count);
        for (var _item2644 in value.type_uses) {
            _m_TypeUse_write(out, _item2644);
        }
        found.append(("type_uses", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.use_contexts.count);
        for (var _item2645 in value.use_contexts) {
            _m_UseContext_write(out, _item2645);
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
            for (var _item2646 in value.literal_args) {
                var (_t2647, _t2648, _t2649) = _item2646;
                out.loc(_t2647);
                out.unsigned(_t2648);
                out.loc(_t2649);
            }
        }
        found.append(("literal_args", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.constrained_aliases.count);
        for (var _item2650 in value.constrained_aliases) {
            _m_TypeAliasDef_write(out, _item2650);
        }
        found.append(("constrained_aliases", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.trait_types.count);
        for (var _item2651 in value.trait_types) {
            _m_TraitType_write(out, _item2651);
        }
        found.append(("trait_types", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.conversions.count);
        for (var _item2652 in value.conversions) {
            _m_Conversion_write(out, _item2652);
        }
        found.append(("conversions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2654 = Array<(u8[], u8[], String)>();
        for (var (_key2653, _) in value.overload_sets) {
            var _scratch2655 = out.scratch();
            _scratch2655.text(_key2653);
            var _vscratch2657 = out.scratch();
            _vscratch2657.unsigned(value.overload_sets[_key2653].count);
            for (var _item2658 in value.overload_sets[_key2653]) {
                _vscratch2657.text(_item2658);
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
            out.unsigned(value.overload_sets[_key2653].count);
            for (var _item2659 in value.overload_sets[_key2653]) {
                out.text(_item2659);
            }
        }
        found.append(("overload_sets", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2661 = Array<(u8[], u8[], String)>();
        for (var (_key2660, _) in value.overload_unions) {
            var _scratch2662 = out.scratch();
            _scratch2662.text(_key2660);
            var _vscratch2664 = out.scratch();
            _vscratch2664.unsigned(value.overload_unions[_key2660].count);
            for (var _item2665 in value.overload_unions[_key2660]) {
                _vscratch2664.unsigned(_item2665.count);
                for (var _item2666 in _item2665) {
                    _vscratch2664.text(_item2666);
                }
            }
            _keys2661.append((_scratch2662.finish(), _vscratch2664.finish(), _key2660));
        }
        _keys2661.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2661.count);
        for (var (_bytes2663, _, _key2660) in _keys2661) {
            out.text(_key2660);
            out.unsigned(value.overload_unions[_key2660].count);
            for (var _item2667 in value.overload_unions[_key2660]) {
                out.unsigned(_item2667.count);
                for (var _item2668 in _item2667) {
                    out.text(_item2668);
                }
            }
        }
        found.append(("overload_unions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2670 = Array<(u8[], u8[], String)>();
        for (var (_key2669, _) in value.method_overload_sets) {
            var _scratch2671 = out.scratch();
            _scratch2671.text(_key2669);
            var _vscratch2673 = out.scratch();
            var _keys2675 = Array<(u8[], u8[], String)>();
            for (var (_key2674, _) in value.method_overload_sets[_key2669]) {
                var _scratch2676 = _vscratch2673.scratch();
                _scratch2676.text(_key2674);
                var _vscratch2678 = _vscratch2673.scratch();
                _vscratch2678.unsigned(value.method_overload_sets[_key2669][_key2674].count);
                for (var _item2679 in value.method_overload_sets[_key2669][_key2674]) {
                    _vscratch2678.text(_item2679);
                }
                _keys2675.append((_scratch2676.finish(), _vscratch2678.finish(), _key2674));
            }
            _keys2675.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            _vscratch2673.unsigned(_keys2675.count);
            for (var (_bytes2677, _, _key2674) in _keys2675) {
                _vscratch2673.text(_key2674);
                _vscratch2673.unsigned(value.method_overload_sets[_key2669][_key2674].count);
                for (var _item2680 in value.method_overload_sets[_key2669][_key2674]) {
                    _vscratch2673.text(_item2680);
                }
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
            var _keys2682 = Array<(u8[], u8[], String)>();
            for (var (_key2681, _) in value.method_overload_sets[_key2669]) {
                var _scratch2683 = out.scratch();
                _scratch2683.text(_key2681);
                var _vscratch2685 = out.scratch();
                _vscratch2685.unsigned(value.method_overload_sets[_key2669][_key2681].count);
                for (var _item2686 in value.method_overload_sets[_key2669][_key2681]) {
                    _vscratch2685.text(_item2686);
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
                out.unsigned(value.method_overload_sets[_key2669][_key2681].count);
                for (var _item2687 in value.method_overload_sets[_key2669][_key2681]) {
                    out.text(_item2687);
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
        var _keys2689 = Array<(u8[], u8[], Loc)>();
        for (var _key2688 in value.private_functions) {
            var _scratch2690 = out.scratch();
            _scratch2690.loc(_key2688);
            var _vscratch2692 = out.scratch();
            _keys2689.append((_scratch2690.finish(), _vscratch2692.finish(), _key2688));
        }
        _keys2689.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2689.count);
        for (var (_bytes2691, _, _key2688) in _keys2689) {
            out.loc(_key2688);
        }
        found.append(("private_functions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2694 = Array<(u8[], u8[], Loc)>();
        for (var _key2693 in value.file_private_functions) {
            var _scratch2695 = out.scratch();
            _scratch2695.loc(_key2693);
            var _vscratch2697 = out.scratch();
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
            out.loc(_key2693);
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
            for (var _item2698 in value.call_targets) {
                var (_t2699, _t2700) = _item2698;
                out.loc(_t2699);
                out.text(_t2700);
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
            for (var _item2701 in value.argument_names) {
                var (_t2702, _t2703) = _item2701;
                out.loc(_t2702);
                out.text(_t2703);
            }
        }
        found.append(("argument_names", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.namespaces.count);
        for (var _item2704 in value.namespaces) {
            out.text(_item2704);
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
            for (var _item2705 in value.cached_files) {
                out.flag(_item2705);
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
            var _keys2707 = Array<(u8[], u8[], Loc)>();
            for (var (_key2706, _) in value.recorded_summaries) {
                var _scratch2708 = out.scratch();
                _scratch2708.loc(_key2706);
                var _vscratch2710 = out.scratch();
                _vscratch2710.text(value.recorded_summaries[_key2706]);
                _keys2707.append((_scratch2708.finish(), _vscratch2710.finish(), _key2706));
            }
            _keys2707.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            out.unsigned(_keys2707.count);
            for (var (_bytes2709, _, _key2706) in _keys2707) {
                out.loc(_key2706);
                out.text(value.recorded_summaries[_key2706]);
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
            var _keys2712 = Array<(u8[], u8[], Loc)>();
            for (var _key2711 in value.stripped) {
                var _scratch2713 = out.scratch();
                _scratch2713.loc(_key2711);
                var _vscratch2715 = out.scratch();
                _keys2712.append((_scratch2713.finish(), _vscratch2715.finish(), _key2711));
            }
            _keys2712.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            out.unsigned(_keys2712.count);
            for (var (_bytes2714, _, _key2711) in _keys2712) {
                out.loc(_key2711);
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
        var _keys2717 = Array<(u8[], u8[], String)>();
        for (var (_key2716, _) in value.spec_requests) {
            var _scratch2718 = out.scratch();
            _scratch2718.text(_key2716);
            var _vscratch2720 = out.scratch();
            _m_SpecRequest_write(_vscratch2720, value.spec_requests[_key2716]);
            _keys2717.append((_scratch2718.finish(), _vscratch2720.finish(), _key2716));
        }
        _keys2717.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2717.count);
        for (var (_bytes2719, _, _key2716) in _keys2717) {
            out.text(_key2716);
            _m_SpecRequest_write(out, value.spec_requests[_key2716]);
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
            for (var _item2721 in value.summaries_to_record) {
                var (_t2722, _t2723) = _item2721;
                out.loc(_t2722);
                out.text(_t2723);
            }
        }
        found.append(("summaries_to_record", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2725 = Array<(u8[], u8[], String)>();
        for (var (_key2724, _) in value.caller_copies) {
            var _scratch2726 = out.scratch();
            _scratch2726.text(_key2724);
            var _vscratch2728 = out.scratch();
            _vscratch2728.unsigned(value.caller_copies[_key2724].count);
            for (var _item2729 in value.caller_copies[_key2724]) {
                _vscratch2728.flag(_item2729);
            }
            _keys2725.append((_scratch2726.finish(), _vscratch2728.finish(), _key2724));
        }
        _keys2725.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2725.count);
        for (var (_bytes2727, _, _key2724) in _keys2725) {
            out.text(_key2724);
            out.unsigned(value.caller_copies[_key2724].count);
            for (var _item2730 in value.caller_copies[_key2724]) {
                out.flag(_item2730);
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
    for (var _item2731 in value.structs) {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        _m_StructDef_write(out, _item2731);
        found.append(("structs " + _item2731.name, interface_text(out)));
    }
    for (var _item2732 in value.functions) {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        _m_FunctionDef_write(out, _item2732);
        found.append(("functions " + _item2732.name, interface_text(out)));
    }
    return found;
}
