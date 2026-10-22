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
    if (value.labeled.is_value()) {
        out.unsigned(1);
        _m_TypeName_write(out, value.labeled.value());
    } else {
        out.unsigned(0);
    }
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
    var _o1425 = Optional<TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o1425 = Optional<TypeName>.Value(_m_TypeName_read(input));
    }
    var _f1426 = _o1425;
    return MethodCallExpression(_f1419, _f1420, _f1423, _f1424, _f1426);
}

_m_FunctionRefExpression_write(out: RecordOut, value: FunctionRefExpression) {
    out.text(value.function);
    _m_TypeName_write(out, value.ty);
    out.loc(value.loc);
}

_m_FunctionRefExpression_read(input: RecordIn): FunctionRefExpression {
    var _f1427 = input.text();
    var _f1428 = _m_TypeName_read(input);
    var _f1429 = input.loc();
    return FunctionRefExpression(_f1427, _f1428, _f1429);
}

_m_InvokeExpression_write(out: RecordOut, value: InvokeExpression) {
    _m_Expression_write(out, value.callee);
    out.unsigned(value.args.count);
    for (var _item1430 in value.args) {
        _m_Expression_write(out, _item1430);
    }
}

_m_InvokeExpression_read(input: RecordIn): InvokeExpression {
    var _f1431 = _m_Expression_read(input);
    var _v1432 = Array<Expression>();
    var _n1433 = input.count();
    for (var _ in 0.._n1433) {
        _v1432.append(_m_Expression_read(input));
    }
    var _f1434 = _v1432;
    return InvokeExpression(_f1431, _f1434);
}

_m_MakeClosureExpression_write(out: RecordOut, value: MakeClosureExpression) {
    _m_Expression_write(out, value.value);
    out.text(value.closure);
    _m_TypeName_write(out, value.ty);
    out.loc(value.loc);
}

_m_MakeClosureExpression_read(input: RecordIn): MakeClosureExpression {
    var _f1436 = _m_Expression_read(input);
    var _f1437 = input.text();
    var _f1438 = _m_TypeName_read(input);
    var _f1439 = input.loc();
    return MakeClosureExpression(_f1436, _f1437, _f1438, _f1439);
}

_m_CallPointerExpression_write(out: RecordOut, value: CallPointerExpression) {
    _m_Expression_write(out, value.pointer);
    out.unsigned(value.args.count);
    for (var _item1441 in value.args) {
        _m_Expression_write(out, _item1441);
    }
}

_m_CallPointerExpression_read(input: RecordIn): CallPointerExpression {
    var _f1442 = _m_Expression_read(input);
    var _v1443 = Array<Expression>();
    var _n1444 = input.count();
    for (var _ in 0.._n1444) {
        _v1443.append(_m_Expression_read(input));
    }
    var _f1445 = _v1443;
    return CallPointerExpression(_f1442, _f1445);
}

_m_MoveExpression_write(out: RecordOut, value: MoveExpression) {
    _m_Expression_write(out, value.value);
    out.loc(value.loc);
}

_m_MoveExpression_read(input: RecordIn): MoveExpression {
    var _f1448 = _m_Expression_read(input);
    var _f1449 = input.loc();
    return MoveExpression(_f1448, _f1449);
}

_m_DestructureExpression_write(out: RecordOut, value: DestructureExpression) {
    _m_Expression_write(out, value.value);
    out.unsigned(value.count);
    out.loc(value.loc);
}

_m_DestructureExpression_read(input: RecordIn): DestructureExpression {
    var _f1450 = _m_Expression_read(input);
    var _f1451 = input.unsigned();
    var _f1452 = input.loc();
    return DestructureExpression(_f1450, _f1451, _f1452);
}

_m_StaticCaseExpression_write(out: RecordOut, value: StaticCaseExpression) {
    _m_TypeName_write(out, value.ty);
    out.signed(value.tag as long);
}

_m_StaticCaseExpression_read(input: RecordIn): StaticCaseExpression {
    var _f1455 = _m_TypeName_read(input);
    var _f1456 = input.signed();
    return StaticCaseExpression(_f1455, _f1456);
}

_m_StaticStringExpression_write(out: RecordOut, value: StaticStringExpression) {
    out.text(value.value);
    out.loc(value.loc);
}

_m_StaticStringExpression_read(input: RecordIn): StaticStringExpression {
    var _f1457 = input.text();
    var _f1458 = input.loc();
    return StaticStringExpression(_f1457, _f1458);
}

_m_SubjectExpression_write(out: RecordOut, value: SubjectExpression) {
    out.unsigned(value.id);
    _m_TypeName_write(out, value.ty);
    out.loc(value.loc);
}

_m_SubjectExpression_read(input: RecordIn): SubjectExpression {
    var _f1460 = input.unsigned();
    var _f1461 = _m_TypeName_read(input);
    var _f1462 = input.loc();
    return SubjectExpression(_f1460, _f1461, _f1462);
}

_m_ToTraitExpression_write(out: RecordOut, value: ToTraitExpression) {
    _m_Expression_write(out, value.value);
    _m_TypeName_write(out, value.from);
    _m_TypeName_write(out, value.to);
    out.loc(value.loc);
}

_m_ToTraitExpression_read(input: RecordIn): ToTraitExpression {
    var _f1463 = _m_Expression_read(input);
    var _f1464 = _m_TypeName_read(input);
    var _f1465 = _m_TypeName_read(input);
    var _f1466 = input.loc();
    return ToTraitExpression(_f1463, _f1464, _f1465, _f1466);
}

_m_FromTraitExpression_write(out: RecordOut, value: FromTraitExpression) {
    _m_Expression_write(out, value.value);
    _m_TypeName_write(out, value.from);
    _m_TypeName_write(out, value.to);
    out.unsigned(value.candidates.count);
    for (var _item1467 in value.candidates) {
        _m_TypeName_write(out, _item1467);
    }
    out.flag(value.test);
    out.loc(value.loc);
}

_m_FromTraitExpression_read(input: RecordIn): FromTraitExpression {
    var _f1468 = _m_Expression_read(input);
    var _f1469 = _m_TypeName_read(input);
    var _f1470 = _m_TypeName_read(input);
    var _v1471 = Array<TypeName>();
    var _n1472 = input.count();
    for (var _ in 0.._n1472) {
        _v1471.append(_m_TypeName_read(input));
    }
    var _f1473 = _v1471;
    var _f1474 = input.flag();
    var _f1475 = input.loc();
    return FromTraitExpression(_f1468, _f1469, _f1470, _f1473, _f1474, _f1475);
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
        var _f1435 = _m_ClosureLiteral_read(input);
        return Expression.ClosureLiteral(_f1435);
    }
    if (tag == 36) {
        return Expression.MakeClosure(_m_MakeClosureExpression_read(input));
    }
    if (tag == 37) {
        var _f1440 = input.text();
        return Expression.MethodAddress(_f1440);
    }
    if (tag == 38) {
        return Expression.CallPointer(_m_CallPointerExpression_read(input));
    }
    if (tag == 39) {
        var _f1446 = _m_Expression_read(input);
        return Expression.ForIterator(_f1446);
    }
    if (tag == 40) {
        var _f1447 = _m_Expression_read(input);
        return Expression.WithEntered(_f1447);
    }
    if (tag == 41) {
        return Expression.Move(_m_MoveExpression_read(input));
    }
    if (tag == 42) {
        return Expression.Destructure(_m_DestructureExpression_read(input));
    }
    if (tag == 43) {
        var _f1453 = _m_MatchArmTest_read(input);
        return Expression.MatchArm(_f1453);
    }
    if (tag == 44) {
        var _f1454 = _m_CaseValue_read(input);
        return Expression.CaseValue(_f1454);
    }
    if (tag == 45) {
        return Expression.StaticCase(_m_StaticCaseExpression_read(input));
    }
    if (tag == 46) {
        return Expression.StaticString(_m_StaticStringExpression_read(input));
    }
    if (tag == 47) {
        var _f1459 = _m_WithSubject_read(input);
        return Expression.WithSubject(_f1459);
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
        var _f1476 = _m_StaticValue_read(input);
        return Expression.StaticValue(_f1476);
    }
    if (tag == 53) {
        var _f1477 = _m_StaticMember_read(input);
        return Expression.StaticMember(_f1477);
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
        var _f1478 = _m_VariableDef_read(input);
        return Declaration.Variable(_f1478);
    }
    if (tag == 1) {
        var _f1479 = _m_FunctionDef_read(input);
        return Declaration.Function(_f1479);
    }
    if (tag == 2) {
        var _f1480 = _m_StructDef_read(input);
        return Declaration.Struct(_f1480);
    }
    if (tag == 3) {
        var _f1481 = _m_TraitDef_read(input);
        return Declaration.Trait(_f1481);
    }
    if (tag == 4) {
        var _f1482 = _m_ExtensionDef_read(input);
        return Declaration.Extension(_f1482);
    }
    if (tag == 5) {
        var _f1483 = _m_ExternDef_read(input);
        return Declaration.Extern(_f1483);
    }
    if (tag == 6) {
        var _f1484 = _m_TypeAliasDef_read(input);
        return Declaration.TypeAlias(_f1484);
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
    var _hs1490 = Array<String>();
    for (var _item1485 in value.imports) {
        var scratch = base.scratch();
        _a_Import_write(scratch, _item1485);
        _hs1490.append(base.hash_of(scratch));
    }
    var _seq1491 = base.sequence("imports");
    ulong _bj1492 = 0;
    var _news1493 = Array<ulong>();
    for (var _i1494 in 0.._hs1490.count) {
        if (_bj1492 < _seq1491.count and _hs1490[_i1494] == _seq1491[_bj1492]) {
            _bj1492 += 1;
        } else {
            _news1493.append(_i1494);
        }
    }
    if (_bj1492 == _seq1491.count) {
        out.unsigned(2);
        out.unsigned(_news1493.count);
        for (var _i1494 in _news1493) {
            out.unsigned(_i1494);
            _a_Import_write(out, value.imports[_i1494]);
            {
                var _own1495 = RecordOut();
                _own1495.blank_bodies = true;
                _own1495.blank_locs = true;
                _own1495.pending_as_bytes = true;
                _a_Import_write(_own1495, value.imports[_i1494]);
                base.own("imports", interface_text(_own1495));
            }
        }
        base.count("imports" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("imports" + " whole", 0);
        out.unsigned(value.imports.count);
        for (var _i1494 in 0..value.imports.count) {
            _a_Import_write(out, value.imports[_i1494]);
            {
                var _own1496 = RecordOut();
                _own1496.blank_bodies = true;
                _own1496.blank_locs = true;
                _own1496.pending_as_bytes = true;
                _a_Import_write(_own1496, value.imports[_i1494]);
                base.own("imports", interface_text(_own1496));
            }
        }
    }
    base.stat("imports", out.values.count - _mark);
    _mark = out.values.count;
    var _seq1506 = base.ref_structs;
    ulong _bj1507 = 0;
    var _news1509 = Array<ulong>();
    var _patches1510 = Array<(ulong, ulong)>();
    for (var _i1511 in 0..value.structs.count) {
        if (_bj1507 < _seq1506.count
            and value.structs[_i1511] === _seq1506[_bj1507]
            and !value.extended_checked.contains(value.structs[_i1511].name)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_StructDef_write(scratch, value.structs[_i1511]);
                base.verify_same("s", _bj1507, scratch, value.structs[_i1511].name);
            }
            _bj1507 += 1;
        } else if (_bj1507 < _seq1506.count
            and !(value.structs[_i1511] === _seq1506[_bj1507])
            and _same_m_StructDef(value.structs[_i1511], _seq1506[_bj1507], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_StructDef_write(scratch, value.structs[_i1511]);
                base.verify_same("s", _bj1507, scratch, value.structs[_i1511].name);
            }
            _bj1507 += 1;
        } else if (_bj1507 < _seq1506.count and value.structs[_i1511].name == _seq1506[_bj1507].name) {
            _patches1510.append((_i1511, _bj1507));
            _bj1507 += 1;
        } else {
            _news1509.append(_i1511);
        }
    }
    if (_bj1507 == _seq1506.count) {
        out.unsigned(2);
        out.unsigned(_patches1510.count);
        for (var (_i1511, _b) in _patches1510) {
            ulong _before = out.values.count;
            out.text(value.structs[_i1511].name);
            out.unsigned(_b);
            _patch_s_write(out, value.structs[_i1511], base, _b);
            base.count("s patched", out.values.count - _before);
            {
                var _own1512 = RecordOut();
                _own1512.blank_bodies = true;
                _own1512.blank_locs = true;
                _own1512.pending_as_bytes = true;
                var _s1513 = value.structs[_i1511];
                var _methods1514 = _s1513.method_members;
                _s1513.method_members = Array<FunctionDef>();
                var _fields1515 = _s1513.field_members;
                var split__fields1515 = splits_fields(_s1513);
                if (split__fields1515) {
                    _s1513.field_members = Array<VariableDef>();
                }
                _m_StructDef_write(_own1512, _s1513);
                _s1513.method_members = _methods1514;
                _s1513.field_members = _fields1515;
                base.own_named("structs", _s1513.name, interface_text(_own1512));
                for (var _m1516 in _methods1514) {
                    var _own1517 = RecordOut();
                    _own1517.blank_bodies = true;
                    _own1517.blank_locs = true;
                    _own1517.pending_as_bytes = true;
                    _m_FunctionDef_write(_own1517, _m1516);
                    base.own_method("structs", _s1513.name, _m1516.name, interface_text(_own1517));
                }
                if (split__fields1515) {
                    var _order1519 = StringBuilder();
                    for (var _f1518 in _fields1515) {
                        var _own1520 = RecordOut();
                        _own1520.blank_locs = true;
                        _m_VariableDef_write(_own1520, _f1518);
                        base.own_method("structs", _s1513.name, "." + _f1518.name, interface_text(_own1520));
                        _order1519.append(_f1518.name);
                        _order1519.append(",");
                    }
                    base.own_method("structs", _s1513.name, ".#order", _order1519.to_string());
                }
            }
        }
        out.unsigned(_news1509.count);
        for (var _i1511 in _news1509) {
            ulong _before = out.values.count;
            out.unsigned(_i1511);
            _m_StructDef_write(out, value.structs[_i1511]);
            base.count("s new", out.values.count - _before);
            {
                var _own1521 = RecordOut();
                _own1521.blank_bodies = true;
                _own1521.blank_locs = true;
                _own1521.pending_as_bytes = true;
                var _s1522 = value.structs[_i1511];
                var _methods1523 = _s1522.method_members;
                _s1522.method_members = Array<FunctionDef>();
                var _fields1524 = _s1522.field_members;
                var split__fields1524 = splits_fields(_s1522);
                if (split__fields1524) {
                    _s1522.field_members = Array<VariableDef>();
                }
                _m_StructDef_write(_own1521, _s1522);
                _s1522.method_members = _methods1523;
                _s1522.field_members = _fields1524;
                base.own_named("structs", _s1522.name, interface_text(_own1521));
                for (var _m1525 in _methods1523) {
                    var _own1526 = RecordOut();
                    _own1526.blank_bodies = true;
                    _own1526.blank_locs = true;
                    _own1526.pending_as_bytes = true;
                    _m_FunctionDef_write(_own1526, _m1525);
                    base.own_method("structs", _s1522.name, _m1525.name, interface_text(_own1526));
                }
                if (split__fields1524) {
                    var _order1528 = StringBuilder();
                    for (var _f1527 in _fields1524) {
                        var _own1529 = RecordOut();
                        _own1529.blank_locs = true;
                        _m_VariableDef_write(_own1529, _f1527);
                        base.own_method("structs", _s1522.name, "." + _f1527.name, interface_text(_own1529));
                        _order1528.append(_f1527.name);
                        _order1528.append(",");
                    }
                    base.own_method("structs", _s1522.name, ".#order", _order1528.to_string());
                }
            }
        }
        base.count("s merged", 0);
    } else {
        out.unsigned(1);
        base.count("s by place", 0);
        var _struct_hits1505 = HashSet<long>();
        var _slots1508 = HashMap<String, long>();
        for (var _i1511 in 0.._seq1506.count) {
            if (!_slots1508.contains(_seq1506[_i1511].name)) {
                _slots1508[_seq1506[_i1511].name] = _i1511 as long;
            }
        }
        out.unsigned(value.structs.count);
        for (var _i1511 in 0..value.structs.count) {
            var _item1504 = value.structs[_i1511];
            var _slot = _slots1508.try_get(_item1504.name);
            long named = _slot.is_value() ? _slot.value() : -1;
            long at = -1;
            if (named >= 0
                and _seq1506[named as ulong] === _item1504
                and !value.extended_checked.contains(_item1504.name)) {
                at = named;
            }
            ulong _before = out.values.count;
            if (at >= 0) {
                _struct_hits1505.insert(at);
                out.unsigned((at as ulong) * 2 + 1);
            } else if (named >= 0) {
                _struct_hits1505.insert(named);
                out.unsigned(2);
                out.unsigned(named as ulong);
                _patch_s_write(out, _item1504, base, named as ulong);
                base.count("s patched", out.values.count - _before);
            } else {
                out.unsigned(0);
                _m_StructDef_write(out, _item1504);
                base.count("s new", out.values.count - _before);
            }
        }
        base.missed("s", "s", _struct_hits1505.count);
    }
    base.stat("structs", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1543 = Array<String>();
    for (var _item1538 in value.traits) {
        var scratch = base.scratch();
        _m_TraitDef_write(scratch, _item1538);
        _hs1543.append(base.hash_of(scratch));
    }
    var _seq1544 = base.sequence("traits");
    ulong _bj1545 = 0;
    var _news1546 = Array<ulong>();
    for (var _i1547 in 0.._hs1543.count) {
        if (_bj1545 < _seq1544.count and _hs1543[_i1547] == _seq1544[_bj1545]) {
            _bj1545 += 1;
        } else {
            _news1546.append(_i1547);
        }
    }
    if (_bj1545 == _seq1544.count) {
        out.unsigned(2);
        out.unsigned(_news1546.count);
        for (var _i1547 in _news1546) {
            out.unsigned(_i1547);
            _m_TraitDef_write(out, value.traits[_i1547]);
            {
                var _own1548 = RecordOut();
                _own1548.blank_bodies = false;
                _own1548.blank_locs = true;
                _own1548.pending_as_bytes = true;
                _m_TraitDef_write(_own1548, value.traits[_i1547]);
                base.own("traits", interface_text(_own1548));
            }
        }
        base.count("traits" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("traits" + " whole", 0);
        out.unsigned(value.traits.count);
        for (var _i1547 in 0..value.traits.count) {
            _m_TraitDef_write(out, value.traits[_i1547]);
            {
                var _own1549 = RecordOut();
                _own1549.blank_bodies = false;
                _own1549.blank_locs = true;
                _own1549.pending_as_bytes = true;
                _m_TraitDef_write(_own1549, value.traits[_i1547]);
                base.own("traits", interface_text(_own1549));
            }
        }
    }
    base.stat("traits", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1562 = Array<String>();
    for (var _item1557 in value.extensions) {
        var scratch = base.scratch();
        _m_ExtensionDef_write(scratch, _item1557);
        _hs1562.append(base.hash_of(scratch));
    }
    var _seq1563 = base.sequence("extensions");
    ulong _bj1564 = 0;
    var _news1565 = Array<ulong>();
    for (var _i1566 in 0.._hs1562.count) {
        if (_bj1564 < _seq1563.count and _hs1562[_i1566] == _seq1563[_bj1564]) {
            _bj1564 += 1;
        } else {
            _news1565.append(_i1566);
        }
    }
    if (_bj1564 == _seq1563.count) {
        out.unsigned(2);
        out.unsigned(_news1565.count);
        for (var _i1566 in _news1565) {
            out.unsigned(_i1566);
            _m_ExtensionDef_write(out, value.extensions[_i1566]);
            {
                var _own1567 = RecordOut();
                _own1567.blank_bodies = true;
                _own1567.blank_locs = true;
                _own1567.pending_as_bytes = true;
                _m_ExtensionDef_write(_own1567, value.extensions[_i1566]);
                base.own("extensions", interface_text(_own1567));
            }
        }
        base.count("extensions" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("extensions" + " whole", 0);
        out.unsigned(value.extensions.count);
        for (var _i1566 in 0..value.extensions.count) {
            _m_ExtensionDef_write(out, value.extensions[_i1566]);
            {
                var _own1568 = RecordOut();
                _own1568.blank_bodies = true;
                _own1568.blank_locs = true;
                _own1568.pending_as_bytes = true;
                _m_ExtensionDef_write(_own1568, value.extensions[_i1566]);
                base.own("extensions", interface_text(_own1568));
            }
        }
    }
    base.stat("extensions", out.values.count - _mark);
    _mark = out.values.count;
    var _seq1581 = base.ref_functions;
    ulong _bj1582 = 0;
    var _news1583 = Array<ulong>();
    var _changed1577 = Array<(ulong, ulong)>();
    for (var _i1584 in 0..value.functions.count) {
        if (_bj1582 < _seq1581.count and value.functions[_i1584] === _seq1581[_bj1582]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.functions[_i1584]);
                base.verify_same("functions", _bj1582, scratch);
            }
            _bj1582 += 1;
        } else if (_bj1582 < _seq1581.count and _same_m_FunctionDef(value.functions[_i1584], _seq1581[_bj1582], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.functions[_i1584]);
                base.verify_same("functions", _bj1582, scratch);
            }
            _bj1582 += 1;
        } else if (_bj1582 < _seq1581.count and value.functions[_i1584].name == _seq1581[_bj1582].name) {
            _changed1577.append((_i1584, _bj1582));
            _bj1582 += 1;
        } else {
            _news1583.append(_i1584);
        }
    }
    if (_bj1582 == _seq1581.count) {
        out.unsigned(2);
        out.unsigned(_changed1577.count);
        for (var (_i1584, _b) in _changed1577) {
            out.text(value.functions[_i1584].name);
            out.unsigned(_b);
            _m_FunctionDef_write(out, value.functions[_i1584]);
            {
                var _own1585 = RecordOut();
                _own1585.blank_bodies = true;
                _own1585.blank_locs = true;
                _own1585.pending_as_bytes = true;
                _m_FunctionDef_write(_own1585, value.functions[_i1584]);
                base.own_function("functions", value.functions[_i1584], interface_text(_own1585));
            }
        }
        base.count("functions" + " changed", _changed1577.count);
        out.unsigned(_news1583.count);
        for (var _i1584 in _news1583) {
            out.unsigned(_i1584);
            _m_FunctionDef_write(out, value.functions[_i1584]);
            {
                var _own1586 = RecordOut();
                _own1586.blank_bodies = true;
                _own1586.blank_locs = true;
                _own1586.pending_as_bytes = true;
                _m_FunctionDef_write(_own1586, value.functions[_i1584]);
                base.own_function("functions", value.functions[_i1584], interface_text(_own1586));
            }
        }
        base.count("functions" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("functions" + " whole", 0);
        out.unsigned(value.functions.count);
        for (var _i1584 in 0..value.functions.count) {
            _m_FunctionDef_write(out, value.functions[_i1584]);
            {
                var _own1587 = RecordOut();
                _own1587.blank_bodies = true;
                _own1587.blank_locs = true;
                _own1587.pending_as_bytes = true;
                _m_FunctionDef_write(_own1587, value.functions[_i1584]);
                base.own_function("functions", value.functions[_i1584], interface_text(_own1587));
            }
        }
    }
    base.stat("functions", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1600 = Array<String>();
    for (var _item1595 in value.externs) {
        var scratch = base.scratch();
        _m_ExternDef_write(scratch, _item1595);
        _hs1600.append(base.hash_of(scratch));
    }
    var _seq1601 = base.sequence("externs");
    ulong _bj1602 = 0;
    var _news1603 = Array<ulong>();
    for (var _i1604 in 0.._hs1600.count) {
        if (_bj1602 < _seq1601.count and _hs1600[_i1604] == _seq1601[_bj1602]) {
            _bj1602 += 1;
        } else {
            _news1603.append(_i1604);
        }
    }
    if (_bj1602 == _seq1601.count) {
        out.unsigned(2);
        out.unsigned(_news1603.count);
        for (var _i1604 in _news1603) {
            out.unsigned(_i1604);
            _m_ExternDef_write(out, value.externs[_i1604]);
            {
                var _own1605 = RecordOut();
                _own1605.blank_bodies = true;
                _own1605.blank_locs = true;
                _own1605.pending_as_bytes = true;
                _m_ExternDef_write(_own1605, value.externs[_i1604]);
                base.own("externs", interface_text(_own1605));
            }
        }
        base.count("externs" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("externs" + " whole", 0);
        out.unsigned(value.externs.count);
        for (var _i1604 in 0..value.externs.count) {
            _m_ExternDef_write(out, value.externs[_i1604]);
            {
                var _own1606 = RecordOut();
                _own1606.blank_bodies = true;
                _own1606.blank_locs = true;
                _own1606.pending_as_bytes = true;
                _m_ExternDef_write(_own1606, value.externs[_i1604]);
                base.own("externs", interface_text(_own1606));
            }
        }
    }
    base.stat("externs", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1619 = Array<String>();
    for (var _item1614 in value.globals) {
        var scratch = base.scratch();
        _m_VariableDef_write(scratch, _item1614);
        _hs1619.append(base.hash_of(scratch));
    }
    var _seq1620 = base.sequence("globals");
    ulong _bj1621 = 0;
    var _news1622 = Array<ulong>();
    for (var _i1623 in 0.._hs1619.count) {
        if (_bj1621 < _seq1620.count and _hs1619[_i1623] == _seq1620[_bj1621]) {
            _bj1621 += 1;
        } else {
            _news1622.append(_i1623);
        }
    }
    if (_bj1621 == _seq1620.count) {
        out.unsigned(2);
        out.unsigned(_news1622.count);
        for (var _i1623 in _news1622) {
            out.unsigned(_i1623);
            _m_VariableDef_write(out, value.globals[_i1623]);
            {
                var _own1624 = RecordOut();
                _own1624.blank_bodies = true;
                _own1624.blank_locs = true;
                _own1624.pending_as_bytes = true;
                _m_VariableDef_write(_own1624, value.globals[_i1623]);
                base.own("globals", interface_text(_own1624));
            }
        }
        base.count("globals" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("globals" + " whole", 0);
        out.unsigned(value.globals.count);
        for (var _i1623 in 0..value.globals.count) {
            _m_VariableDef_write(out, value.globals[_i1623]);
            {
                var _own1625 = RecordOut();
                _own1625.blank_bodies = true;
                _own1625.blank_locs = true;
                _own1625.pending_as_bytes = true;
                _m_VariableDef_write(_own1625, value.globals[_i1623]);
                base.own("globals", interface_text(_own1625));
            }
        }
    }
    base.stat("globals", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1638 = Array<String>();
    for (var _item1633 in value.static_blocks) {
        var scratch = base.scratch();
        _m_ModuleStaticBlock_write(scratch, _item1633);
        _hs1638.append(base.hash_of(scratch));
    }
    var _seq1639 = base.sequence("static_blocks");
    ulong _bj1640 = 0;
    var _news1641 = Array<ulong>();
    for (var _i1642 in 0.._hs1638.count) {
        if (_bj1640 < _seq1639.count and _hs1638[_i1642] == _seq1639[_bj1640]) {
            _bj1640 += 1;
        } else {
            _news1641.append(_i1642);
        }
    }
    if (_bj1640 == _seq1639.count) {
        out.unsigned(2);
        out.unsigned(_news1641.count);
        for (var _i1642 in _news1641) {
            out.unsigned(_i1642);
            _m_ModuleStaticBlock_write(out, value.static_blocks[_i1642]);
            {
                var _own1643 = RecordOut();
                _own1643.blank_bodies = true;
                _own1643.blank_locs = true;
                _own1643.pending_as_bytes = true;
                _m_ModuleStaticBlock_write(_own1643, value.static_blocks[_i1642]);
                base.own("static_blocks", interface_text(_own1643));
            }
        }
        base.count("static_blocks" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("static_blocks" + " whole", 0);
        out.unsigned(value.static_blocks.count);
        for (var _i1642 in 0..value.static_blocks.count) {
            _m_ModuleStaticBlock_write(out, value.static_blocks[_i1642]);
            {
                var _own1644 = RecordOut();
                _own1644.blank_bodies = true;
                _own1644.blank_locs = true;
                _own1644.pending_as_bytes = true;
                _m_ModuleStaticBlock_write(_own1644, value.static_blocks[_i1642]);
                base.own("static_blocks", interface_text(_own1644));
            }
        }
    }
    base.stat("static_blocks", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1657 = Array<String>();
    for (var _item1652 in value.enums) {
        var scratch = base.scratch();
        _m_EnumDef_write(scratch, _item1652);
        _hs1657.append(base.hash_of(scratch));
    }
    var _seq1658 = base.sequence("enums");
    ulong _bj1659 = 0;
    var _news1660 = Array<ulong>();
    for (var _i1661 in 0.._hs1657.count) {
        if (_bj1659 < _seq1658.count and _hs1657[_i1661] == _seq1658[_bj1659]) {
            _bj1659 += 1;
        } else {
            _news1660.append(_i1661);
        }
    }
    if (_bj1659 == _seq1658.count) {
        out.unsigned(2);
        out.unsigned(_news1660.count);
        for (var _i1661 in _news1660) {
            out.unsigned(_i1661);
            _m_EnumDef_write(out, value.enums[_i1661]);
            {
                var _own1662 = RecordOut();
                _own1662.blank_bodies = true;
                _own1662.blank_locs = true;
                _own1662.pending_as_bytes = true;
                _m_EnumDef_write(_own1662, value.enums[_i1661]);
                base.own_named("enums", value.enums[_i1661].name, interface_text(_own1662));
            }
        }
        base.count("enums" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("enums" + " whole", 0);
        out.unsigned(value.enums.count);
        for (var _i1661 in 0..value.enums.count) {
            _m_EnumDef_write(out, value.enums[_i1661]);
            {
                var _own1663 = RecordOut();
                _own1663.blank_bodies = true;
                _own1663.blank_locs = true;
                _own1663.pending_as_bytes = true;
                _m_EnumDef_write(_own1663, value.enums[_i1661]);
                base.own_named("enums", value.enums[_i1661].name, interface_text(_own1663));
            }
        }
    }
    base.stat("enums", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1676 = Array<String>();
    for (var _item1671 in value.struct_specs) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item1671);
        _hs1676.append(base.hash_of(scratch));
    }
    var _seq1677 = base.sequence("struct_specs");
    ulong _bj1678 = 0;
    var _news1679 = Array<ulong>();
    for (var _i1680 in 0.._hs1676.count) {
        if (_bj1678 < _seq1677.count and _hs1676[_i1680] == _seq1677[_bj1678]) {
            _bj1678 += 1;
        } else {
            _news1679.append(_i1680);
        }
    }
    if (_bj1678 == _seq1677.count) {
        out.unsigned(2);
        out.unsigned(_news1679.count);
        for (var _i1680 in _news1679) {
            out.unsigned(_i1680);
            _m_TypeName_write(out, value.struct_specs[_i1680]);
            {
                var _own1681 = RecordOut();
                _own1681.blank_bodies = true;
                _own1681.blank_locs = true;
                _own1681.pending_as_bytes = true;
                _m_TypeName_write(_own1681, value.struct_specs[_i1680]);
                base.own("struct_specs", interface_text(_own1681));
            }
        }
        base.count("struct_specs" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("struct_specs" + " whole", 0);
        out.unsigned(value.struct_specs.count);
        for (var _i1680 in 0..value.struct_specs.count) {
            _m_TypeName_write(out, value.struct_specs[_i1680]);
            {
                var _own1682 = RecordOut();
                _own1682.blank_bodies = true;
                _own1682.blank_locs = true;
                _own1682.pending_as_bytes = true;
                _m_TypeName_write(_own1682, value.struct_specs[_i1680]);
                base.own("struct_specs", interface_text(_own1682));
            }
        }
    }
    base.stat("struct_specs", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1695 = Array<String>();
    for (var _item1690 in value.func_specs) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item1690);
        _hs1695.append(base.hash_of(scratch));
    }
    var _seq1696 = base.sequence("func_specs");
    ulong _bj1697 = 0;
    var _news1698 = Array<ulong>();
    for (var _i1699 in 0.._hs1695.count) {
        if (_bj1697 < _seq1696.count and _hs1695[_i1699] == _seq1696[_bj1697]) {
            _bj1697 += 1;
        } else {
            _news1698.append(_i1699);
        }
    }
    if (_bj1697 == _seq1696.count) {
        out.unsigned(2);
        out.unsigned(_news1698.count);
        for (var _i1699 in _news1698) {
            out.unsigned(_i1699);
            _m_TypeName_write(out, value.func_specs[_i1699]);
            {
                var _own1700 = RecordOut();
                _own1700.blank_bodies = true;
                _own1700.blank_locs = true;
                _own1700.pending_as_bytes = true;
                _m_TypeName_write(_own1700, value.func_specs[_i1699]);
                base.own("func_specs", interface_text(_own1700));
            }
        }
        base.count("func_specs" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("func_specs" + " whole", 0);
        out.unsigned(value.func_specs.count);
        for (var _i1699 in 0..value.func_specs.count) {
            _m_TypeName_write(out, value.func_specs[_i1699]);
            {
                var _own1701 = RecordOut();
                _own1701.blank_bodies = true;
                _own1701.blank_locs = true;
                _own1701.pending_as_bytes = true;
                _m_TypeName_write(_own1701, value.func_specs[_i1699]);
                base.own("func_specs", interface_text(_own1701));
            }
        }
    }
    base.stat("func_specs", out.values.count - _mark);
    _mark = out.values.count;
    var _hits1713 = HashSet<long>();
    out.unsigned(value.type_aliases.count);
    for (var _item1709 in value.type_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1709);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed("type_aliases", hash);
        if (at >= 0) {
            _hits1713.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_TypeAliasDef_write(out, _item1709);
        }
    }
    base.missed("type_aliases", "type_aliases", _hits1713.count);
    base.stat("type_aliases", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1723 = Array<String>();
    for (var _item1718 in value.withheld) {
        var scratch = base.scratch();
        _m_Withheld_write(scratch, _item1718);
        _hs1723.append(base.hash_of(scratch));
    }
    var _seq1724 = base.sequence("withheld");
    ulong _bj1725 = 0;
    var _news1726 = Array<ulong>();
    for (var _i1727 in 0.._hs1723.count) {
        if (_bj1725 < _seq1724.count and _hs1723[_i1727] == _seq1724[_bj1725]) {
            _bj1725 += 1;
        } else {
            _news1726.append(_i1727);
        }
    }
    if (_bj1725 == _seq1724.count) {
        out.unsigned(2);
        out.unsigned(_news1726.count);
        for (var _i1727 in _news1726) {
            out.unsigned(_i1727);
            _m_Withheld_write(out, value.withheld[_i1727]);
            {
                var _own1728 = RecordOut();
                _own1728.blank_bodies = true;
                _own1728.blank_locs = true;
                _own1728.pending_as_bytes = true;
                _m_Withheld_write(_own1728, value.withheld[_i1727]);
                base.own("withheld", interface_text(_own1728));
            }
        }
        base.count("withheld" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("withheld" + " whole", 0);
        out.unsigned(value.withheld.count);
        for (var _i1727 in 0..value.withheld.count) {
            _m_Withheld_write(out, value.withheld[_i1727]);
            {
                var _own1729 = RecordOut();
                _own1729.blank_bodies = true;
                _own1729.blank_locs = true;
                _own1729.pending_as_bytes = true;
                _m_Withheld_write(_own1729, value.withheld[_i1727]);
                base.own("withheld", interface_text(_own1729));
            }
        }
    }
    base.stat("withheld", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1742 = Array<String>();
    for (var _item1737 in value.properties) {
        var scratch = base.scratch();
        _m_PropertyDef_write(scratch, _item1737);
        _hs1742.append(base.hash_of(scratch));
    }
    var _seq1743 = base.sequence("properties");
    ulong _bj1744 = 0;
    var _news1745 = Array<ulong>();
    for (var _i1746 in 0.._hs1742.count) {
        if (_bj1744 < _seq1743.count and _hs1742[_i1746] == _seq1743[_bj1744]) {
            _bj1744 += 1;
        } else {
            _news1745.append(_i1746);
        }
    }
    if (_bj1744 == _seq1743.count) {
        out.unsigned(2);
        out.unsigned(_news1745.count);
        for (var _i1746 in _news1745) {
            out.unsigned(_i1746);
            _m_PropertyDef_write(out, value.properties[_i1746]);
            {
                var _own1747 = RecordOut();
                _own1747.blank_bodies = true;
                _own1747.blank_locs = true;
                _own1747.pending_as_bytes = true;
                _m_PropertyDef_write(_own1747, value.properties[_i1746]);
                base.own("properties", interface_text(_own1747));
            }
        }
        base.count("properties" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("properties" + " whole", 0);
        out.unsigned(value.properties.count);
        for (var _i1746 in 0..value.properties.count) {
            _m_PropertyDef_write(out, value.properties[_i1746]);
            {
                var _own1748 = RecordOut();
                _own1748.blank_bodies = true;
                _own1748.blank_locs = true;
                _own1748.pending_as_bytes = true;
                _m_PropertyDef_write(_own1748, value.properties[_i1746]);
                base.own("properties", interface_text(_own1748));
            }
        }
    }
    base.stat("properties", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1761 = Array<String>();
    for (var _item1756 in value.type_uses) {
        var scratch = base.scratch();
        _m_TypeUse_write(scratch, _item1756);
        _hs1761.append(base.hash_of(scratch));
    }
    var _seq1762 = base.sequence("type_uses");
    ulong _bj1763 = 0;
    var _news1764 = Array<ulong>();
    for (var _i1765 in 0.._hs1761.count) {
        if (_bj1763 < _seq1762.count and _hs1761[_i1765] == _seq1762[_bj1763]) {
            _bj1763 += 1;
        } else {
            _news1764.append(_i1765);
        }
    }
    if (_bj1763 == _seq1762.count) {
        out.unsigned(2);
        out.unsigned(_news1764.count);
        for (var _i1765 in _news1764) {
            out.unsigned(_i1765);
            _m_TypeUse_write(out, value.type_uses[_i1765]);
            {
                var _own1766 = RecordOut();
                _own1766.blank_bodies = true;
                _own1766.blank_locs = true;
                _own1766.pending_as_bytes = true;
                _m_TypeUse_write(_own1766, value.type_uses[_i1765]);
                base.own("type_uses", interface_text(_own1766));
            }
        }
        base.count("type_uses" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("type_uses" + " whole", 0);
        out.unsigned(value.type_uses.count);
        for (var _i1765 in 0..value.type_uses.count) {
            _m_TypeUse_write(out, value.type_uses[_i1765]);
            {
                var _own1767 = RecordOut();
                _own1767.blank_bodies = true;
                _own1767.blank_locs = true;
                _own1767.pending_as_bytes = true;
                _m_TypeUse_write(_own1767, value.type_uses[_i1765]);
                base.own("type_uses", interface_text(_own1767));
            }
        }
    }
    base.stat("type_uses", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1780 = Array<String>();
    for (var _item1775 in value.use_contexts) {
        var scratch = base.scratch();
        _m_UseContext_write(scratch, _item1775);
        _hs1780.append(base.hash_of(scratch));
    }
    var _seq1781 = base.sequence("use_contexts");
    ulong _bj1782 = 0;
    var _news1783 = Array<ulong>();
    for (var _i1784 in 0.._hs1780.count) {
        if (_bj1782 < _seq1781.count and _hs1780[_i1784] == _seq1781[_bj1782]) {
            _bj1782 += 1;
        } else {
            _news1783.append(_i1784);
        }
    }
    if (_bj1782 == _seq1781.count) {
        out.unsigned(2);
        out.unsigned(_news1783.count);
        for (var _i1784 in _news1783) {
            out.unsigned(_i1784);
            _m_UseContext_write(out, value.use_contexts[_i1784]);
            {
                var _own1785 = RecordOut();
                _own1785.blank_bodies = true;
                _own1785.blank_locs = true;
                _own1785.pending_as_bytes = true;
                _m_UseContext_write(_own1785, value.use_contexts[_i1784]);
                base.own("use_contexts", interface_text(_own1785));
            }
        }
        base.count("use_contexts" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("use_contexts" + " whole", 0);
        out.unsigned(value.use_contexts.count);
        for (var _i1784 in 0..value.use_contexts.count) {
            _m_UseContext_write(out, value.use_contexts[_i1784]);
            {
                var _own1786 = RecordOut();
                _own1786.blank_bodies = true;
                _own1786.blank_locs = true;
                _own1786.pending_as_bytes = true;
                _m_UseContext_write(_own1786, value.use_contexts[_i1784]);
                base.own("use_contexts", interface_text(_own1786));
            }
        }
    }
    base.stat("use_contexts", out.values.count - _mark);
    _mark = out.values.count;
    var _n1796 = base.size("literal_args");
    var _scratch1795 = base.scratch();
    if (value.literal_args.count >= _n1796) {
        for (var _i1797 in 0.._n1796) {
            var (_t1798, _t1799, _t1800) = value.literal_args[_i1797];
            _scratch1795.loc(_t1798);
            _scratch1795.unsigned(_t1799);
            _scratch1795.loc(_t1800);
        }
    }
    if (value.literal_args.count >= _n1796 and base.same_list("literal_args", _scratch1795)) {
        out.unsigned(1);
        out.unsigned(_n1796);
        out.unsigned(value.literal_args.count - _n1796);
        for (var _i1797 in _n1796..value.literal_args.count) {
            var (_t1801, _t1802, _t1803) = value.literal_args[_i1797];
            out.loc(_t1801);
            out.unsigned(_t1802);
            out.loc(_t1803);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.literal_args.count);
        for (var _item1804 in value.literal_args) {
            var (_t1805, _t1806, _t1807) = _item1804;
            out.loc(_t1805);
            out.unsigned(_t1806);
            out.loc(_t1807);
        }
        base.count("literal_args whole", 0);
    }
    base.stat("literal_args", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1830 = Array<String>();
    for (var _item1825 in value.constrained_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1825);
        _hs1830.append(base.hash_of(scratch));
    }
    var _seq1831 = base.sequence("constrained_aliases");
    ulong _bj1832 = 0;
    var _news1833 = Array<ulong>();
    for (var _i1834 in 0.._hs1830.count) {
        if (_bj1832 < _seq1831.count and _hs1830[_i1834] == _seq1831[_bj1832]) {
            _bj1832 += 1;
        } else {
            _news1833.append(_i1834);
        }
    }
    if (_bj1832 == _seq1831.count) {
        out.unsigned(2);
        out.unsigned(_news1833.count);
        for (var _i1834 in _news1833) {
            out.unsigned(_i1834);
            _m_TypeAliasDef_write(out, value.constrained_aliases[_i1834]);
            {
                var _own1835 = RecordOut();
                _own1835.blank_bodies = true;
                _own1835.blank_locs = true;
                _own1835.pending_as_bytes = true;
                _m_TypeAliasDef_write(_own1835, value.constrained_aliases[_i1834]);
                base.own("constrained_aliases", interface_text(_own1835));
            }
        }
        base.count("constrained_aliases" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("constrained_aliases" + " whole", 0);
        out.unsigned(value.constrained_aliases.count);
        for (var _i1834 in 0..value.constrained_aliases.count) {
            _m_TypeAliasDef_write(out, value.constrained_aliases[_i1834]);
            {
                var _own1836 = RecordOut();
                _own1836.blank_bodies = true;
                _own1836.blank_locs = true;
                _own1836.pending_as_bytes = true;
                _m_TypeAliasDef_write(_own1836, value.constrained_aliases[_i1834]);
                base.own("constrained_aliases", interface_text(_own1836));
            }
        }
    }
    base.stat("constrained_aliases", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1849 = Array<String>();
    for (var _item1844 in value.trait_types) {
        var scratch = base.scratch();
        _m_TraitType_write(scratch, _item1844);
        _hs1849.append(base.hash_of(scratch));
    }
    var _seq1850 = base.sequence("trait_types");
    ulong _bj1851 = 0;
    var _news1852 = Array<ulong>();
    for (var _i1853 in 0.._hs1849.count) {
        if (_bj1851 < _seq1850.count and _hs1849[_i1853] == _seq1850[_bj1851]) {
            _bj1851 += 1;
        } else {
            _news1852.append(_i1853);
        }
    }
    if (_bj1851 == _seq1850.count) {
        out.unsigned(2);
        out.unsigned(_news1852.count);
        for (var _i1853 in _news1852) {
            out.unsigned(_i1853);
            _m_TraitType_write(out, value.trait_types[_i1853]);
            {
                var _own1854 = RecordOut();
                _own1854.blank_bodies = true;
                _own1854.blank_locs = true;
                _own1854.pending_as_bytes = true;
                _m_TraitType_write(_own1854, value.trait_types[_i1853]);
                base.own("trait_types", interface_text(_own1854));
            }
        }
        base.count("trait_types" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("trait_types" + " whole", 0);
        out.unsigned(value.trait_types.count);
        for (var _i1853 in 0..value.trait_types.count) {
            _m_TraitType_write(out, value.trait_types[_i1853]);
            {
                var _own1855 = RecordOut();
                _own1855.blank_bodies = true;
                _own1855.blank_locs = true;
                _own1855.pending_as_bytes = true;
                _m_TraitType_write(_own1855, value.trait_types[_i1853]);
                base.own("trait_types", interface_text(_own1855));
            }
        }
    }
    base.stat("trait_types", out.values.count - _mark);
    _mark = out.values.count;
    out.unsigned(value.conversions.count);
    for (var _item1863 in value.conversions) {
        _m_Conversion_write(out, _item1863);
    }
    for (var _conv1864 in value.conversions) {
        var _own1865 = RecordOut();
        _own1865.blank_locs = true;
        _m_Conversion_write(_own1865, _conv1864);
        var _h = interface_text(_own1865);
        if (base.find_hashed("conversions", _h) < 0) {
            base.own("conversions", _h);
        }
    }
    base.stat("conversions", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept1873 = 0;
    var _news1874 = Map<String, Array<String>>();
    for (var (_key1870, _) in value.overload_sets) {
        var _kscratch1871 = base.scratch();
        _kscratch1871.text(_key1870);
        var _vscratch1872 = base.scratch();
        _vscratch1872.unsigned(value.overload_sets[_key1870].count);
        for (var _item1875 in value.overload_sets[_key1870]) {
            _vscratch1872.text(_item1875);
        }
        var _had = base.entry("overload_sets", _kscratch1871, _vscratch1872);
        if (_had >= 0) {
            _kept1873 += 1;
        }
        if (_had != 1) {
            _news1874[_key1870] = value.overload_sets[_key1870];
        }
    }
    if (_kept1873 == base.size("overload_sets")) {
        out.unsigned(1);
        var _keys1877 = Array<(u8[], u8[], String)>();
        for (var (_key1876, _) in _news1874) {
            var _scratch1878 = out.scratch();
            _scratch1878.text(_key1876);
            var _vscratch1880 = out.scratch();
            _vscratch1880.unsigned(_news1874[_key1876].count);
            for (var _item1881 in _news1874[_key1876]) {
                _vscratch1880.text(_item1881);
            }
            _keys1877.append((_scratch1878.finish(), _vscratch1880.finish(), _key1876));
        }
        _keys1877.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1877.count);
        for (var (_bytes1879, _, _key1876) in _keys1877) {
            out.text(_key1876);
            out.unsigned(_news1874[_key1876].count);
            for (var _item1882 in _news1874[_key1876]) {
                out.text(_item1882);
            }
        }
        for (var (_okey1883, _) in _news1874) {
            var _own1884 = RecordOut();
            _own1884.blank_bodies = true;
            _own1884.blank_locs = true;
            _own1884.pending_as_bytes = true;
            _own1884.text(_okey1883);
            _own1884.unsigned(_news1874[_okey1883].count);
            for (var _item1885 in _news1874[_okey1883]) {
                _own1884.text(_item1885);
            }
            base.own("overload_sets", interface_text(_own1884));
        }
    } else {
        out.unsigned(0);
        var _keys1887 = Array<(u8[], u8[], String)>();
        for (var (_key1886, _) in value.overload_sets) {
            var _scratch1888 = out.scratch();
            _scratch1888.text(_key1886);
            var _vscratch1890 = out.scratch();
            _vscratch1890.unsigned(value.overload_sets[_key1886].count);
            for (var _item1891 in value.overload_sets[_key1886]) {
                _vscratch1890.text(_item1891);
            }
            _keys1887.append((_scratch1888.finish(), _vscratch1890.finish(), _key1886));
        }
        _keys1887.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1887.count);
        for (var (_bytes1889, _, _key1886) in _keys1887) {
            out.text(_key1886);
            out.unsigned(value.overload_sets[_key1886].count);
            for (var _item1892 in value.overload_sets[_key1886]) {
                out.text(_item1892);
            }
        }
        for (var (_okey1893, _) in value.overload_sets) {
            var _own1894 = RecordOut();
            _own1894.blank_bodies = true;
            _own1894.blank_locs = true;
            _own1894.pending_as_bytes = true;
            _own1894.text(_okey1893);
            _own1894.unsigned(value.overload_sets[_okey1893].count);
            for (var _item1895 in value.overload_sets[_okey1893]) {
                _own1894.text(_item1895);
            }
            base.own("overload_sets", interface_text(_own1894));
        }
        base.count("overload_sets whole", 0);
    }
    base.stat("overload_sets", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept1913 = 0;
    var _news1914 = Map<String, Array<Array<String>>>();
    for (var (_key1910, _) in value.overload_unions) {
        var _kscratch1911 = base.scratch();
        _kscratch1911.text(_key1910);
        var _vscratch1912 = base.scratch();
        _vscratch1912.unsigned(value.overload_unions[_key1910].count);
        for (var _item1915 in value.overload_unions[_key1910]) {
            _vscratch1912.unsigned(_item1915.count);
            for (var _item1916 in _item1915) {
                _vscratch1912.text(_item1916);
            }
        }
        var _had = base.entry("overload_unions", _kscratch1911, _vscratch1912);
        if (_had >= 0) {
            _kept1913 += 1;
        }
        if (_had != 1) {
            _news1914[_key1910] = value.overload_unions[_key1910];
        }
    }
    if (_kept1913 == base.size("overload_unions")) {
        out.unsigned(1);
        var _keys1918 = Array<(u8[], u8[], String)>();
        for (var (_key1917, _) in _news1914) {
            var _scratch1919 = out.scratch();
            _scratch1919.text(_key1917);
            var _vscratch1921 = out.scratch();
            _vscratch1921.unsigned(_news1914[_key1917].count);
            for (var _item1922 in _news1914[_key1917]) {
                _vscratch1921.unsigned(_item1922.count);
                for (var _item1923 in _item1922) {
                    _vscratch1921.text(_item1923);
                }
            }
            _keys1918.append((_scratch1919.finish(), _vscratch1921.finish(), _key1917));
        }
        _keys1918.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1918.count);
        for (var (_bytes1920, _, _key1917) in _keys1918) {
            out.text(_key1917);
            out.unsigned(_news1914[_key1917].count);
            for (var _item1924 in _news1914[_key1917]) {
                out.unsigned(_item1924.count);
                for (var _item1925 in _item1924) {
                    out.text(_item1925);
                }
            }
        }
        for (var (_okey1926, _) in _news1914) {
            var _own1927 = RecordOut();
            _own1927.blank_bodies = true;
            _own1927.blank_locs = true;
            _own1927.pending_as_bytes = true;
            _own1927.text(_okey1926);
            _own1927.unsigned(_news1914[_okey1926].count);
            for (var _item1928 in _news1914[_okey1926]) {
                _own1927.unsigned(_item1928.count);
                for (var _item1929 in _item1928) {
                    _own1927.text(_item1929);
                }
            }
            base.own("overload_unions", interface_text(_own1927));
        }
    } else {
        out.unsigned(0);
        var _keys1931 = Array<(u8[], u8[], String)>();
        for (var (_key1930, _) in value.overload_unions) {
            var _scratch1932 = out.scratch();
            _scratch1932.text(_key1930);
            var _vscratch1934 = out.scratch();
            _vscratch1934.unsigned(value.overload_unions[_key1930].count);
            for (var _item1935 in value.overload_unions[_key1930]) {
                _vscratch1934.unsigned(_item1935.count);
                for (var _item1936 in _item1935) {
                    _vscratch1934.text(_item1936);
                }
            }
            _keys1931.append((_scratch1932.finish(), _vscratch1934.finish(), _key1930));
        }
        _keys1931.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1931.count);
        for (var (_bytes1933, _, _key1930) in _keys1931) {
            out.text(_key1930);
            out.unsigned(value.overload_unions[_key1930].count);
            for (var _item1937 in value.overload_unions[_key1930]) {
                out.unsigned(_item1937.count);
                for (var _item1938 in _item1937) {
                    out.text(_item1938);
                }
            }
        }
        for (var (_okey1939, _) in value.overload_unions) {
            var _own1940 = RecordOut();
            _own1940.blank_bodies = true;
            _own1940.blank_locs = true;
            _own1940.pending_as_bytes = true;
            _own1940.text(_okey1939);
            _own1940.unsigned(value.overload_unions[_okey1939].count);
            for (var _item1941 in value.overload_unions[_okey1939]) {
                _own1940.unsigned(_item1941.count);
                for (var _item1942 in _item1941) {
                    _own1940.text(_item1942);
                }
            }
            base.own("overload_unions", interface_text(_own1940));
        }
        base.count("overload_unions whole", 0);
    }
    base.stat("overload_unions", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept1965 = 0;
    var _news1966 = Map<String, Map<String, Array<String>>>();
    for (var (_key1962, _) in value.method_overload_sets) {
        var _kscratch1963 = base.scratch();
        _kscratch1963.text(_key1962);
        var _vscratch1964 = base.scratch();
        var _keys1968 = Array<(u8[], u8[], String)>();
        for (var (_key1967, _) in value.method_overload_sets[_key1962]) {
            var _scratch1969 = _vscratch1964.scratch();
            _scratch1969.text(_key1967);
            var _vscratch1971 = _vscratch1964.scratch();
            _vscratch1971.unsigned(value.method_overload_sets[_key1962][_key1967].count);
            for (var _item1972 in value.method_overload_sets[_key1962][_key1967]) {
                _vscratch1971.text(_item1972);
            }
            _keys1968.append((_scratch1969.finish(), _vscratch1971.finish(), _key1967));
        }
        _keys1968.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        _vscratch1964.unsigned(_keys1968.count);
        for (var (_bytes1970, _, _key1967) in _keys1968) {
            _vscratch1964.text(_key1967);
            _vscratch1964.unsigned(value.method_overload_sets[_key1962][_key1967].count);
            for (var _item1973 in value.method_overload_sets[_key1962][_key1967]) {
                _vscratch1964.text(_item1973);
            }
        }
        var _had = base.entry("method_overload_sets", _kscratch1963, _vscratch1964);
        if (_had >= 0) {
            _kept1965 += 1;
        }
        if (_had != 1) {
            _news1966[_key1962] = value.method_overload_sets[_key1962];
        }
    }
    if (_kept1965 == base.size("method_overload_sets")) {
        out.unsigned(1);
        var _keys1975 = Array<(u8[], u8[], String)>();
        for (var (_key1974, _) in _news1966) {
            var _scratch1976 = out.scratch();
            _scratch1976.text(_key1974);
            var _vscratch1978 = out.scratch();
            var _keys1980 = Array<(u8[], u8[], String)>();
            for (var (_key1979, _) in _news1966[_key1974]) {
                var _scratch1981 = _vscratch1978.scratch();
                _scratch1981.text(_key1979);
                var _vscratch1983 = _vscratch1978.scratch();
                _vscratch1983.unsigned(_news1966[_key1974][_key1979].count);
                for (var _item1984 in _news1966[_key1974][_key1979]) {
                    _vscratch1983.text(_item1984);
                }
                _keys1980.append((_scratch1981.finish(), _vscratch1983.finish(), _key1979));
            }
            _keys1980.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            _vscratch1978.unsigned(_keys1980.count);
            for (var (_bytes1982, _, _key1979) in _keys1980) {
                _vscratch1978.text(_key1979);
                _vscratch1978.unsigned(_news1966[_key1974][_key1979].count);
                for (var _item1985 in _news1966[_key1974][_key1979]) {
                    _vscratch1978.text(_item1985);
                }
            }
            _keys1975.append((_scratch1976.finish(), _vscratch1978.finish(), _key1974));
        }
        _keys1975.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1975.count);
        for (var (_bytes1977, _, _key1974) in _keys1975) {
            out.text(_key1974);
            var _keys1987 = Array<(u8[], u8[], String)>();
            for (var (_key1986, _) in _news1966[_key1974]) {
                var _scratch1988 = out.scratch();
                _scratch1988.text(_key1986);
                var _vscratch1990 = out.scratch();
                _vscratch1990.unsigned(_news1966[_key1974][_key1986].count);
                for (var _item1991 in _news1966[_key1974][_key1986]) {
                    _vscratch1990.text(_item1991);
                }
                _keys1987.append((_scratch1988.finish(), _vscratch1990.finish(), _key1986));
            }
            _keys1987.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            out.unsigned(_keys1987.count);
            for (var (_bytes1989, _, _key1986) in _keys1987) {
                out.text(_key1986);
                out.unsigned(_news1966[_key1974][_key1986].count);
                for (var _item1992 in _news1966[_key1974][_key1986]) {
                    out.text(_item1992);
                }
            }
        }
        for (var (_okey1993, _) in _news1966) {
            var _own1994 = RecordOut();
            _own1994.blank_bodies = true;
            _own1994.blank_locs = true;
            _own1994.pending_as_bytes = true;
            _own1994.text(_okey1993);
            var _keys1996 = Array<(u8[], u8[], String)>();
            for (var (_key1995, _) in _news1966[_okey1993]) {
                var _scratch1997 = _own1994.scratch();
                _scratch1997.text(_key1995);
                var _vscratch1999 = _own1994.scratch();
                _vscratch1999.unsigned(_news1966[_okey1993][_key1995].count);
                for (var _item2000 in _news1966[_okey1993][_key1995]) {
                    _vscratch1999.text(_item2000);
                }
                _keys1996.append((_scratch1997.finish(), _vscratch1999.finish(), _key1995));
            }
            _keys1996.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            _own1994.unsigned(_keys1996.count);
            for (var (_bytes1998, _, _key1995) in _keys1996) {
                _own1994.text(_key1995);
                _own1994.unsigned(_news1966[_okey1993][_key1995].count);
                for (var _item2001 in _news1966[_okey1993][_key1995]) {
                    _own1994.text(_item2001);
                }
            }
            base.own("method_overload_sets", interface_text(_own1994));
        }
    } else {
        out.unsigned(0);
        var _keys2003 = Array<(u8[], u8[], String)>();
        for (var (_key2002, _) in value.method_overload_sets) {
            var _scratch2004 = out.scratch();
            _scratch2004.text(_key2002);
            var _vscratch2006 = out.scratch();
            var _keys2008 = Array<(u8[], u8[], String)>();
            for (var (_key2007, _) in value.method_overload_sets[_key2002]) {
                var _scratch2009 = _vscratch2006.scratch();
                _scratch2009.text(_key2007);
                var _vscratch2011 = _vscratch2006.scratch();
                _vscratch2011.unsigned(value.method_overload_sets[_key2002][_key2007].count);
                for (var _item2012 in value.method_overload_sets[_key2002][_key2007]) {
                    _vscratch2011.text(_item2012);
                }
                _keys2008.append((_scratch2009.finish(), _vscratch2011.finish(), _key2007));
            }
            _keys2008.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            _vscratch2006.unsigned(_keys2008.count);
            for (var (_bytes2010, _, _key2007) in _keys2008) {
                _vscratch2006.text(_key2007);
                _vscratch2006.unsigned(value.method_overload_sets[_key2002][_key2007].count);
                for (var _item2013 in value.method_overload_sets[_key2002][_key2007]) {
                    _vscratch2006.text(_item2013);
                }
            }
            _keys2003.append((_scratch2004.finish(), _vscratch2006.finish(), _key2002));
        }
        _keys2003.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2003.count);
        for (var (_bytes2005, _, _key2002) in _keys2003) {
            out.text(_key2002);
            var _keys2015 = Array<(u8[], u8[], String)>();
            for (var (_key2014, _) in value.method_overload_sets[_key2002]) {
                var _scratch2016 = out.scratch();
                _scratch2016.text(_key2014);
                var _vscratch2018 = out.scratch();
                _vscratch2018.unsigned(value.method_overload_sets[_key2002][_key2014].count);
                for (var _item2019 in value.method_overload_sets[_key2002][_key2014]) {
                    _vscratch2018.text(_item2019);
                }
                _keys2015.append((_scratch2016.finish(), _vscratch2018.finish(), _key2014));
            }
            _keys2015.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            out.unsigned(_keys2015.count);
            for (var (_bytes2017, _, _key2014) in _keys2015) {
                out.text(_key2014);
                out.unsigned(value.method_overload_sets[_key2002][_key2014].count);
                for (var _item2020 in value.method_overload_sets[_key2002][_key2014]) {
                    out.text(_item2020);
                }
            }
        }
        for (var (_okey2021, _) in value.method_overload_sets) {
            var _own2022 = RecordOut();
            _own2022.blank_bodies = true;
            _own2022.blank_locs = true;
            _own2022.pending_as_bytes = true;
            _own2022.text(_okey2021);
            var _keys2024 = Array<(u8[], u8[], String)>();
            for (var (_key2023, _) in value.method_overload_sets[_okey2021]) {
                var _scratch2025 = _own2022.scratch();
                _scratch2025.text(_key2023);
                var _vscratch2027 = _own2022.scratch();
                _vscratch2027.unsigned(value.method_overload_sets[_okey2021][_key2023].count);
                for (var _item2028 in value.method_overload_sets[_okey2021][_key2023]) {
                    _vscratch2027.text(_item2028);
                }
                _keys2024.append((_scratch2025.finish(), _vscratch2027.finish(), _key2023));
            }
            _keys2024.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            _own2022.unsigned(_keys2024.count);
            for (var (_bytes2026, _, _key2023) in _keys2024) {
                _own2022.text(_key2023);
                _own2022.unsigned(value.method_overload_sets[_okey2021][_key2023].count);
                for (var _item2029 in value.method_overload_sets[_okey2021][_key2023]) {
                    _own2022.text(_item2029);
                }
            }
            base.own("method_overload_sets", interface_text(_own2022));
        }
        base.count("method_overload_sets whole", 0);
    }
    base.stat("method_overload_sets", out.values.count - _mark);
    _mark = out.values.count;
    _m_ExtensionScopes_write(out, value.extension_scopes);
    base.stat("extension_scopes", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2060 = 0;
    var _news2061 = HashSet<Loc>();
    for (var _key2057 in value.private_functions) {
        var _kscratch2058 = base.scratch();
        _kscratch2058.loc(_key2057);
        var _vscratch2059 = base.scratch();
        var _had = base.entry("private_functions", _kscratch2058, _vscratch2059);
        if (_had >= 0) {
            _kept2060 += 1;
        }
        if (_had != 1) {
            _news2061.insert(_key2057);
        }
    }
    if (_kept2060 == base.size("private_functions")) {
        out.unsigned(1);
        var _keys2063 = Array<(u8[], u8[], Loc)>();
        for (var _key2062 in _news2061) {
            var _scratch2064 = out.scratch();
            _scratch2064.loc(_key2062);
            var _vscratch2066 = out.scratch();
            _keys2063.append((_scratch2064.finish(), _vscratch2066.finish(), _key2062));
        }
        _keys2063.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2063.count);
        for (var (_bytes2065, _, _key2062) in _keys2063) {
            out.loc(_key2062);
        }
        for (var _okey2067 in _news2061) {
            var _own2068 = RecordOut();
            _own2068.blank_bodies = true;
            _own2068.blank_locs = true;
            _own2068.pending_as_bytes = true;
            _own2068.loc(_okey2067);
            base.own_at("private_functions", _okey2067, interface_text(_own2068));
        }
    } else {
        out.unsigned(0);
        var _keys2070 = Array<(u8[], u8[], Loc)>();
        for (var _key2069 in value.private_functions) {
            var _scratch2071 = out.scratch();
            _scratch2071.loc(_key2069);
            var _vscratch2073 = out.scratch();
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
        }
        for (var _okey2074 in value.private_functions) {
            var _own2075 = RecordOut();
            _own2075.blank_bodies = true;
            _own2075.blank_locs = true;
            _own2075.pending_as_bytes = true;
            _own2075.loc(_okey2074);
            base.own_at("private_functions", _okey2074, interface_text(_own2075));
        }
        base.count("private_functions whole", 0);
    }
    base.stat("private_functions", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2086 = 0;
    var _news2087 = HashSet<Loc>();
    for (var _key2083 in value.file_private_functions) {
        var _kscratch2084 = base.scratch();
        _kscratch2084.loc(_key2083);
        var _vscratch2085 = base.scratch();
        var _had = base.entry("file_private_functions", _kscratch2084, _vscratch2085);
        if (_had >= 0) {
            _kept2086 += 1;
        }
        if (_had != 1) {
            _news2087.insert(_key2083);
        }
    }
    if (_kept2086 == base.size("file_private_functions")) {
        out.unsigned(1);
        var _keys2089 = Array<(u8[], u8[], Loc)>();
        for (var _key2088 in _news2087) {
            var _scratch2090 = out.scratch();
            _scratch2090.loc(_key2088);
            var _vscratch2092 = out.scratch();
            _keys2089.append((_scratch2090.finish(), _vscratch2092.finish(), _key2088));
        }
        _keys2089.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2089.count);
        for (var (_bytes2091, _, _key2088) in _keys2089) {
            out.loc(_key2088);
        }
        for (var _okey2093 in _news2087) {
            var _own2094 = RecordOut();
            _own2094.blank_bodies = true;
            _own2094.blank_locs = true;
            _own2094.pending_as_bytes = true;
            _own2094.loc(_okey2093);
            base.own_at("file_private_functions", _okey2093, interface_text(_own2094));
        }
    } else {
        out.unsigned(0);
        var _keys2096 = Array<(u8[], u8[], Loc)>();
        for (var _key2095 in value.file_private_functions) {
            var _scratch2097 = out.scratch();
            _scratch2097.loc(_key2095);
            var _vscratch2099 = out.scratch();
            _keys2096.append((_scratch2097.finish(), _vscratch2099.finish(), _key2095));
        }
        _keys2096.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2096.count);
        for (var (_bytes2098, _, _key2095) in _keys2096) {
            out.loc(_key2095);
        }
        for (var _okey2100 in value.file_private_functions) {
            var _own2101 = RecordOut();
            _own2101.blank_bodies = true;
            _own2101.blank_locs = true;
            _own2101.pending_as_bytes = true;
            _own2101.loc(_okey2100);
            base.own_at("file_private_functions", _okey2100, interface_text(_own2101));
        }
        base.count("file_private_functions whole", 0);
    }
    base.stat("file_private_functions", out.values.count - _mark);
    _mark = out.values.count;
    var _n2111 = base.size("call_targets");
    var _scratch2110 = base.scratch();
    if (value.call_targets.count >= _n2111) {
        for (var _i2112 in 0.._n2111) {
            var (_t2113, _t2114) = value.call_targets[_i2112];
            _scratch2110.loc(_t2113);
            _scratch2110.text(_t2114);
        }
    }
    if (value.call_targets.count >= _n2111 and base.same_list("call_targets", _scratch2110)) {
        out.unsigned(1);
        out.unsigned(_n2111);
        out.unsigned(value.call_targets.count - _n2111);
        for (var _i2112 in _n2111..value.call_targets.count) {
            var (_t2115, _t2116) = value.call_targets[_i2112];
            out.loc(_t2115);
            out.text(_t2116);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.call_targets.count);
        for (var _item2117 in value.call_targets) {
            var (_t2118, _t2119) = _item2117;
            out.loc(_t2118);
            out.text(_t2119);
        }
        base.count("call_targets whole", 0);
    }
    base.stat("call_targets", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2136 = 0;
    var _news2137 = Array<(Loc, String)>();
    for (var _item2134 in value.argument_names) {
        var _escratch2135 = base.scratch();
        var (_t2138, _t2139) = _item2134;
        _escratch2135.loc(_t2138);
        _escratch2135.text(_t2139);
        if (base.entry("argument_names", _escratch2135, base.scratch()) >= 0) {
            _kept2136 += 1;
        } else {
            _news2137.append(_item2134);
        }
    }
    if (_kept2136 == base.size("argument_names")) {
        out.unsigned(1);
        out.unsigned(_news2137.count);
        for (var _item2140 in _news2137) {
            var (_t2141, _t2142) = _item2140;
            out.loc(_t2141);
            out.text(_t2142);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.argument_names.count);
        for (var _item2143 in value.argument_names) {
            var (_t2144, _t2145) = _item2143;
            out.loc(_t2144);
            out.text(_t2145);
        }
        base.count("argument_names whole", 0);
    }
    base.stat("argument_names", out.values.count - _mark);
    _mark = out.values.count;
    var _n2160 = base.size("namespaces");
    var _scratch2159 = base.scratch();
    if (value.namespaces.count >= _n2160) {
        for (var _i2161 in 0.._n2160) {
            _scratch2159.text(value.namespaces[_i2161]);
        }
    }
    if (value.namespaces.count >= _n2160 and base.same_list("namespaces", _scratch2159)) {
        out.unsigned(1);
        out.unsigned(_n2160);
        out.unsigned(value.namespaces.count - _n2160);
        for (var _i2161 in _n2160..value.namespaces.count) {
            out.text(value.namespaces[_i2161]);
            {
                var _own2162 = RecordOut();
                _own2162.blank_bodies = true;
                _own2162.blank_locs = true;
                _own2162.pending_as_bytes = true;
                _own2162.text(value.namespaces[_i2161]);
                base.own("namespaces", interface_text(_own2162));
            }
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.namespaces.count);
        for (var _item2163 in value.namespaces) {
            out.text(_item2163);
        }
        for (var _i2161 in 0..value.namespaces.count) {
            {
                var _own2164 = RecordOut();
                _own2164.blank_bodies = true;
                _own2164.blank_locs = true;
                _own2164.pending_as_bytes = true;
                _own2164.text(value.namespaces[_i2161]);
                base.own("namespaces", interface_text(_own2164));
            }
        }
        base.count("namespaces whole", 0);
    }
    base.stat("namespaces", out.values.count - _mark);
    _mark = out.values.count;
    var _n2175 = base.size("cached_files");
    var _scratch2174 = base.scratch();
    if (value.cached_files.count >= _n2175) {
        for (var _i2176 in 0.._n2175) {
            _scratch2174.flag(value.cached_files[_i2176]);
        }
    }
    if (value.cached_files.count >= _n2175 and base.same_list("cached_files", _scratch2174)) {
        out.unsigned(1);
        out.unsigned(_n2175);
        out.unsigned(value.cached_files.count - _n2175);
        for (var _i2176 in _n2175..value.cached_files.count) {
            out.flag(value.cached_files[_i2176]);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.cached_files.count);
        for (var _item2177 in value.cached_files) {
            out.flag(_item2177);
        }
        base.count("cached_files whole", 0);
    }
    base.stat("cached_files", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2189 = 0;
    var _news2190 = HashMap<Loc, String>();
    for (var (_key2186, _) in value.recorded_summaries) {
        var _kscratch2187 = base.scratch();
        _kscratch2187.loc(_key2186);
        var _vscratch2188 = base.scratch();
        _vscratch2188.text(value.recorded_summaries[_key2186]);
        var _had = base.entry("recorded_summaries", _kscratch2187, _vscratch2188);
        if (_had >= 0) {
            _kept2189 += 1;
        }
        if (_had != 1) {
            _news2190[_key2186] = value.recorded_summaries[_key2186];
        }
    }
    if (_kept2189 == base.size("recorded_summaries")) {
        out.unsigned(1);
        var _keys2192 = Array<(u8[], u8[], Loc)>();
        for (var (_key2191, _) in _news2190) {
            var _scratch2193 = out.scratch();
            _scratch2193.loc(_key2191);
            var _vscratch2195 = out.scratch();
            _vscratch2195.text(_news2190[_key2191]);
            _keys2192.append((_scratch2193.finish(), _vscratch2195.finish(), _key2191));
        }
        _keys2192.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2192.count);
        for (var (_bytes2194, _, _key2191) in _keys2192) {
            out.loc(_key2191);
            out.text(_news2190[_key2191]);
        }
    } else {
        out.unsigned(0);
        var _keys2197 = Array<(u8[], u8[], Loc)>();
        for (var (_key2196, _) in value.recorded_summaries) {
            var _scratch2198 = out.scratch();
            _scratch2198.loc(_key2196);
            var _vscratch2200 = out.scratch();
            _vscratch2200.text(value.recorded_summaries[_key2196]);
            _keys2197.append((_scratch2198.finish(), _vscratch2200.finish(), _key2196));
        }
        _keys2197.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2197.count);
        for (var (_bytes2199, _, _key2196) in _keys2197) {
            out.loc(_key2196);
            out.text(value.recorded_summaries[_key2196]);
        }
        base.count("recorded_summaries whole", 0);
    }
    base.stat("recorded_summaries", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2213 = 0;
    var _news2214 = HashSet<Loc>();
    for (var _key2210 in value.stripped) {
        var _kscratch2211 = base.scratch();
        _kscratch2211.loc(_key2210);
        var _vscratch2212 = base.scratch();
        var _had = base.entry("stripped", _kscratch2211, _vscratch2212);
        if (_had >= 0) {
            _kept2213 += 1;
        }
        if (_had != 1) {
            _news2214.insert(_key2210);
        }
    }
    if (_kept2213 == base.size("stripped")) {
        out.unsigned(1);
        var _keys2216 = Array<(u8[], u8[], Loc)>();
        for (var _key2215 in _news2214) {
            var _scratch2217 = out.scratch();
            _scratch2217.loc(_key2215);
            var _vscratch2219 = out.scratch();
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
            out.loc(_key2215);
        }
    } else {
        out.unsigned(0);
        var _keys2221 = Array<(u8[], u8[], Loc)>();
        for (var _key2220 in value.stripped) {
            var _scratch2222 = out.scratch();
            _scratch2222.loc(_key2220);
            var _vscratch2224 = out.scratch();
            _keys2221.append((_scratch2222.finish(), _vscratch2224.finish(), _key2220));
        }
        _keys2221.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2221.count);
        for (var (_bytes2223, _, _key2220) in _keys2221) {
            out.loc(_key2220);
        }
        base.count("stripped whole", 0);
    }
    base.stat("stripped", out.values.count - _mark);
    _mark = out.values.count;
    out.flag(value.templates.frozen);
    var _seq2234 = base.ref_templates;
    ulong _bj2235 = 0;
    var _news2237 = Array<ulong>();
    var _patches2238 = Array<(ulong, ulong)>();
    for (var _i2239 in 0..value.templates.structs.count) {
        if (_bj2235 < _seq2234.count
            and value.templates.structs[_i2239] === _seq2234[_bj2235]
            and !value.extended_checked.contains(value.templates.structs[_i2239].name)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_StructDef_write(scratch, value.templates.structs[_i2239]);
                base.verify_same("t", _bj2235, scratch, value.templates.structs[_i2239].name);
            }
            _bj2235 += 1;
        } else if (_bj2235 < _seq2234.count
            and !(value.templates.structs[_i2239] === _seq2234[_bj2235])
            and _same_m_StructDef(value.templates.structs[_i2239], _seq2234[_bj2235], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_StructDef_write(scratch, value.templates.structs[_i2239]);
                base.verify_same("t", _bj2235, scratch, value.templates.structs[_i2239].name);
            }
            _bj2235 += 1;
        } else if (_bj2235 < _seq2234.count and value.templates.structs[_i2239].name == _seq2234[_bj2235].name) {
            _patches2238.append((_i2239, _bj2235));
            _bj2235 += 1;
        } else {
            _news2237.append(_i2239);
        }
    }
    if (_bj2235 == _seq2234.count) {
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
        var _struct_hits2233 = HashSet<long>();
        var _slots2236 = HashMap<String, long>();
        for (var _i2239 in 0.._seq2234.count) {
            if (!_slots2236.contains(_seq2234[_i2239].name)) {
                _slots2236[_seq2234[_i2239].name] = _i2239 as long;
            }
        }
        out.unsigned(value.templates.structs.count);
        for (var _i2239 in 0..value.templates.structs.count) {
            var _item2232 = value.templates.structs[_i2239];
            var _slot = _slots2236.try_get(_item2232.name);
            long named = _slot.is_value() ? _slot.value() : -1;
            long at = -1;
            if (named >= 0
                and _seq2234[named as ulong] === _item2232
                and !value.extended_checked.contains(_item2232.name)) {
                at = named;
            }
            ulong _before = out.values.count;
            if (at >= 0) {
                _struct_hits2233.insert(at);
                out.unsigned((at as ulong) * 2 + 1);
            } else if (named >= 0) {
                _struct_hits2233.insert(named);
                out.unsigned(2);
                out.unsigned(named as ulong);
                _patch_t_write(out, _item2232, base, named as ulong);
                base.count("t patched", out.values.count - _before);
            } else {
                out.unsigned(0);
                _m_StructDef_write(out, _item2232);
                base.count("t new", out.values.count - _before);
            }
        }
        base.missed("t", "t", _struct_hits2233.count);
    }
    var _seq2255 = base.ref_template_functions;
    ulong _bj2256 = 0;
    var _news2257 = Array<ulong>();
    var _changed2251 = Array<(ulong, ulong)>();
    for (var _i2258 in 0..value.templates.functions.count) {
        if (_bj2256 < _seq2255.count and value.templates.functions[_i2258] === _seq2255[_bj2256]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.templates.functions[_i2258]);
                base.verify_same("tf", _bj2256, scratch);
            }
            _bj2256 += 1;
        } else if (_bj2256 < _seq2255.count
            and _same_m_FunctionDef(value.templates.functions[_i2258], _seq2255[_bj2256], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.templates.functions[_i2258]);
                base.verify_same("tf", _bj2256, scratch);
            }
            _bj2256 += 1;
        } else if (_bj2256 < _seq2255.count and value.templates.functions[_i2258].name == _seq2255[_bj2256].name) {
            _changed2251.append((_i2258, _bj2256));
            _bj2256 += 1;
        } else {
            _news2257.append(_i2258);
        }
    }
    if (_bj2256 == _seq2255.count) {
        out.unsigned(2);
        out.unsigned(_changed2251.count);
        for (var (_i2258, _b) in _changed2251) {
            out.text(value.templates.functions[_i2258].name);
            out.unsigned(_b);
            _m_FunctionDef_write(out, value.templates.functions[_i2258]);
            {
                var _own2259 = RecordOut();
                _own2259.blank_bodies = false;
                _own2259.blank_locs = true;
                _own2259.pending_as_bytes = true;
                _m_FunctionDef_write(_own2259, value.templates.functions[_i2258]);
                base.own("templates functions", interface_text(_own2259));
            }
        }
        base.count("tf" + " changed", _changed2251.count);
        out.unsigned(_news2257.count);
        for (var _i2258 in _news2257) {
            out.unsigned(_i2258);
            _m_FunctionDef_write(out, value.templates.functions[_i2258]);
            {
                var _own2260 = RecordOut();
                _own2260.blank_bodies = false;
                _own2260.blank_locs = true;
                _own2260.pending_as_bytes = true;
                _m_FunctionDef_write(_own2260, value.templates.functions[_i2258]);
                base.own("templates functions", interface_text(_own2260));
            }
        }
        base.count("tf" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("tf" + " whole", 0);
        out.unsigned(value.templates.functions.count);
        for (var _i2258 in 0..value.templates.functions.count) {
            _m_FunctionDef_write(out, value.templates.functions[_i2258]);
            {
                var _own2261 = RecordOut();
                _own2261.blank_bodies = false;
                _own2261.blank_locs = true;
                _own2261.pending_as_bytes = true;
                _m_FunctionDef_write(_own2261, value.templates.functions[_i2258]);
                base.own("templates functions", interface_text(_own2261));
            }
        }
    }
    base.stat("templates", out.values.count - _mark);
    _mark = out.values.count;
    base.write_checked(out, value.checked);
    base.stat("checked", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2274 = 0;
    var _news2275 = HashMap<String, SpecRequest>();
    for (var (_key2271, _) in value.spec_requests) {
        var _kscratch2272 = base.scratch();
        _kscratch2272.text(_key2271);
        var _vscratch2273 = base.scratch();
        _m_SpecRequest_write(_vscratch2273, value.spec_requests[_key2271]);
        var _had = base.entry("spec_requests", _kscratch2272, _vscratch2273);
        if (_had >= 0) {
            _kept2274 += 1;
        }
        if (_had != 1) {
            _news2275[_key2271] = value.spec_requests[_key2271];
        }
    }
    if (_kept2274 == base.size("spec_requests")) {
        out.unsigned(1);
        var _keys2277 = Array<(u8[], u8[], String)>();
        for (var (_key2276, _) in _news2275) {
            var _scratch2278 = out.scratch();
            _scratch2278.text(_key2276);
            var _vscratch2280 = out.scratch();
            _m_SpecRequest_write(_vscratch2280, _news2275[_key2276]);
            _keys2277.append((_scratch2278.finish(), _vscratch2280.finish(), _key2276));
        }
        _keys2277.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2277.count);
        for (var (_bytes2279, _, _key2276) in _keys2277) {
            out.text(_key2276);
            _m_SpecRequest_write(out, _news2275[_key2276]);
        }
        for (var (_okey2281, _) in _news2275) {
            var _own2282 = RecordOut();
            _own2282.blank_bodies = true;
            _own2282.blank_locs = true;
            _own2282.pending_as_bytes = true;
            _own2282.text(_okey2281);
            _m_SpecRequest_write(_own2282, _news2275[_okey2281]);
            base.own("spec_requests", interface_text(_own2282));
        }
    } else {
        out.unsigned(0);
        var _keys2284 = Array<(u8[], u8[], String)>();
        for (var (_key2283, _) in value.spec_requests) {
            var _scratch2285 = out.scratch();
            _scratch2285.text(_key2283);
            var _vscratch2287 = out.scratch();
            _m_SpecRequest_write(_vscratch2287, value.spec_requests[_key2283]);
            _keys2284.append((_scratch2285.finish(), _vscratch2287.finish(), _key2283));
        }
        _keys2284.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2284.count);
        for (var (_bytes2286, _, _key2283) in _keys2284) {
            out.text(_key2283);
            _m_SpecRequest_write(out, value.spec_requests[_key2283]);
        }
        for (var (_okey2288, _) in value.spec_requests) {
            var _own2289 = RecordOut();
            _own2289.blank_bodies = true;
            _own2289.blank_locs = true;
            _own2289.pending_as_bytes = true;
            _own2289.text(_okey2288);
            _m_SpecRequest_write(_own2289, value.spec_requests[_okey2288]);
            base.own("spec_requests", interface_text(_own2289));
        }
        base.count("spec_requests whole", 0);
    }
    base.stat("spec_requests", out.values.count - _mark);
    _mark = out.values.count;
    out.flag(value.record_summaries);
    base.stat("record_summaries", out.values.count - _mark);
    _mark = out.values.count;
    var _n2302 = base.size("summaries_to_record");
    var _scratch2301 = base.scratch();
    if (value.summaries_to_record.count >= _n2302) {
        for (var _i2303 in 0.._n2302) {
            var (_t2304, _t2305) = value.summaries_to_record[_i2303];
            _scratch2301.loc(_t2304);
            _scratch2301.text(_t2305);
        }
    }
    if (value.summaries_to_record.count >= _n2302 and base.same_list("summaries_to_record", _scratch2301)) {
        out.unsigned(1);
        out.unsigned(_n2302);
        out.unsigned(value.summaries_to_record.count - _n2302);
        for (var _i2303 in _n2302..value.summaries_to_record.count) {
            var (_t2306, _t2307) = value.summaries_to_record[_i2303];
            out.loc(_t2306);
            out.text(_t2307);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.summaries_to_record.count);
        for (var _item2308 in value.summaries_to_record) {
            var (_t2309, _t2310) = _item2308;
            out.loc(_t2309);
            out.text(_t2310);
        }
        base.count("summaries_to_record whole", 0);
    }
    base.stat("summaries_to_record", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2328 = 0;
    var _news2329 = HashMap<String, Array<bool>>();
    for (var (_key2325, _) in value.caller_copies) {
        var _kscratch2326 = base.scratch();
        _kscratch2326.text(_key2325);
        var _vscratch2327 = base.scratch();
        _vscratch2327.unsigned(value.caller_copies[_key2325].count);
        for (var _item2330 in value.caller_copies[_key2325]) {
            _vscratch2327.flag(_item2330);
        }
        var _had = base.entry("caller_copies", _kscratch2326, _vscratch2327);
        if (_had >= 0) {
            _kept2328 += 1;
        }
        if (_had != 1) {
            _news2329[_key2325] = value.caller_copies[_key2325];
        }
    }
    if (_kept2328 == base.size("caller_copies")) {
        out.unsigned(1);
        var _keys2332 = Array<(u8[], u8[], String)>();
        for (var (_key2331, _) in _news2329) {
            var _scratch2333 = out.scratch();
            _scratch2333.text(_key2331);
            var _vscratch2335 = out.scratch();
            _vscratch2335.unsigned(_news2329[_key2331].count);
            for (var _item2336 in _news2329[_key2331]) {
                _vscratch2335.flag(_item2336);
            }
            _keys2332.append((_scratch2333.finish(), _vscratch2335.finish(), _key2331));
        }
        _keys2332.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2332.count);
        for (var (_bytes2334, _, _key2331) in _keys2332) {
            out.text(_key2331);
            out.unsigned(_news2329[_key2331].count);
            for (var _item2337 in _news2329[_key2331]) {
                out.flag(_item2337);
            }
        }
        for (var (_okey2338, _) in _news2329) {
            var _own2339 = RecordOut();
            _own2339.blank_bodies = true;
            _own2339.blank_locs = true;
            _own2339.pending_as_bytes = true;
            _own2339.text(_okey2338);
            _own2339.unsigned(_news2329[_okey2338].count);
            for (var _item2340 in _news2329[_okey2338]) {
                _own2339.flag(_item2340);
            }
            base.own("caller_copies", interface_text(_own2339));
        }
    } else {
        out.unsigned(0);
        var _keys2342 = Array<(u8[], u8[], String)>();
        for (var (_key2341, _) in value.caller_copies) {
            var _scratch2343 = out.scratch();
            _scratch2343.text(_key2341);
            var _vscratch2345 = out.scratch();
            _vscratch2345.unsigned(value.caller_copies[_key2341].count);
            for (var _item2346 in value.caller_copies[_key2341]) {
                _vscratch2345.flag(_item2346);
            }
            _keys2342.append((_scratch2343.finish(), _vscratch2345.finish(), _key2341));
        }
        _keys2342.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2342.count);
        for (var (_bytes2344, _, _key2341) in _keys2342) {
            out.text(_key2341);
            out.unsigned(value.caller_copies[_key2341].count);
            for (var _item2347 in value.caller_copies[_key2341]) {
                out.flag(_item2347);
            }
        }
        for (var (_okey2348, _) in value.caller_copies) {
            var _own2349 = RecordOut();
            _own2349.blank_bodies = true;
            _own2349.blank_locs = true;
            _own2349.pending_as_bytes = true;
            _own2349.text(_okey2348);
            _own2349.unsigned(value.caller_copies[_okey2348].count);
            for (var _item2350 in value.caller_copies[_okey2348]) {
                _own2349.flag(_item2350);
            }
            base.own("caller_copies", interface_text(_own2349));
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
    var _f1497 = Array<ast.Import>();
    var _mode1500 = input.unsigned();
    if (_mode1500 == 2) {
        var _changed1486 = HashMap<ulong, ast.Import>();
        ulong _bi1501 = 0;
        var _n1498 = input.count();
        for (var _ in 0.._n1498) {
            var _at1502 = input.unsigned();
            while (_f1497.count < _at1502 or (input.merging and _bi1501 < base.imports.count)) {
                var _c = _changed1486.try_get(_bi1501);
                _f1497.append(_c.is_value() ? _c.value() : base.imports[_bi1501]);
                _bi1501 += 1;
            }
            _f1497.append(_a_Import_read(input));
        }
        while (_bi1501 < base.imports.count) {
            var _c = _changed1486.try_get(_bi1501);
            _f1497.append(_c.is_value() ? _c.value() : base.imports[_bi1501]);
            _bi1501 += 1;
        }
    } else if (_mode1500 == 3) {
        var _n1498 = input.count();
        for (var _ in 0.._n1498) {
            _f1497.append(_a_Import_read(input));
        }
    } else {
        var _n1498 = input.count();
        if (input.merging) {
            input.error = "imports" + " written by place";
        }
        for (var _ in 0.._n1498) {
            var _tag1499 = input.unsigned();
            if (_tag1499 & 1 == 1) {
                if (!input.merging) {
                    _f1497.append(base.imports[_tag1499 >> 1]);
                }
            } else {
                var _read = _a_Import_read(input);
                if (!input.merging or true) {
                    _f1497.append(_read);
                }
            }
        }
    }
    var _f1530 = Array<StructDef>();
    var _mode1533 = input.unsigned();
    if (_mode1533 == 2) {
        var _patched1536 = HashMap<ulong, StructDef>();
        var _n1531 = input.count();
        for (var _ in 0.._n1531) {
            var _name = input.text();
            var _slot = input.unsigned();
            if (input.merging) {
                _slot = struct_named(base.structs, _name);
            }
            if (_slot >= base.structs.count) {
                input.error = $"no struct {_name} to patch";
                break;
            }
            _patched1536[_slot] = _patch_s_read(input, base.structs[_slot]);
        }
        ulong _bi1534 = 0;
        var _added = input.count();
        for (var _ in 0.._added) {
            var _at1535 = input.unsigned();
            while (_f1530.count < _at1535 or (input.merging and _bi1534 < base.structs.count)) {
                var _p = _patched1536.try_get(_bi1534);
                _f1530.append(_p.is_value() ? _p.value() : base.structs[_bi1534]);
                _bi1534 += 1;
            }
            _f1530.append(_m_StructDef_read_lazy(input));
        }
        while (_bi1534 < base.structs.count) {
            var _p = _patched1536.try_get(_bi1534);
            _f1530.append(_p.is_value() ? _p.value() : base.structs[_bi1534]);
            _bi1534 += 1;
        }
    } else {
        if (input.merging) {
            input.error = "structs written by place";
        }
        var _n1531 = input.count();
        for (var _ in 0.._n1531) {
            var _tag1532 = input.unsigned();
            if (_tag1532 & 1 == 1) {
                _f1530.append(base.structs[(_tag1532 >> 1) < base.structs.count ? _tag1532 >> 1 : 0]);
            } else if (_tag1532 == 2) {
                var _was = base.structs[input.unsigned()];
                _f1530.append(_patch_s_read(input, _was));
            } else {
                _f1530.append(_m_StructDef_read_lazy(input));
            }
        }
    }
    var _f1550 = Array<TraitDef>();
    var _mode1553 = input.unsigned();
    if (_mode1553 == 2) {
        var _changed1539 = HashMap<ulong, TraitDef>();
        ulong _bi1554 = 0;
        var _n1551 = input.count();
        for (var _ in 0.._n1551) {
            var _at1555 = input.unsigned();
            while (_f1550.count < _at1555 or (input.merging and _bi1554 < base.traits.count)) {
                var _c = _changed1539.try_get(_bi1554);
                _f1550.append(_c.is_value() ? _c.value() : base.traits[_bi1554]);
                _bi1554 += 1;
            }
            _f1550.append(_m_TraitDef_read(input));
        }
        while (_bi1554 < base.traits.count) {
            var _c = _changed1539.try_get(_bi1554);
            _f1550.append(_c.is_value() ? _c.value() : base.traits[_bi1554]);
            _bi1554 += 1;
        }
    } else if (_mode1553 == 3) {
        var _n1551 = input.count();
        for (var _ in 0.._n1551) {
            _f1550.append(_m_TraitDef_read(input));
        }
    } else {
        var _n1551 = input.count();
        if (input.merging) {
            input.error = "traits" + " written by place";
        }
        for (var _ in 0.._n1551) {
            var _tag1552 = input.unsigned();
            if (_tag1552 & 1 == 1) {
                if (!input.merging) {
                    _f1550.append(base.traits[_tag1552 >> 1]);
                }
            } else {
                var _read = _m_TraitDef_read(input);
                if (!input.merging or true) {
                    _f1550.append(_read);
                }
            }
        }
    }
    var _f1569 = Array<ExtensionDef>();
    var _mode1572 = input.unsigned();
    if (_mode1572 == 2) {
        var _changed1558 = HashMap<ulong, ExtensionDef>();
        ulong _bi1573 = 0;
        var _n1570 = input.count();
        for (var _ in 0.._n1570) {
            var _at1574 = input.unsigned();
            while (_f1569.count < _at1574 or (input.merging and _bi1573 < base.extensions.count)) {
                var _c = _changed1558.try_get(_bi1573);
                _f1569.append(_c.is_value() ? _c.value() : base.extensions[_bi1573]);
                _bi1573 += 1;
            }
            _f1569.append(_m_ExtensionDef_read(input));
        }
        while (_bi1573 < base.extensions.count) {
            var _c = _changed1558.try_get(_bi1573);
            _f1569.append(_c.is_value() ? _c.value() : base.extensions[_bi1573]);
            _bi1573 += 1;
        }
    } else if (_mode1572 == 3) {
        var _n1570 = input.count();
        for (var _ in 0.._n1570) {
            _f1569.append(_m_ExtensionDef_read(input));
        }
    } else {
        var _n1570 = input.count();
        if (input.merging) {
            input.error = "extensions" + " written by place";
        }
        for (var _ in 0.._n1570) {
            var _tag1571 = input.unsigned();
            if (_tag1571 & 1 == 1) {
                if (!input.merging) {
                    _f1569.append(base.extensions[_tag1571 >> 1]);
                }
            } else {
                var _read = _m_ExtensionDef_read(input);
                if (!input.merging or true) {
                    _f1569.append(_read);
                }
            }
        }
    }
    var _f1588 = Array<FunctionDef>();
    var _mode1591 = input.unsigned();
    if (_mode1591 == 2) {
        var _changed1577 = HashMap<ulong, FunctionDef>();
        var _nc1579 = input.count();
        for (var _ in 0.._nc1579) {
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
                _changed1577[_slot] = _el;
            } else {
                input.error = $"no {_name} to change";
            }
        }
        ulong _bi1592 = 0;
        var _n1589 = input.count();
        for (var _ in 0.._n1589) {
            var _at1593 = input.unsigned();
            while (_f1588.count < _at1593 or (input.merging and _bi1592 < base.functions.count)) {
                var _c = _changed1577.try_get(_bi1592);
                _f1588.append(_c.is_value() ? _c.value() : base.functions[_bi1592]);
                _bi1592 += 1;
            }
            _f1588.append(_m_FunctionDef_read_lazy(input));
        }
        while (_bi1592 < base.functions.count) {
            var _c = _changed1577.try_get(_bi1592);
            _f1588.append(_c.is_value() ? _c.value() : base.functions[_bi1592]);
            _bi1592 += 1;
        }
    } else if (_mode1591 == 3) {
        var _n1589 = input.count();
        for (var _ in 0.._n1589) {
            _f1588.append(_m_FunctionDef_read_lazy(input));
        }
    } else {
        var _n1589 = input.count();
        if (input.merging) {
            input.error = "functions" + " written by place";
        }
        for (var _ in 0.._n1589) {
            var _tag1590 = input.unsigned();
            if (_tag1590 & 1 == 1) {
                if (!input.merging) {
                    _f1588.append(base.functions[_tag1590 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read_lazy(input);
                if (!input.merging or true) {
                    _f1588.append(_read);
                }
            }
        }
    }
    var _f1607 = Array<ExternDef>();
    var _mode1610 = input.unsigned();
    if (_mode1610 == 2) {
        var _changed1596 = HashMap<ulong, ExternDef>();
        ulong _bi1611 = 0;
        var _n1608 = input.count();
        for (var _ in 0.._n1608) {
            var _at1612 = input.unsigned();
            while (_f1607.count < _at1612 or (input.merging and _bi1611 < base.externs.count)) {
                var _c = _changed1596.try_get(_bi1611);
                _f1607.append(_c.is_value() ? _c.value() : base.externs[_bi1611]);
                _bi1611 += 1;
            }
            _f1607.append(_m_ExternDef_read(input));
        }
        while (_bi1611 < base.externs.count) {
            var _c = _changed1596.try_get(_bi1611);
            _f1607.append(_c.is_value() ? _c.value() : base.externs[_bi1611]);
            _bi1611 += 1;
        }
    } else if (_mode1610 == 3) {
        var _n1608 = input.count();
        for (var _ in 0.._n1608) {
            _f1607.append(_m_ExternDef_read(input));
        }
    } else {
        var _n1608 = input.count();
        if (input.merging) {
            input.error = "externs" + " written by place";
        }
        for (var _ in 0.._n1608) {
            var _tag1609 = input.unsigned();
            if (_tag1609 & 1 == 1) {
                if (!input.merging) {
                    _f1607.append(base.externs[_tag1609 >> 1]);
                }
            } else {
                var _read = _m_ExternDef_read(input);
                if (!input.merging or true) {
                    _f1607.append(_read);
                }
            }
        }
    }
    var _f1626 = Array<VariableDef>();
    var _mode1629 = input.unsigned();
    if (_mode1629 == 2) {
        var _changed1615 = HashMap<ulong, VariableDef>();
        ulong _bi1630 = 0;
        var _n1627 = input.count();
        for (var _ in 0.._n1627) {
            var _at1631 = input.unsigned();
            while (_f1626.count < _at1631 or (input.merging and _bi1630 < base.globals.count)) {
                var _c = _changed1615.try_get(_bi1630);
                _f1626.append(_c.is_value() ? _c.value() : base.globals[_bi1630]);
                _bi1630 += 1;
            }
            _f1626.append(_m_VariableDef_read(input));
        }
        while (_bi1630 < base.globals.count) {
            var _c = _changed1615.try_get(_bi1630);
            _f1626.append(_c.is_value() ? _c.value() : base.globals[_bi1630]);
            _bi1630 += 1;
        }
    } else if (_mode1629 == 3) {
        var _n1627 = input.count();
        for (var _ in 0.._n1627) {
            _f1626.append(_m_VariableDef_read(input));
        }
    } else {
        var _n1627 = input.count();
        if (input.merging) {
            input.error = "globals" + " written by place";
        }
        for (var _ in 0.._n1627) {
            var _tag1628 = input.unsigned();
            if (_tag1628 & 1 == 1) {
                if (!input.merging) {
                    _f1626.append(base.globals[_tag1628 >> 1]);
                }
            } else {
                var _read = _m_VariableDef_read(input);
                if (!input.merging or true) {
                    _f1626.append(_read);
                }
            }
        }
    }
    var _f1645 = Array<ModuleStaticBlock>();
    var _mode1648 = input.unsigned();
    if (_mode1648 == 2) {
        var _changed1634 = HashMap<ulong, ModuleStaticBlock>();
        ulong _bi1649 = 0;
        var _n1646 = input.count();
        for (var _ in 0.._n1646) {
            var _at1650 = input.unsigned();
            while (_f1645.count < _at1650 or (input.merging and _bi1649 < base.static_blocks.count)) {
                var _c = _changed1634.try_get(_bi1649);
                _f1645.append(_c.is_value() ? _c.value() : base.static_blocks[_bi1649]);
                _bi1649 += 1;
            }
            _f1645.append(_m_ModuleStaticBlock_read(input));
        }
        while (_bi1649 < base.static_blocks.count) {
            var _c = _changed1634.try_get(_bi1649);
            _f1645.append(_c.is_value() ? _c.value() : base.static_blocks[_bi1649]);
            _bi1649 += 1;
        }
    } else if (_mode1648 == 3) {
        var _n1646 = input.count();
        for (var _ in 0.._n1646) {
            _f1645.append(_m_ModuleStaticBlock_read(input));
        }
    } else {
        var _n1646 = input.count();
        if (input.merging) {
            input.error = "static_blocks" + " written by place";
        }
        for (var _ in 0.._n1646) {
            var _tag1647 = input.unsigned();
            if (_tag1647 & 1 == 1) {
                if (!input.merging) {
                    _f1645.append(base.static_blocks[_tag1647 >> 1]);
                }
            } else {
                var _read = _m_ModuleStaticBlock_read(input);
                if (!input.merging or true) {
                    _f1645.append(_read);
                }
            }
        }
    }
    var _f1664 = Array<EnumDef>();
    var _mode1667 = input.unsigned();
    if (_mode1667 == 2) {
        var _changed1653 = HashMap<ulong, EnumDef>();
        ulong _bi1668 = 0;
        var _n1665 = input.count();
        for (var _ in 0.._n1665) {
            var _at1669 = input.unsigned();
            while (_f1664.count < _at1669 or (input.merging and _bi1668 < base.enums.count)) {
                var _c = _changed1653.try_get(_bi1668);
                _f1664.append(_c.is_value() ? _c.value() : base.enums[_bi1668]);
                _bi1668 += 1;
            }
            _f1664.append(_m_EnumDef_read(input));
        }
        while (_bi1668 < base.enums.count) {
            var _c = _changed1653.try_get(_bi1668);
            _f1664.append(_c.is_value() ? _c.value() : base.enums[_bi1668]);
            _bi1668 += 1;
        }
    } else if (_mode1667 == 3) {
        var _n1665 = input.count();
        for (var _ in 0.._n1665) {
            _f1664.append(_m_EnumDef_read(input));
        }
    } else {
        var _n1665 = input.count();
        if (input.merging) {
            input.error = "enums" + " written by place";
        }
        for (var _ in 0.._n1665) {
            var _tag1666 = input.unsigned();
            if (_tag1666 & 1 == 1) {
                if (!input.merging) {
                    _f1664.append(base.enums[_tag1666 >> 1]);
                }
            } else {
                var _read = _m_EnumDef_read(input);
                if (!input.merging or true) {
                    _f1664.append(_read);
                }
            }
        }
    }
    var _f1683 = Array<TypeName>();
    var _mode1686 = input.unsigned();
    if (_mode1686 == 2) {
        var _changed1672 = HashMap<ulong, TypeName>();
        ulong _bi1687 = 0;
        var _n1684 = input.count();
        for (var _ in 0.._n1684) {
            var _at1688 = input.unsigned();
            while (_f1683.count < _at1688 or (input.merging and _bi1687 < base.struct_specs.count)) {
                var _c = _changed1672.try_get(_bi1687);
                _f1683.append(_c.is_value() ? _c.value() : base.struct_specs[_bi1687]);
                _bi1687 += 1;
            }
            _f1683.append(_m_TypeName_read(input));
        }
        while (_bi1687 < base.struct_specs.count) {
            var _c = _changed1672.try_get(_bi1687);
            _f1683.append(_c.is_value() ? _c.value() : base.struct_specs[_bi1687]);
            _bi1687 += 1;
        }
    } else if (_mode1686 == 3) {
        var _n1684 = input.count();
        for (var _ in 0.._n1684) {
            _f1683.append(_m_TypeName_read(input));
        }
    } else {
        var _n1684 = input.count();
        if (input.merging) {
            input.error = "struct_specs" + " written by place";
        }
        for (var _ in 0.._n1684) {
            var _tag1685 = input.unsigned();
            if (_tag1685 & 1 == 1) {
                if (!input.merging) {
                    _f1683.append(base.struct_specs[_tag1685 >> 1]);
                }
            } else {
                var _read = _m_TypeName_read(input);
                if (!input.merging or true) {
                    _f1683.append(_read);
                }
            }
        }
    }
    var _f1702 = Array<TypeName>();
    var _mode1705 = input.unsigned();
    if (_mode1705 == 2) {
        var _changed1691 = HashMap<ulong, TypeName>();
        ulong _bi1706 = 0;
        var _n1703 = input.count();
        for (var _ in 0.._n1703) {
            var _at1707 = input.unsigned();
            while (_f1702.count < _at1707 or (input.merging and _bi1706 < base.func_specs.count)) {
                var _c = _changed1691.try_get(_bi1706);
                _f1702.append(_c.is_value() ? _c.value() : base.func_specs[_bi1706]);
                _bi1706 += 1;
            }
            _f1702.append(_m_TypeName_read(input));
        }
        while (_bi1706 < base.func_specs.count) {
            var _c = _changed1691.try_get(_bi1706);
            _f1702.append(_c.is_value() ? _c.value() : base.func_specs[_bi1706]);
            _bi1706 += 1;
        }
    } else if (_mode1705 == 3) {
        var _n1703 = input.count();
        for (var _ in 0.._n1703) {
            _f1702.append(_m_TypeName_read(input));
        }
    } else {
        var _n1703 = input.count();
        if (input.merging) {
            input.error = "func_specs" + " written by place";
        }
        for (var _ in 0.._n1703) {
            var _tag1704 = input.unsigned();
            if (_tag1704 & 1 == 1) {
                if (!input.merging) {
                    _f1702.append(base.func_specs[_tag1704 >> 1]);
                }
            } else {
                var _read = _m_TypeName_read(input);
                if (!input.merging or true) {
                    _f1702.append(_read);
                }
            }
        }
    }
    var _f1714 = Array<TypeAliasDef>();
    var _n1715 = input.count();
    if (input.merging) {
        for (var _b in base.type_aliases) {
            _f1714.append(_b);
        }
    }
    for (var _ in 0.._n1715) {
        var _tag1716 = input.unsigned();
        if (_tag1716 & 1 == 1) {
            if (!input.merging) {
                _f1714.append(base.type_aliases[_tag1716 >> 1]);
            }
        } else {
            var _read = _m_TypeAliasDef_read(input);
            if (!input.merging or false) {
                _f1714.append(_read);
            }
        }
    }
    var _f1730 = Array<Withheld>();
    var _mode1733 = input.unsigned();
    if (_mode1733 == 2) {
        var _changed1719 = HashMap<ulong, Withheld>();
        ulong _bi1734 = 0;
        var _n1731 = input.count();
        for (var _ in 0.._n1731) {
            var _at1735 = input.unsigned();
            while (_f1730.count < _at1735 or (input.merging and _bi1734 < base.withheld.count)) {
                var _c = _changed1719.try_get(_bi1734);
                _f1730.append(_c.is_value() ? _c.value() : base.withheld[_bi1734]);
                _bi1734 += 1;
            }
            _f1730.append(_m_Withheld_read(input));
        }
        while (_bi1734 < base.withheld.count) {
            var _c = _changed1719.try_get(_bi1734);
            _f1730.append(_c.is_value() ? _c.value() : base.withheld[_bi1734]);
            _bi1734 += 1;
        }
    } else if (_mode1733 == 3) {
        var _n1731 = input.count();
        for (var _ in 0.._n1731) {
            _f1730.append(_m_Withheld_read(input));
        }
    } else {
        var _n1731 = input.count();
        if (input.merging) {
            input.error = "withheld" + " written by place";
        }
        for (var _ in 0.._n1731) {
            var _tag1732 = input.unsigned();
            if (_tag1732 & 1 == 1) {
                if (!input.merging) {
                    _f1730.append(base.withheld[_tag1732 >> 1]);
                }
            } else {
                var _read = _m_Withheld_read(input);
                if (!input.merging or true) {
                    _f1730.append(_read);
                }
            }
        }
    }
    var _f1749 = Array<PropertyDef>();
    var _mode1752 = input.unsigned();
    if (_mode1752 == 2) {
        var _changed1738 = HashMap<ulong, PropertyDef>();
        ulong _bi1753 = 0;
        var _n1750 = input.count();
        for (var _ in 0.._n1750) {
            var _at1754 = input.unsigned();
            while (_f1749.count < _at1754 or (input.merging and _bi1753 < base.properties.count)) {
                var _c = _changed1738.try_get(_bi1753);
                _f1749.append(_c.is_value() ? _c.value() : base.properties[_bi1753]);
                _bi1753 += 1;
            }
            _f1749.append(_m_PropertyDef_read(input));
        }
        while (_bi1753 < base.properties.count) {
            var _c = _changed1738.try_get(_bi1753);
            _f1749.append(_c.is_value() ? _c.value() : base.properties[_bi1753]);
            _bi1753 += 1;
        }
    } else if (_mode1752 == 3) {
        var _n1750 = input.count();
        for (var _ in 0.._n1750) {
            _f1749.append(_m_PropertyDef_read(input));
        }
    } else {
        var _n1750 = input.count();
        if (input.merging) {
            input.error = "properties" + " written by place";
        }
        for (var _ in 0.._n1750) {
            var _tag1751 = input.unsigned();
            if (_tag1751 & 1 == 1) {
                if (!input.merging) {
                    _f1749.append(base.properties[_tag1751 >> 1]);
                }
            } else {
                var _read = _m_PropertyDef_read(input);
                if (!input.merging or true) {
                    _f1749.append(_read);
                }
            }
        }
    }
    var _f1768 = Array<TypeUse>();
    var _mode1771 = input.unsigned();
    if (_mode1771 == 2) {
        var _changed1757 = HashMap<ulong, TypeUse>();
        ulong _bi1772 = 0;
        var _n1769 = input.count();
        for (var _ in 0.._n1769) {
            var _at1773 = input.unsigned();
            while (_f1768.count < _at1773 or (input.merging and _bi1772 < base.type_uses.count)) {
                var _c = _changed1757.try_get(_bi1772);
                _f1768.append(_c.is_value() ? _c.value() : base.type_uses[_bi1772]);
                _bi1772 += 1;
            }
            _f1768.append(_m_TypeUse_read(input));
        }
        while (_bi1772 < base.type_uses.count) {
            var _c = _changed1757.try_get(_bi1772);
            _f1768.append(_c.is_value() ? _c.value() : base.type_uses[_bi1772]);
            _bi1772 += 1;
        }
    } else if (_mode1771 == 3) {
        var _n1769 = input.count();
        for (var _ in 0.._n1769) {
            _f1768.append(_m_TypeUse_read(input));
        }
    } else {
        var _n1769 = input.count();
        if (input.merging) {
            input.error = "type_uses" + " written by place";
        }
        for (var _ in 0.._n1769) {
            var _tag1770 = input.unsigned();
            if (_tag1770 & 1 == 1) {
                if (!input.merging) {
                    _f1768.append(base.type_uses[_tag1770 >> 1]);
                }
            } else {
                var _read = _m_TypeUse_read(input);
                if (!input.merging or true) {
                    _f1768.append(_read);
                }
            }
        }
    }
    var _f1787 = Array<UseContext>();
    var _mode1790 = input.unsigned();
    if (_mode1790 == 2) {
        var _changed1776 = HashMap<ulong, UseContext>();
        ulong _bi1791 = 0;
        var _n1788 = input.count();
        for (var _ in 0.._n1788) {
            var _at1792 = input.unsigned();
            while (_f1787.count < _at1792 or (input.merging and _bi1791 < base.use_contexts.count)) {
                var _c = _changed1776.try_get(_bi1791);
                _f1787.append(_c.is_value() ? _c.value() : base.use_contexts[_bi1791]);
                _bi1791 += 1;
            }
            _f1787.append(_m_UseContext_read(input));
        }
        while (_bi1791 < base.use_contexts.count) {
            var _c = _changed1776.try_get(_bi1791);
            _f1787.append(_c.is_value() ? _c.value() : base.use_contexts[_bi1791]);
            _bi1791 += 1;
        }
    } else if (_mode1790 == 3) {
        var _n1788 = input.count();
        for (var _ in 0.._n1788) {
            _f1787.append(_m_UseContext_read(input));
        }
    } else {
        var _n1788 = input.count();
        if (input.merging) {
            input.error = "use_contexts" + " written by place";
        }
        for (var _ in 0.._n1788) {
            var _tag1789 = input.unsigned();
            if (_tag1789 & 1 == 1) {
                if (!input.merging) {
                    _f1787.append(base.use_contexts[_tag1789 >> 1]);
                }
            } else {
                var _read = _m_UseContext_read(input);
                if (!input.merging or true) {
                    _f1787.append(_read);
                }
            }
        }
    }
    var _f1808 = Array<(Loc, ulong, Loc)>();
    var _tag1809 = input.unsigned();
    if (_tag1809 == 1) {
        input.unsigned();
        for (var _i1797 in 0..base.literal_args.count) {
            _f1808.append(base.literal_args[_i1797]);
        }
        var _more1811 = input.count();
        for (var _ in 0.._more1811) {
            var _t1812 = input.loc();
            var _t1813 = input.unsigned();
            var _t1814 = input.loc();
            _f1808.append((_t1812, _t1813, _t1814));
        }
    } else {
        var _v1815 = Array<(Loc, ulong, Loc)>();
        var _n1816 = input.count();
        for (var _ in 0.._n1816) {
            var _t1817 = input.loc();
            var _t1818 = input.unsigned();
            var _t1819 = input.loc();
            _v1815.append((_t1817, _t1818, _t1819));
        }
        _f1808 = _v1815;
    }
    var _f1837 = Array<TypeAliasDef>();
    var _mode1840 = input.unsigned();
    if (_mode1840 == 2) {
        var _changed1826 = HashMap<ulong, TypeAliasDef>();
        ulong _bi1841 = 0;
        var _n1838 = input.count();
        for (var _ in 0.._n1838) {
            var _at1842 = input.unsigned();
            while (_f1837.count < _at1842 or (input.merging and _bi1841 < base.constrained_aliases.count)) {
                var _c = _changed1826.try_get(_bi1841);
                _f1837.append(_c.is_value() ? _c.value() : base.constrained_aliases[_bi1841]);
                _bi1841 += 1;
            }
            _f1837.append(_m_TypeAliasDef_read(input));
        }
        while (_bi1841 < base.constrained_aliases.count) {
            var _c = _changed1826.try_get(_bi1841);
            _f1837.append(_c.is_value() ? _c.value() : base.constrained_aliases[_bi1841]);
            _bi1841 += 1;
        }
    } else if (_mode1840 == 3) {
        var _n1838 = input.count();
        for (var _ in 0.._n1838) {
            _f1837.append(_m_TypeAliasDef_read(input));
        }
    } else {
        var _n1838 = input.count();
        if (input.merging) {
            input.error = "constrained_aliases" + " written by place";
        }
        for (var _ in 0.._n1838) {
            var _tag1839 = input.unsigned();
            if (_tag1839 & 1 == 1) {
                if (!input.merging) {
                    _f1837.append(base.constrained_aliases[_tag1839 >> 1]);
                }
            } else {
                var _read = _m_TypeAliasDef_read(input);
                if (!input.merging or true) {
                    _f1837.append(_read);
                }
            }
        }
    }
    var _f1856 = Array<TraitType>();
    var _mode1859 = input.unsigned();
    if (_mode1859 == 2) {
        var _changed1845 = HashMap<ulong, TraitType>();
        ulong _bi1860 = 0;
        var _n1857 = input.count();
        for (var _ in 0.._n1857) {
            var _at1861 = input.unsigned();
            while (_f1856.count < _at1861 or (input.merging and _bi1860 < base.trait_types.count)) {
                var _c = _changed1845.try_get(_bi1860);
                _f1856.append(_c.is_value() ? _c.value() : base.trait_types[_bi1860]);
                _bi1860 += 1;
            }
            _f1856.append(_m_TraitType_read(input));
        }
        while (_bi1860 < base.trait_types.count) {
            var _c = _changed1845.try_get(_bi1860);
            _f1856.append(_c.is_value() ? _c.value() : base.trait_types[_bi1860]);
            _bi1860 += 1;
        }
    } else if (_mode1859 == 3) {
        var _n1857 = input.count();
        for (var _ in 0.._n1857) {
            _f1856.append(_m_TraitType_read(input));
        }
    } else {
        var _n1857 = input.count();
        if (input.merging) {
            input.error = "trait_types" + " written by place";
        }
        for (var _ in 0.._n1857) {
            var _tag1858 = input.unsigned();
            if (_tag1858 & 1 == 1) {
                if (!input.merging) {
                    _f1856.append(base.trait_types[_tag1858 >> 1]);
                }
            } else {
                var _read = _m_TraitType_read(input);
                if (!input.merging or true) {
                    _f1856.append(_read);
                }
            }
        }
    }
    var _v1867 = Array<Conversion>();
    var _n1868 = input.count();
    for (var _ in 0.._n1868) {
        _v1867.append(_m_Conversion_read(input));
    }
    var _f1869 = _v1867;
    var _f1896 = Map<String, Array<String>>();
    var _tag1897 = input.unsigned();
    if (_tag1897 == 1) {
        for (var (_bk1898, _bv) in base.overload_sets) {
            _f1896[_bk1898] = _bv;
        }
        var _v1899 = Map<String, Array<String>>();
        var _n1900 = input.count();
        for (var _ in 0.._n1900) {
            var _k1901 = input.text();
            var _v1902 = Array<String>();
            var _n1903 = input.count();
            for (var _ in 0.._n1903) {
                _v1902.append(input.text());
            }
            _v1899[_k1901] = _v1902;
        }
        for (var (_bk1898, _av) in _v1899) {
            _f1896[_bk1898] = _av;
        }
    } else {
        var _v1904 = Map<String, Array<String>>();
        var _n1905 = input.count();
        for (var _ in 0.._n1905) {
            var _k1906 = input.text();
            var _v1907 = Array<String>();
            var _n1908 = input.count();
            for (var _ in 0.._n1908) {
                _v1907.append(input.text());
            }
            _v1904[_k1906] = _v1907;
        }
        _f1896 = _v1904;
    }
    var _f1943 = Map<String, Array<Array<String>>>();
    var _tag1944 = input.unsigned();
    if (_tag1944 == 1) {
        for (var (_bk1945, _bv) in base.overload_unions) {
            _f1943[_bk1945] = _bv;
        }
        var _v1946 = Map<String, Array<Array<String>>>();
        var _n1947 = input.count();
        for (var _ in 0.._n1947) {
            var _k1948 = input.text();
            var _v1949 = Array<Array<String>>();
            var _n1950 = input.count();
            for (var _ in 0.._n1950) {
                var _v1951 = Array<String>();
                var _n1952 = input.count();
                for (var _ in 0.._n1952) {
                    _v1951.append(input.text());
                }
                _v1949.append(_v1951);
            }
            _v1946[_k1948] = _v1949;
        }
        for (var (_bk1945, _av) in _v1946) {
            _f1943[_bk1945] = _av;
        }
    } else {
        var _v1953 = Map<String, Array<Array<String>>>();
        var _n1954 = input.count();
        for (var _ in 0.._n1954) {
            var _k1955 = input.text();
            var _v1956 = Array<Array<String>>();
            var _n1957 = input.count();
            for (var _ in 0.._n1957) {
                var _v1958 = Array<String>();
                var _n1959 = input.count();
                for (var _ in 0.._n1959) {
                    _v1958.append(input.text());
                }
                _v1956.append(_v1958);
            }
            _v1953[_k1955] = _v1956;
        }
        _f1943 = _v1953;
    }
    var _f2030 = Map<String, Map<String, Array<String>>>();
    var _tag2031 = input.unsigned();
    if (_tag2031 == 1) {
        for (var (_bk2032, _bv) in base.method_overload_sets) {
            _f2030[_bk2032] = _bv;
        }
        var _v2033 = Map<String, Map<String, Array<String>>>();
        var _n2034 = input.count();
        for (var _ in 0.._n2034) {
            var _k2035 = input.text();
            var _v2036 = Map<String, Array<String>>();
            var _n2037 = input.count();
            for (var _ in 0.._n2037) {
                var _k2038 = input.text();
                var _v2039 = Array<String>();
                var _n2040 = input.count();
                for (var _ in 0.._n2040) {
                    _v2039.append(input.text());
                }
                _v2036[_k2038] = _v2039;
            }
            _v2033[_k2035] = _v2036;
        }
        for (var (_bk2032, _av) in _v2033) {
            _f2030[_bk2032] = _av;
        }
    } else {
        var _v2041 = Map<String, Map<String, Array<String>>>();
        var _n2042 = input.count();
        for (var _ in 0.._n2042) {
            var _k2043 = input.text();
            var _v2044 = Map<String, Array<String>>();
            var _n2045 = input.count();
            for (var _ in 0.._n2045) {
                var _k2046 = input.text();
                var _v2047 = Array<String>();
                var _n2048 = input.count();
                for (var _ in 0.._n2048) {
                    _v2047.append(input.text());
                }
                _v2044[_k2046] = _v2047;
            }
            _v2041[_k2043] = _v2044;
        }
        _f2030 = _v2041;
    }
    var _f2056 = _m_ExtensionScopes_read(input);
    var _f2076 = HashSet<Loc>();
    var _tag2077 = input.unsigned();
    if (_tag2077 == 1) {
        for (var _bk2078 in base.private_functions) {
            _f2076.insert(_bk2078);
        }
        var _v2079 = HashSet<Loc>();
        var _n2080 = input.count();
        for (var _ in 0.._n2080) {
            _v2079.insert(input.loc());
        }
        for (var _bk2078 in _v2079) {
            _f2076.insert(_bk2078);
        }
    } else {
        var _v2081 = HashSet<Loc>();
        var _n2082 = input.count();
        for (var _ in 0.._n2082) {
            _v2081.insert(input.loc());
        }
        _f2076 = _v2081;
    }
    var _f2102 = HashSet<Loc>();
    var _tag2103 = input.unsigned();
    if (_tag2103 == 1) {
        for (var _bk2104 in base.file_private_functions) {
            _f2102.insert(_bk2104);
        }
        var _v2105 = HashSet<Loc>();
        var _n2106 = input.count();
        for (var _ in 0.._n2106) {
            _v2105.insert(input.loc());
        }
        for (var _bk2104 in _v2105) {
            _f2102.insert(_bk2104);
        }
    } else {
        var _v2107 = HashSet<Loc>();
        var _n2108 = input.count();
        for (var _ in 0.._n2108) {
            _v2107.insert(input.loc());
        }
        _f2102 = _v2107;
    }
    var _f2120 = Array<(Loc, String)>();
    var _tag2121 = input.unsigned();
    if (_tag2121 == 1) {
        input.unsigned();
        for (var _i2112 in 0..base.call_targets.count) {
            _f2120.append(base.call_targets[_i2112]);
        }
        var _more2123 = input.count();
        for (var _ in 0.._more2123) {
            var _t2124 = input.loc();
            var _t2125 = input.text();
            _f2120.append((_t2124, _t2125));
        }
    } else {
        var _v2126 = Array<(Loc, String)>();
        var _n2127 = input.count();
        for (var _ in 0.._n2127) {
            var _t2128 = input.loc();
            var _t2129 = input.text();
            _v2126.append((_t2128, _t2129));
        }
        _f2120 = _v2126;
    }
    var _f2146 = Array<(Loc, String)>();
    var _tag2147 = input.unsigned();
    if (_tag2147 == 1) {
        var _v2148 = Array<(Loc, String)>();
        var _n2149 = input.count();
        for (var _ in 0.._n2149) {
            var _t2150 = input.loc();
            var _t2151 = input.text();
            _v2148.append((_t2150, _t2151));
        }
        _f2146 = merge_by_place(base.argument_names, _v2148);
    } else {
        var _v2152 = Array<(Loc, String)>();
        var _n2153 = input.count();
        for (var _ in 0.._n2153) {
            var _t2154 = input.loc();
            var _t2155 = input.text();
            _v2152.append((_t2154, _t2155));
        }
        _f2146 = _v2152;
    }
    var _f2165 = Array<String>();
    var _tag2166 = input.unsigned();
    if (_tag2166 == 1) {
        input.unsigned();
        for (var _i2161 in 0..base.namespaces.count) {
            _f2165.append(base.namespaces[_i2161]);
        }
        var _more2168 = input.count();
        for (var _ in 0.._more2168) {
            _f2165.append(input.text());
        }
    } else {
        var _v2169 = Array<String>();
        var _n2170 = input.count();
        for (var _ in 0.._n2170) {
            _v2169.append(input.text());
        }
        _f2165 = _v2169;
    }
    var _f2178 = Array<bool>();
    var _tag2179 = input.unsigned();
    if (_tag2179 == 1) {
        input.unsigned();
        for (var _i2176 in 0..base.cached_files.count) {
            _f2178.append(base.cached_files[_i2176]);
        }
        var _more2181 = input.count();
        for (var _ in 0.._more2181) {
            _f2178.append(input.flag());
        }
    } else {
        var _v2182 = Array<bool>();
        var _n2183 = input.count();
        for (var _ in 0.._n2183) {
            _v2182.append(input.flag());
        }
        _f2178 = _v2182;
    }
    var _f2201 = HashMap<Loc, String>();
    var _tag2202 = input.unsigned();
    if (_tag2202 == 1) {
        for (var (_bk2203, _bv) in base.recorded_summaries) {
            _f2201[_bk2203] = _bv;
        }
        var _v2204 = HashMap<Loc, String>();
        var _n2205 = input.count();
        for (var _ in 0.._n2205) {
            var _k2206 = input.loc();
            _v2204[_k2206] = input.text();
        }
        for (var (_bk2203, _av) in _v2204) {
            _f2201[_bk2203] = _av;
        }
    } else {
        var _v2207 = HashMap<Loc, String>();
        var _n2208 = input.count();
        for (var _ in 0.._n2208) {
            var _k2209 = input.loc();
            _v2207[_k2209] = input.text();
        }
        _f2201 = _v2207;
    }
    var _f2225 = HashSet<Loc>();
    var _tag2226 = input.unsigned();
    if (_tag2226 == 1) {
        for (var _bk2227 in base.stripped) {
            _f2225.insert(_bk2227);
        }
        var _v2228 = HashSet<Loc>();
        var _n2229 = input.count();
        for (var _ in 0.._n2229) {
            _v2228.insert(input.loc());
        }
        for (var _bk2227 in _v2228) {
            _f2225.insert(_bk2227);
        }
    } else {
        var _v2230 = HashSet<Loc>();
        var _n2231 = input.count();
        for (var _ in 0.._n2231) {
            _v2230.insert(input.loc());
        }
        _f2225 = _v2230;
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
    var _f2262 = Array<FunctionDef>();
    var _mode2265 = input.unsigned();
    if (_mode2265 == 2) {
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
        ulong _bi2266 = 0;
        var _n2263 = input.count();
        for (var _ in 0.._n2263) {
            var _at2267 = input.unsigned();
            while (_f2262.count < _at2267 or (input.merging and _bi2266 < base.templates.functions.count)) {
                var _c = _changed2251.try_get(_bi2266);
                _f2262.append(_c.is_value() ? _c.value() : base.templates.functions[_bi2266]);
                _bi2266 += 1;
            }
            _f2262.append(_m_FunctionDef_read(input));
        }
        while (_bi2266 < base.templates.functions.count) {
            var _c = _changed2251.try_get(_bi2266);
            _f2262.append(_c.is_value() ? _c.value() : base.templates.functions[_bi2266]);
            _bi2266 += 1;
        }
    } else if (_mode2265 == 3) {
        var _n2263 = input.count();
        for (var _ in 0.._n2263) {
            _f2262.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2263 = input.count();
        if (input.merging) {
            input.error = "tf" + " written by place";
        }
        for (var _ in 0.._n2263) {
            var _tag2264 = input.unsigned();
            if (_tag2264 & 1 == 1) {
                if (!input.merging) {
                    _f2262.append(base.templates.functions[_tag2264 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2262.append(_read);
                }
            }
        }
    }
    var _f2269 = Templates(_frozen, _f2242, _f2262);
    var _f2270 = DeltaBase.read_checked(input, base.checked);
    var _f2290 = HashMap<String, SpecRequest>();
    var _tag2291 = input.unsigned();
    if (_tag2291 == 1) {
        for (var (_bk2292, _bv) in base.spec_requests) {
            _f2290[_bk2292] = _bv;
        }
        var _v2293 = HashMap<String, SpecRequest>();
        var _n2294 = input.count();
        for (var _ in 0.._n2294) {
            var _k2295 = input.text();
            _v2293[_k2295] = _m_SpecRequest_read(input);
        }
        for (var (_bk2292, _av) in _v2293) {
            _f2290[_bk2292] = _av;
        }
    } else {
        var _v2296 = HashMap<String, SpecRequest>();
        var _n2297 = input.count();
        for (var _ in 0.._n2297) {
            var _k2298 = input.text();
            _v2296[_k2298] = _m_SpecRequest_read(input);
        }
        _f2290 = _v2296;
    }
    var _f2299 = input.flag();
    var _f2311 = Array<(Loc, String)>();
    var _tag2312 = input.unsigned();
    if (_tag2312 == 1) {
        input.unsigned();
        for (var _i2303 in 0..base.summaries_to_record.count) {
            _f2311.append(base.summaries_to_record[_i2303]);
        }
        var _more2314 = input.count();
        for (var _ in 0.._more2314) {
            var _t2315 = input.loc();
            var _t2316 = input.text();
            _f2311.append((_t2315, _t2316));
        }
    } else {
        var _v2317 = Array<(Loc, String)>();
        var _n2318 = input.count();
        for (var _ in 0.._n2318) {
            var _t2319 = input.loc();
            var _t2320 = input.text();
            _v2317.append((_t2319, _t2320));
        }
        _f2311 = _v2317;
    }
    var _f2351 = HashMap<String, Array<bool>>();
    var _tag2352 = input.unsigned();
    if (_tag2352 == 1) {
        for (var (_bk2353, _bv) in base.caller_copies) {
            _f2351[_bk2353] = _bv;
        }
        var _v2354 = HashMap<String, Array<bool>>();
        var _n2355 = input.count();
        for (var _ in 0.._n2355) {
            var _k2356 = input.text();
            var _v2357 = Array<bool>();
            var _n2358 = input.count();
            for (var _ in 0.._n2358) {
                _v2357.append(input.flag());
            }
            _v2354[_k2356] = _v2357;
        }
        for (var (_bk2353, _av) in _v2354) {
            _f2351[_bk2353] = _av;
        }
    } else {
        var _v2359 = HashMap<String, Array<bool>>();
        var _n2360 = input.count();
        for (var _ in 0.._n2360) {
            var _k2361 = input.text();
            var _v2362 = Array<bool>();
            var _n2363 = input.count();
            for (var _ in 0.._n2363) {
                _v2362.append(input.flag());
            }
            _v2359[_k2361] = _v2362;
        }
        _f2351 = _v2359;
    }
    var _f2365 = input.flag();
    return Module(
        _f1497,
        _f1530,
        _f1550,
        _f1569,
        _f1588,
        _f1607,
        _f1626,
        _f1645,
        _f1664,
        _f1683,
        _f1702,
        _f1714,
        _f1730,
        _f1749,
        _f1768,
        _f1787,
        _f1808,
        _f1837,
        _f1856,
        _f1869,
        _f1896,
        _f1943,
        _f2030,
        _f2056,
        _f2076,
        _f2102,
        _f2120,
        _f2146,
        _f2165,
        _f2178,
        _f2201,
        _f2225,
        _f2269,
        _f2270,
        _f2290,
        _f2299,
        _f2311,
        _f2351,
        _f2365
    );
}

_m_Module_index(value: Module, base: DeltaBase) {
    ulong _j1503 = 0;
    for (var _item1485 in value.imports) {
        var scratch = base.scratch();
        _a_Import_write(scratch, _item1485);
        base.add("imports", scratch, _j1503);
        _j1503 += 1;
    }
    if (base.verifying) {
        ulong _j1537 = 0;
        for (var _item1504 in value.structs) {
            var scratch = base.scratch();
            _m_StructDef_write(scratch, _item1504);
            base.add("s", scratch, _j1537);
            base.name("s", _item1504.name, _j1537);
            _patch_s_index(_item1504, base, _j1537);
            _j1537 += 1;
        }
    }
    base.ref_structs = value.structs.clone();
    base.ref_struct_parts = Array<StructDef>();
    for (var _item1504 in value.structs) {
        base.ref_struct_parts.append(_m_StructDef_shallow(_item1504));
    }
    ulong _j1556 = 0;
    for (var _item1538 in value.traits) {
        var scratch = base.scratch();
        _m_TraitDef_write(scratch, _item1538);
        base.add("traits", scratch, _j1556);
        _j1556 += 1;
    }
    ulong _j1575 = 0;
    for (var _item1557 in value.extensions) {
        var scratch = base.scratch();
        _m_ExtensionDef_write(scratch, _item1557);
        base.add("extensions", scratch, _j1575);
        _j1575 += 1;
    }
    if (base.verifying) {
        ulong _j1594 = 0;
        for (var _item1576 in value.functions) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item1576);
            base.add("functions", scratch, _j1594);
            base.name("functions", _item1576.name, _j1594);
            _j1594 += 1;
        }
    }
    base.ref_functions = value.functions.clone();
    ulong _j1613 = 0;
    for (var _item1595 in value.externs) {
        var scratch = base.scratch();
        _m_ExternDef_write(scratch, _item1595);
        base.add("externs", scratch, _j1613);
        _j1613 += 1;
    }
    ulong _j1632 = 0;
    for (var _item1614 in value.globals) {
        var scratch = base.scratch();
        _m_VariableDef_write(scratch, _item1614);
        base.add("globals", scratch, _j1632);
        _j1632 += 1;
    }
    ulong _j1651 = 0;
    for (var _item1633 in value.static_blocks) {
        var scratch = base.scratch();
        _m_ModuleStaticBlock_write(scratch, _item1633);
        base.add("static_blocks", scratch, _j1651);
        _j1651 += 1;
    }
    ulong _j1670 = 0;
    for (var _item1652 in value.enums) {
        var scratch = base.scratch();
        _m_EnumDef_write(scratch, _item1652);
        base.add("enums", scratch, _j1670);
        _j1670 += 1;
    }
    ulong _j1689 = 0;
    for (var _item1671 in value.struct_specs) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item1671);
        base.add("struct_specs", scratch, _j1689);
        _j1689 += 1;
    }
    ulong _j1708 = 0;
    for (var _item1690 in value.func_specs) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item1690);
        base.add("func_specs", scratch, _j1708);
        _j1708 += 1;
    }
    ulong _j1717 = 0;
    for (var _item1709 in value.type_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1709);
        base.add("type_aliases", scratch, _j1717);
        _j1717 += 1;
    }
    ulong _j1736 = 0;
    for (var _item1718 in value.withheld) {
        var scratch = base.scratch();
        _m_Withheld_write(scratch, _item1718);
        base.add("withheld", scratch, _j1736);
        _j1736 += 1;
    }
    ulong _j1755 = 0;
    for (var _item1737 in value.properties) {
        var scratch = base.scratch();
        _m_PropertyDef_write(scratch, _item1737);
        base.add("properties", scratch, _j1755);
        _j1755 += 1;
    }
    ulong _j1774 = 0;
    for (var _item1756 in value.type_uses) {
        var scratch = base.scratch();
        _m_TypeUse_write(scratch, _item1756);
        base.add("type_uses", scratch, _j1774);
        _j1774 += 1;
    }
    ulong _j1793 = 0;
    for (var _item1775 in value.use_contexts) {
        var scratch = base.scratch();
        _m_UseContext_write(scratch, _item1775);
        base.add("use_contexts", scratch, _j1793);
        _j1793 += 1;
    }
    var _xscratch1820 = base.scratch();
    for (var _xitem1821 in value.literal_args) {
        var (_t1822, _t1823, _t1824) = _xitem1821;
        _xscratch1820.loc(_t1822);
        _xscratch1820.unsigned(_t1823);
        _xscratch1820.loc(_t1824);
    }
    base.keep_list("literal_args", value.literal_args.count, _xscratch1820);
    ulong _j1843 = 0;
    for (var _item1825 in value.constrained_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1825);
        base.add("constrained_aliases", scratch, _j1843);
        _j1843 += 1;
    }
    ulong _j1862 = 0;
    for (var _item1844 in value.trait_types) {
        var scratch = base.scratch();
        _m_TraitType_write(scratch, _item1844);
        base.add("trait_types", scratch, _j1862);
        _j1862 += 1;
    }
    ulong _cj1866 = 0;
    for (var _conv1864 in value.conversions) {
        var _own1865 = RecordOut();
        _own1865.blank_locs = true;
        _m_Conversion_write(_own1865, _conv1864);
        base.add_hashed("conversions", interface_text(_own1865), _cj1866);
        _cj1866 += 1;
    }
    for (var (_key1870, _) in value.overload_sets) {
        var _kscratch1871 = base.scratch();
        _kscratch1871.text(_key1870);
        var _vscratch1872 = base.scratch();
        _vscratch1872.unsigned(value.overload_sets[_key1870].count);
        for (var _item1909 in value.overload_sets[_key1870]) {
            _vscratch1872.text(_item1909);
        }
        base.keep_entry("overload_sets", _kscratch1871, _vscratch1872);
    }
    for (var (_key1910, _) in value.overload_unions) {
        var _kscratch1911 = base.scratch();
        _kscratch1911.text(_key1910);
        var _vscratch1912 = base.scratch();
        _vscratch1912.unsigned(value.overload_unions[_key1910].count);
        for (var _item1960 in value.overload_unions[_key1910]) {
            _vscratch1912.unsigned(_item1960.count);
            for (var _item1961 in _item1960) {
                _vscratch1912.text(_item1961);
            }
        }
        base.keep_entry("overload_unions", _kscratch1911, _vscratch1912);
    }
    for (var (_key1962, _) in value.method_overload_sets) {
        var _kscratch1963 = base.scratch();
        _kscratch1963.text(_key1962);
        var _vscratch1964 = base.scratch();
        var _keys2050 = Array<(u8[], u8[], String)>();
        for (var (_key2049, _) in value.method_overload_sets[_key1962]) {
            var _scratch2051 = _vscratch1964.scratch();
            _scratch2051.text(_key2049);
            var _vscratch2053 = _vscratch1964.scratch();
            _vscratch2053.unsigned(value.method_overload_sets[_key1962][_key2049].count);
            for (var _item2054 in value.method_overload_sets[_key1962][_key2049]) {
                _vscratch2053.text(_item2054);
            }
            _keys2050.append((_scratch2051.finish(), _vscratch2053.finish(), _key2049));
        }
        _keys2050.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        _vscratch1964.unsigned(_keys2050.count);
        for (var (_bytes2052, _, _key2049) in _keys2050) {
            _vscratch1964.text(_key2049);
            _vscratch1964.unsigned(value.method_overload_sets[_key1962][_key2049].count);
            for (var _item2055 in value.method_overload_sets[_key1962][_key2049]) {
                _vscratch1964.text(_item2055);
            }
        }
        base.keep_entry("method_overload_sets", _kscratch1963, _vscratch1964);
    }
    for (var _key2057 in value.private_functions) {
        var _kscratch2058 = base.scratch();
        _kscratch2058.loc(_key2057);
        var _vscratch2059 = base.scratch();
        base.keep_entry("private_functions", _kscratch2058, _vscratch2059);
    }
    for (var _key2083 in value.file_private_functions) {
        var _kscratch2084 = base.scratch();
        _kscratch2084.loc(_key2083);
        var _vscratch2085 = base.scratch();
        base.keep_entry("file_private_functions", _kscratch2084, _vscratch2085);
    }
    var _xscratch2130 = base.scratch();
    for (var _xitem2131 in value.call_targets) {
        var (_t2132, _t2133) = _xitem2131;
        _xscratch2130.loc(_t2132);
        _xscratch2130.text(_t2133);
    }
    base.keep_list("call_targets", value.call_targets.count, _xscratch2130);
    for (var _item2134 in value.argument_names) {
        var _escratch2135 = base.scratch();
        var (_t2156, _t2157) = _item2134;
        _escratch2135.loc(_t2156);
        _escratch2135.text(_t2157);
        base.keep_entry("argument_names", _escratch2135, base.scratch());
    }
    var _xscratch2171 = base.scratch();
    for (var _xitem2172 in value.namespaces) {
        _xscratch2171.text(_xitem2172);
    }
    base.keep_list("namespaces", value.namespaces.count, _xscratch2171);
    var _xscratch2184 = base.scratch();
    for (var _xitem2185 in value.cached_files) {
        _xscratch2184.flag(_xitem2185);
    }
    base.keep_list("cached_files", value.cached_files.count, _xscratch2184);
    for (var (_key2186, _) in value.recorded_summaries) {
        var _kscratch2187 = base.scratch();
        _kscratch2187.loc(_key2186);
        var _vscratch2188 = base.scratch();
        _vscratch2188.text(value.recorded_summaries[_key2186]);
        base.keep_entry("recorded_summaries", _kscratch2187, _vscratch2188);
    }
    for (var _key2210 in value.stripped) {
        var _kscratch2211 = base.scratch();
        _kscratch2211.loc(_key2210);
        var _vscratch2212 = base.scratch();
        base.keep_entry("stripped", _kscratch2211, _vscratch2212);
    }
    if (base.verifying) {
        ulong _j2249 = 0;
        for (var _item2232 in value.templates.structs) {
            var scratch = base.scratch();
            _m_StructDef_write(scratch, _item2232);
            base.add("t", scratch, _j2249);
            base.name("t", _item2232.name, _j2249);
            _patch_t_index(_item2232, base, _j2249);
            _j2249 += 1;
        }
    }
    base.ref_templates = value.templates.structs.clone();
    base.ref_template_parts = Array<StructDef>();
    for (var _item2232 in value.templates.structs) {
        base.ref_template_parts.append(_m_StructDef_shallow(_item2232));
    }
    if (base.verifying) {
        ulong _j2268 = 0;
        for (var _item2250 in value.templates.functions) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2250);
            base.add("tf", scratch, _j2268);
            base.name("tf", _item2250.name, _j2268);
            _j2268 += 1;
        }
    }
    base.ref_template_functions = value.templates.functions.clone();
    base.keep_checked(value.checked);
    for (var (_key2271, _) in value.spec_requests) {
        var _kscratch2272 = base.scratch();
        _kscratch2272.text(_key2271);
        var _vscratch2273 = base.scratch();
        _m_SpecRequest_write(_vscratch2273, value.spec_requests[_key2271]);
        base.keep_entry("spec_requests", _kscratch2272, _vscratch2273);
    }
    var _xscratch2321 = base.scratch();
    for (var _xitem2322 in value.summaries_to_record) {
        var (_t2323, _t2324) = _xitem2322;
        _xscratch2321.loc(_t2323);
        _xscratch2321.text(_t2324);
    }
    base.keep_list("summaries_to_record", value.summaries_to_record.count, _xscratch2321);
    for (var (_key2325, _) in value.caller_copies) {
        var _kscratch2326 = base.scratch();
        _kscratch2326.text(_key2325);
        var _vscratch2327 = base.scratch();
        _vscratch2327.unsigned(value.caller_copies[_key2325].count);
        for (var _item2364 in value.caller_copies[_key2325]) {
            _vscratch2327.flag(_item2364);
        }
        base.keep_entry("caller_copies", _kscratch2326, _vscratch2327);
    }
}

_m_Module_index_resumed(value: Module, base: DeltaBase) {
    ulong _j1717 = 0;
    for (var _item1709 in value.type_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1709);
        base.add("type_aliases", scratch, _j1717);
        _j1717 += 1;
    }
    for (var (_key2186, _) in value.recorded_summaries) {
        var _kscratch2187 = base.scratch();
        _kscratch2187.loc(_key2186);
        var _vscratch2188 = base.scratch();
        _vscratch2188.text(value.recorded_summaries[_key2186]);
        base.keep_entry("recorded_summaries", _kscratch2187, _vscratch2188);
    }
    var _xscratch2321 = base.scratch();
    for (var _xitem2322 in value.summaries_to_record) {
        var (_t2323, _t2324) = _xitem2322;
        _xscratch2321.loc(_t2323);
        _xscratch2321.text(_t2324);
    }
    base.keep_list("summaries_to_record", value.summaries_to_record.count, _xscratch2321);
}

_patch_s_write(out: RecordOut, value: StructDef, base: DeltaBase, slot: ulong) {
    out.text(value.name);
    _m_TypeName_write(out, value.ty);
    var _seq2373 = base.ref_struct_parts[slot].generic_params;
    ulong _bj2374 = 0;
    var _news2375 = Array<ulong>();
    for (var _i2376 in 0..value.generic_params.count) {
        if (_bj2374 < _seq2373.count and value.generic_params[_i2376] === _seq2373[_bj2374]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_GenericParam_write(scratch, value.generic_params[_i2376]);
                base.verify_same($"s.{slot}.generic_params", _bj2374, scratch);
            }
            _bj2374 += 1;
        } else if (_bj2374 < _seq2373.count
            and _same_m_GenericParam(value.generic_params[_i2376], _seq2373[_bj2374], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_GenericParam_write(scratch, value.generic_params[_i2376]);
                base.verify_same($"s.{slot}.generic_params", _bj2374, scratch);
            }
            _bj2374 += 1;
        } else {
            _news2375.append(_i2376);
        }
    }
    if (_bj2374 == _seq2373.count) {
        out.unsigned(2);
        out.unsigned(_news2375.count);
        for (var _i2376 in _news2375) {
            out.unsigned(_i2376);
            _m_GenericParam_write(out, value.generic_params[_i2376]);
        }
        base.count("s.*.generic_params" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.generic_params" + " whole", 0);
        out.unsigned(value.generic_params.count);
        for (var _i2376 in 0..value.generic_params.count) {
            _m_GenericParam_write(out, value.generic_params[_i2376]);
        }
    }
    var _seq2389 = base.ref_struct_parts[slot].field_members;
    ulong _bj2390 = 0;
    var _news2391 = Array<ulong>();
    for (var _i2392 in 0..value.field_members.count) {
        if (_bj2390 < _seq2389.count and value.field_members[_i2392] === _seq2389[_bj2390]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_VariableDef_write(scratch, value.field_members[_i2392]);
                base.verify_same($"s.{slot}.field_members", _bj2390, scratch);
            }
            _bj2390 += 1;
        } else if (_bj2390 < _seq2389.count
            and _same_m_VariableDef(value.field_members[_i2392], _seq2389[_bj2390], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_VariableDef_write(scratch, value.field_members[_i2392]);
                base.verify_same($"s.{slot}.field_members", _bj2390, scratch);
            }
            _bj2390 += 1;
        } else {
            _news2391.append(_i2392);
        }
    }
    if (_bj2390 == _seq2389.count) {
        out.unsigned(2);
        out.unsigned(_news2391.count);
        for (var _i2392 in _news2391) {
            out.unsigned(_i2392);
            _m_VariableDef_write(out, value.field_members[_i2392]);
        }
        base.count("s.*.field_members" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.field_members" + " whole", 0);
        out.unsigned(value.field_members.count);
        for (var _i2392 in 0..value.field_members.count) {
            _m_VariableDef_write(out, value.field_members[_i2392]);
        }
    }
    var _seq2405 = base.ref_struct_parts[slot].method_members;
    ulong _bj2406 = 0;
    var _news2407 = Array<ulong>();
    for (var _i2408 in 0..value.method_members.count) {
        if (_bj2406 < _seq2405.count and value.method_members[_i2408] === _seq2405[_bj2406]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.method_members[_i2408]);
                base.verify_same($"s.{slot}.method_members", _bj2406, scratch);
            }
            _bj2406 += 1;
        } else if (_bj2406 < _seq2405.count
            and _same_m_FunctionDef(value.method_members[_i2408], _seq2405[_bj2406], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.method_members[_i2408]);
                base.verify_same($"s.{slot}.method_members", _bj2406, scratch);
            }
            _bj2406 += 1;
        } else {
            _news2407.append(_i2408);
        }
    }
    if (_bj2406 == _seq2405.count) {
        out.unsigned(2);
        out.unsigned(_news2407.count);
        for (var _i2408 in _news2407) {
            out.unsigned(_i2408);
            _m_FunctionDef_write(out, value.method_members[_i2408]);
        }
        base.count("s.*.method_members" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.method_members" + " whole", 0);
        out.unsigned(value.method_members.count);
        for (var _i2408 in 0..value.method_members.count) {
            _m_FunctionDef_write(out, value.method_members[_i2408]);
        }
    }
    var _seq2421 = base.ref_struct_parts[slot].generic_methods;
    ulong _bj2422 = 0;
    var _news2423 = Array<ulong>();
    for (var _i2424 in 0..value.generic_methods.count) {
        if (_bj2422 < _seq2421.count and value.generic_methods[_i2424] === _seq2421[_bj2422]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.generic_methods[_i2424]);
                base.verify_same($"s.{slot}.generic_methods", _bj2422, scratch);
            }
            _bj2422 += 1;
        } else if (_bj2422 < _seq2421.count
            and _same_m_FunctionDef(value.generic_methods[_i2424], _seq2421[_bj2422], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.generic_methods[_i2424]);
                base.verify_same($"s.{slot}.generic_methods", _bj2422, scratch);
            }
            _bj2422 += 1;
        } else {
            _news2423.append(_i2424);
        }
    }
    if (_bj2422 == _seq2421.count) {
        out.unsigned(2);
        out.unsigned(_news2423.count);
        for (var _i2424 in _news2423) {
            out.unsigned(_i2424);
            _m_FunctionDef_write(out, value.generic_methods[_i2424]);
        }
        base.count("s.*.generic_methods" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.generic_methods" + " whole", 0);
        out.unsigned(value.generic_methods.count);
        for (var _i2424 in 0..value.generic_methods.count) {
            _m_FunctionDef_write(out, value.generic_methods[_i2424]);
        }
    }
    var _seq2437 = base.ref_struct_parts[slot].constructors;
    ulong _bj2438 = 0;
    var _news2439 = Array<ulong>();
    for (var _i2440 in 0..value.constructors.count) {
        if (_bj2438 < _seq2437.count and value.constructors[_i2440] === _seq2437[_bj2438]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.constructors[_i2440]);
                base.verify_same($"s.{slot}.constructors", _bj2438, scratch);
            }
            _bj2438 += 1;
        } else if (_bj2438 < _seq2437.count
            and _same_m_FunctionDef(value.constructors[_i2440], _seq2437[_bj2438], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.constructors[_i2440]);
                base.verify_same($"s.{slot}.constructors", _bj2438, scratch);
            }
            _bj2438 += 1;
        } else {
            _news2439.append(_i2440);
        }
    }
    if (_bj2438 == _seq2437.count) {
        out.unsigned(2);
        out.unsigned(_news2439.count);
        for (var _i2440 in _news2439) {
            out.unsigned(_i2440);
            _m_FunctionDef_write(out, value.constructors[_i2440]);
        }
        base.count("s.*.constructors" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.constructors" + " whole", 0);
        out.unsigned(value.constructors.count);
        for (var _i2440 in 0..value.constructors.count) {
            _m_FunctionDef_write(out, value.constructors[_i2440]);
        }
    }
    _m_FunctionDef_write(out, value.destructor);
    _m_FunctionDef_write(out, value.acquire);
    _m_FunctionDef_write(out, value.release);
    var _seq2456 = base.ref_struct_parts[slot].traits;
    ulong _bj2457 = 0;
    var _news2458 = Array<ulong>();
    for (var _i2459 in 0..value.traits.count) {
        if (_bj2457 < _seq2456.count and value.traits[_i2459] === _seq2456[_bj2457]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_TypeName_write(scratch, value.traits[_i2459]);
                base.verify_same($"s.{slot}.traits", _bj2457, scratch);
            }
            _bj2457 += 1;
        } else if (_bj2457 < _seq2456.count and _same_m_TypeName(value.traits[_i2459], _seq2456[_bj2457], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_TypeName_write(scratch, value.traits[_i2459]);
                base.verify_same($"s.{slot}.traits", _bj2457, scratch);
            }
            _bj2457 += 1;
        } else {
            _news2458.append(_i2459);
        }
    }
    if (_bj2457 == _seq2456.count) {
        out.unsigned(2);
        out.unsigned(_news2458.count);
        for (var _i2459 in _news2458) {
            out.unsigned(_i2459);
            _m_TypeName_write(out, value.traits[_i2459]);
        }
        base.count("s.*.traits" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.traits" + " whole", 0);
        out.unsigned(value.traits.count);
        for (var _i2459 in 0..value.traits.count) {
            _m_TypeName_write(out, value.traits[_i2459]);
        }
    }
    var _seq2472 = base.ref_struct_parts[slot].attributes;
    ulong _bj2473 = 0;
    var _news2474 = Array<ulong>();
    for (var _i2475 in 0..value.attributes.count) {
        if (_bj2473 < _seq2472.count and value.attributes[_i2475] === _seq2472[_bj2473]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _a_Attribute_write(scratch, value.attributes[_i2475]);
                base.verify_same($"s.{slot}.attributes", _bj2473, scratch);
            }
            _bj2473 += 1;
        } else if (_bj2473 < _seq2472.count and _same_a_Attribute(value.attributes[_i2475], _seq2472[_bj2473], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _a_Attribute_write(scratch, value.attributes[_i2475]);
                base.verify_same($"s.{slot}.attributes", _bj2473, scratch);
            }
            _bj2473 += 1;
        } else {
            _news2474.append(_i2475);
        }
    }
    if (_bj2473 == _seq2472.count) {
        out.unsigned(2);
        out.unsigned(_news2474.count);
        for (var _i2475 in _news2474) {
            out.unsigned(_i2475);
            _a_Attribute_write(out, value.attributes[_i2475]);
        }
        base.count("s.*.attributes" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.attributes" + " whole", 0);
        out.unsigned(value.attributes.count);
        for (var _i2475 in 0..value.attributes.count) {
            _a_Attribute_write(out, value.attributes[_i2475]);
        }
    }
    out.loc(value.loc);
    if (value.enum_cases.is_value()) {
        out.unsigned(1);
        out.unsigned(value.enum_cases.value().count);
        for (var _item2484 in value.enum_cases.value()) {
            _m_EnumCaseDef_write(out, _item2484);
        }
    } else {
        out.unsigned(0);
    }
}

_patch_s_read(input: RecordIn, was: StructDef): StructDef {
    var _f2366 = input.text();
    var _f2367 = _m_TypeName_read(input);
    var _f2377 = Array<GenericParam>();
    var _mode2380 = input.unsigned();
    if (_mode2380 == 2) {
        var _changed2369 = HashMap<ulong, GenericParam>();
        ulong _bi2381 = 0;
        var _n2378 = input.count();
        for (var _ in 0.._n2378) {
            var _at2382 = input.unsigned();
            while (_f2377.count < _at2382 or (input.merging and _bi2381 < was.generic_params.count)) {
                var _c = _changed2369.try_get(_bi2381);
                _f2377.append(_c.is_value() ? _c.value() : was.generic_params[_bi2381]);
                _bi2381 += 1;
            }
            _f2377.append(_m_GenericParam_read(input));
        }
        while (_bi2381 < was.generic_params.count) {
            var _c = _changed2369.try_get(_bi2381);
            _f2377.append(_c.is_value() ? _c.value() : was.generic_params[_bi2381]);
            _bi2381 += 1;
        }
    } else if (_mode2380 == 3) {
        var _n2378 = input.count();
        for (var _ in 0.._n2378) {
            _f2377.append(_m_GenericParam_read(input));
        }
    } else {
        var _n2378 = input.count();
        if (input.merging) {
            input.error = "s.*.generic_params" + " written by place";
        }
        for (var _ in 0.._n2378) {
            var _tag2379 = input.unsigned();
            if (_tag2379 & 1 == 1) {
                if (!input.merging) {
                    _f2377.append(was.generic_params[_tag2379 >> 1]);
                }
            } else {
                var _read = _m_GenericParam_read(input);
                if (!input.merging or true) {
                    _f2377.append(_read);
                }
            }
        }
    }
    var _f2393 = Array<VariableDef>();
    var _mode2396 = input.unsigned();
    if (_mode2396 == 2) {
        var _changed2385 = HashMap<ulong, VariableDef>();
        ulong _bi2397 = 0;
        var _n2394 = input.count();
        for (var _ in 0.._n2394) {
            var _at2398 = input.unsigned();
            while (_f2393.count < _at2398 or (input.merging and _bi2397 < was.field_members.count)) {
                var _c = _changed2385.try_get(_bi2397);
                _f2393.append(_c.is_value() ? _c.value() : was.field_members[_bi2397]);
                _bi2397 += 1;
            }
            _f2393.append(_m_VariableDef_read(input));
        }
        while (_bi2397 < was.field_members.count) {
            var _c = _changed2385.try_get(_bi2397);
            _f2393.append(_c.is_value() ? _c.value() : was.field_members[_bi2397]);
            _bi2397 += 1;
        }
    } else if (_mode2396 == 3) {
        var _n2394 = input.count();
        for (var _ in 0.._n2394) {
            _f2393.append(_m_VariableDef_read(input));
        }
    } else {
        var _n2394 = input.count();
        if (input.merging) {
            input.error = "s.*.field_members" + " written by place";
        }
        for (var _ in 0.._n2394) {
            var _tag2395 = input.unsigned();
            if (_tag2395 & 1 == 1) {
                if (!input.merging) {
                    _f2393.append(was.field_members[_tag2395 >> 1]);
                }
            } else {
                var _read = _m_VariableDef_read(input);
                if (!input.merging or true) {
                    _f2393.append(_read);
                }
            }
        }
    }
    var _f2409 = Array<FunctionDef>();
    var _mode2412 = input.unsigned();
    if (_mode2412 == 2) {
        var _changed2401 = HashMap<ulong, FunctionDef>();
        ulong _bi2413 = 0;
        var _n2410 = input.count();
        for (var _ in 0.._n2410) {
            var _at2414 = input.unsigned();
            while (_f2409.count < _at2414 or (input.merging and _bi2413 < was.method_members.count)) {
                var _c = _changed2401.try_get(_bi2413);
                _f2409.append(_c.is_value() ? _c.value() : was.method_members[_bi2413]);
                _bi2413 += 1;
            }
            _f2409.append(_m_FunctionDef_read(input));
        }
        while (_bi2413 < was.method_members.count) {
            var _c = _changed2401.try_get(_bi2413);
            _f2409.append(_c.is_value() ? _c.value() : was.method_members[_bi2413]);
            _bi2413 += 1;
        }
    } else if (_mode2412 == 3) {
        var _n2410 = input.count();
        for (var _ in 0.._n2410) {
            _f2409.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2410 = input.count();
        if (input.merging) {
            input.error = "s.*.method_members" + " written by place";
        }
        for (var _ in 0.._n2410) {
            var _tag2411 = input.unsigned();
            if (_tag2411 & 1 == 1) {
                if (!input.merging) {
                    _f2409.append(was.method_members[_tag2411 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2409.append(_read);
                }
            }
        }
    }
    var _f2425 = Array<FunctionDef>();
    var _mode2428 = input.unsigned();
    if (_mode2428 == 2) {
        var _changed2417 = HashMap<ulong, FunctionDef>();
        ulong _bi2429 = 0;
        var _n2426 = input.count();
        for (var _ in 0.._n2426) {
            var _at2430 = input.unsigned();
            while (_f2425.count < _at2430 or (input.merging and _bi2429 < was.generic_methods.count)) {
                var _c = _changed2417.try_get(_bi2429);
                _f2425.append(_c.is_value() ? _c.value() : was.generic_methods[_bi2429]);
                _bi2429 += 1;
            }
            _f2425.append(_m_FunctionDef_read(input));
        }
        while (_bi2429 < was.generic_methods.count) {
            var _c = _changed2417.try_get(_bi2429);
            _f2425.append(_c.is_value() ? _c.value() : was.generic_methods[_bi2429]);
            _bi2429 += 1;
        }
    } else if (_mode2428 == 3) {
        var _n2426 = input.count();
        for (var _ in 0.._n2426) {
            _f2425.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2426 = input.count();
        if (input.merging) {
            input.error = "s.*.generic_methods" + " written by place";
        }
        for (var _ in 0.._n2426) {
            var _tag2427 = input.unsigned();
            if (_tag2427 & 1 == 1) {
                if (!input.merging) {
                    _f2425.append(was.generic_methods[_tag2427 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2425.append(_read);
                }
            }
        }
    }
    var _f2441 = Array<FunctionDef>();
    var _mode2444 = input.unsigned();
    if (_mode2444 == 2) {
        var _changed2433 = HashMap<ulong, FunctionDef>();
        ulong _bi2445 = 0;
        var _n2442 = input.count();
        for (var _ in 0.._n2442) {
            var _at2446 = input.unsigned();
            while (_f2441.count < _at2446 or (input.merging and _bi2445 < was.constructors.count)) {
                var _c = _changed2433.try_get(_bi2445);
                _f2441.append(_c.is_value() ? _c.value() : was.constructors[_bi2445]);
                _bi2445 += 1;
            }
            _f2441.append(_m_FunctionDef_read(input));
        }
        while (_bi2445 < was.constructors.count) {
            var _c = _changed2433.try_get(_bi2445);
            _f2441.append(_c.is_value() ? _c.value() : was.constructors[_bi2445]);
            _bi2445 += 1;
        }
    } else if (_mode2444 == 3) {
        var _n2442 = input.count();
        for (var _ in 0.._n2442) {
            _f2441.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2442 = input.count();
        if (input.merging) {
            input.error = "s.*.constructors" + " written by place";
        }
        for (var _ in 0.._n2442) {
            var _tag2443 = input.unsigned();
            if (_tag2443 & 1 == 1) {
                if (!input.merging) {
                    _f2441.append(was.constructors[_tag2443 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2441.append(_read);
                }
            }
        }
    }
    var _f2448 = _m_FunctionDef_read(input);
    var _f2449 = _m_FunctionDef_read(input);
    var _f2450 = _m_FunctionDef_read(input);
    var _f2460 = Array<TypeName>();
    var _mode2463 = input.unsigned();
    if (_mode2463 == 2) {
        var _changed2452 = HashMap<ulong, TypeName>();
        ulong _bi2464 = 0;
        var _n2461 = input.count();
        for (var _ in 0.._n2461) {
            var _at2465 = input.unsigned();
            while (_f2460.count < _at2465 or (input.merging and _bi2464 < was.traits.count)) {
                var _c = _changed2452.try_get(_bi2464);
                _f2460.append(_c.is_value() ? _c.value() : was.traits[_bi2464]);
                _bi2464 += 1;
            }
            _f2460.append(_m_TypeName_read(input));
        }
        while (_bi2464 < was.traits.count) {
            var _c = _changed2452.try_get(_bi2464);
            _f2460.append(_c.is_value() ? _c.value() : was.traits[_bi2464]);
            _bi2464 += 1;
        }
    } else if (_mode2463 == 3) {
        var _n2461 = input.count();
        for (var _ in 0.._n2461) {
            _f2460.append(_m_TypeName_read(input));
        }
    } else {
        var _n2461 = input.count();
        if (input.merging) {
            input.error = "s.*.traits" + " written by place";
        }
        for (var _ in 0.._n2461) {
            var _tag2462 = input.unsigned();
            if (_tag2462 & 1 == 1) {
                if (!input.merging) {
                    _f2460.append(was.traits[_tag2462 >> 1]);
                }
            } else {
                var _read = _m_TypeName_read(input);
                if (!input.merging or true) {
                    _f2460.append(_read);
                }
            }
        }
    }
    var _f2476 = Array<ast.Attribute>();
    var _mode2479 = input.unsigned();
    if (_mode2479 == 2) {
        var _changed2468 = HashMap<ulong, ast.Attribute>();
        ulong _bi2480 = 0;
        var _n2477 = input.count();
        for (var _ in 0.._n2477) {
            var _at2481 = input.unsigned();
            while (_f2476.count < _at2481 or (input.merging and _bi2480 < was.attributes.count)) {
                var _c = _changed2468.try_get(_bi2480);
                _f2476.append(_c.is_value() ? _c.value() : was.attributes[_bi2480]);
                _bi2480 += 1;
            }
            _f2476.append(_a_Attribute_read(input));
        }
        while (_bi2480 < was.attributes.count) {
            var _c = _changed2468.try_get(_bi2480);
            _f2476.append(_c.is_value() ? _c.value() : was.attributes[_bi2480]);
            _bi2480 += 1;
        }
    } else if (_mode2479 == 3) {
        var _n2477 = input.count();
        for (var _ in 0.._n2477) {
            _f2476.append(_a_Attribute_read(input));
        }
    } else {
        var _n2477 = input.count();
        if (input.merging) {
            input.error = "s.*.attributes" + " written by place";
        }
        for (var _ in 0.._n2477) {
            var _tag2478 = input.unsigned();
            if (_tag2478 & 1 == 1) {
                if (!input.merging) {
                    _f2476.append(was.attributes[_tag2478 >> 1]);
                }
            } else {
                var _read = _a_Attribute_read(input);
                if (!input.merging or true) {
                    _f2476.append(_read);
                }
            }
        }
    }
    var _f2483 = input.loc();
    var _o2485 = Optional<Array<EnumCaseDef>>.Empty;
    if (input.unsigned() == 1) {
        var _v2486 = Array<EnumCaseDef>();
        var _n2487 = input.count();
        for (var _ in 0.._n2487) {
            _v2486.append(_m_EnumCaseDef_read(input));
        }
        _o2485 = Optional<Array<EnumCaseDef>>.Value(_v2486);
    }
    var _f2488 = _o2485;
    return StructDef(
        _f2366, _f2367, _f2377, _f2393, _f2409, _f2425, _f2441, _f2448, _f2449, _f2450, _f2460, _f2476, _f2483, _f2488
    );
}

_patch_s_index(value: StructDef, base: DeltaBase, slot: ulong) {
    if (base.verifying) {
        ulong _j2383 = 0;
        for (var _item2368 in value.generic_params) {
            var scratch = base.scratch();
            _m_GenericParam_write(scratch, _item2368);
            base.add($"s.{slot}.generic_params", scratch, _j2383);
            _j2383 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2399 = 0;
        for (var _item2384 in value.field_members) {
            var scratch = base.scratch();
            _m_VariableDef_write(scratch, _item2384);
            base.add($"s.{slot}.field_members", scratch, _j2399);
            _j2399 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2415 = 0;
        for (var _item2400 in value.method_members) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2400);
            base.add($"s.{slot}.method_members", scratch, _j2415);
            _j2415 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2431 = 0;
        for (var _item2416 in value.generic_methods) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2416);
            base.add($"s.{slot}.generic_methods", scratch, _j2431);
            _j2431 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2447 = 0;
        for (var _item2432 in value.constructors) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2432);
            base.add($"s.{slot}.constructors", scratch, _j2447);
            _j2447 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2466 = 0;
        for (var _item2451 in value.traits) {
            var scratch = base.scratch();
            _m_TypeName_write(scratch, _item2451);
            base.add($"s.{slot}.traits", scratch, _j2466);
            _j2466 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2482 = 0;
        for (var _item2467 in value.attributes) {
            var scratch = base.scratch();
            _a_Attribute_write(scratch, _item2467);
            base.add($"s.{slot}.attributes", scratch, _j2482);
            _j2482 += 1;
        }
    }
}

_patch_t_write(out: RecordOut, value: StructDef, base: DeltaBase, slot: ulong) {
    out.text(value.name);
    _m_TypeName_write(out, value.ty);
    var _seq2496 = base.ref_template_parts[slot].generic_params;
    ulong _bj2497 = 0;
    var _news2498 = Array<ulong>();
    for (var _i2499 in 0..value.generic_params.count) {
        if (_bj2497 < _seq2496.count and value.generic_params[_i2499] === _seq2496[_bj2497]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_GenericParam_write(scratch, value.generic_params[_i2499]);
                base.verify_same($"t.{slot}.generic_params", _bj2497, scratch);
            }
            _bj2497 += 1;
        } else if (_bj2497 < _seq2496.count
            and _same_m_GenericParam(value.generic_params[_i2499], _seq2496[_bj2497], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_GenericParam_write(scratch, value.generic_params[_i2499]);
                base.verify_same($"t.{slot}.generic_params", _bj2497, scratch);
            }
            _bj2497 += 1;
        } else {
            _news2498.append(_i2499);
        }
    }
    if (_bj2497 == _seq2496.count) {
        out.unsigned(2);
        out.unsigned(_news2498.count);
        for (var _i2499 in _news2498) {
            out.unsigned(_i2499);
            _m_GenericParam_write(out, value.generic_params[_i2499]);
        }
        base.count("t.*.generic_params" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.generic_params" + " whole", 0);
        out.unsigned(value.generic_params.count);
        for (var _i2499 in 0..value.generic_params.count) {
            _m_GenericParam_write(out, value.generic_params[_i2499]);
        }
    }
    var _seq2512 = base.ref_template_parts[slot].field_members;
    ulong _bj2513 = 0;
    var _news2514 = Array<ulong>();
    for (var _i2515 in 0..value.field_members.count) {
        if (_bj2513 < _seq2512.count and value.field_members[_i2515] === _seq2512[_bj2513]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_VariableDef_write(scratch, value.field_members[_i2515]);
                base.verify_same($"t.{slot}.field_members", _bj2513, scratch);
            }
            _bj2513 += 1;
        } else if (_bj2513 < _seq2512.count
            and _same_m_VariableDef(value.field_members[_i2515], _seq2512[_bj2513], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_VariableDef_write(scratch, value.field_members[_i2515]);
                base.verify_same($"t.{slot}.field_members", _bj2513, scratch);
            }
            _bj2513 += 1;
        } else {
            _news2514.append(_i2515);
        }
    }
    if (_bj2513 == _seq2512.count) {
        out.unsigned(2);
        out.unsigned(_news2514.count);
        for (var _i2515 in _news2514) {
            out.unsigned(_i2515);
            _m_VariableDef_write(out, value.field_members[_i2515]);
        }
        base.count("t.*.field_members" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.field_members" + " whole", 0);
        out.unsigned(value.field_members.count);
        for (var _i2515 in 0..value.field_members.count) {
            _m_VariableDef_write(out, value.field_members[_i2515]);
        }
    }
    var _seq2528 = base.ref_template_parts[slot].method_members;
    ulong _bj2529 = 0;
    var _news2530 = Array<ulong>();
    for (var _i2531 in 0..value.method_members.count) {
        if (_bj2529 < _seq2528.count and value.method_members[_i2531] === _seq2528[_bj2529]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.method_members[_i2531]);
                base.verify_same($"t.{slot}.method_members", _bj2529, scratch);
            }
            _bj2529 += 1;
        } else if (_bj2529 < _seq2528.count
            and _same_m_FunctionDef(value.method_members[_i2531], _seq2528[_bj2529], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.method_members[_i2531]);
                base.verify_same($"t.{slot}.method_members", _bj2529, scratch);
            }
            _bj2529 += 1;
        } else {
            _news2530.append(_i2531);
        }
    }
    if (_bj2529 == _seq2528.count) {
        out.unsigned(2);
        out.unsigned(_news2530.count);
        for (var _i2531 in _news2530) {
            out.unsigned(_i2531);
            _m_FunctionDef_write(out, value.method_members[_i2531]);
        }
        base.count("t.*.method_members" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.method_members" + " whole", 0);
        out.unsigned(value.method_members.count);
        for (var _i2531 in 0..value.method_members.count) {
            _m_FunctionDef_write(out, value.method_members[_i2531]);
        }
    }
    var _seq2544 = base.ref_template_parts[slot].generic_methods;
    ulong _bj2545 = 0;
    var _news2546 = Array<ulong>();
    for (var _i2547 in 0..value.generic_methods.count) {
        if (_bj2545 < _seq2544.count and value.generic_methods[_i2547] === _seq2544[_bj2545]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.generic_methods[_i2547]);
                base.verify_same($"t.{slot}.generic_methods", _bj2545, scratch);
            }
            _bj2545 += 1;
        } else if (_bj2545 < _seq2544.count
            and _same_m_FunctionDef(value.generic_methods[_i2547], _seq2544[_bj2545], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.generic_methods[_i2547]);
                base.verify_same($"t.{slot}.generic_methods", _bj2545, scratch);
            }
            _bj2545 += 1;
        } else {
            _news2546.append(_i2547);
        }
    }
    if (_bj2545 == _seq2544.count) {
        out.unsigned(2);
        out.unsigned(_news2546.count);
        for (var _i2547 in _news2546) {
            out.unsigned(_i2547);
            _m_FunctionDef_write(out, value.generic_methods[_i2547]);
        }
        base.count("t.*.generic_methods" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.generic_methods" + " whole", 0);
        out.unsigned(value.generic_methods.count);
        for (var _i2547 in 0..value.generic_methods.count) {
            _m_FunctionDef_write(out, value.generic_methods[_i2547]);
        }
    }
    var _seq2560 = base.ref_template_parts[slot].constructors;
    ulong _bj2561 = 0;
    var _news2562 = Array<ulong>();
    for (var _i2563 in 0..value.constructors.count) {
        if (_bj2561 < _seq2560.count and value.constructors[_i2563] === _seq2560[_bj2561]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.constructors[_i2563]);
                base.verify_same($"t.{slot}.constructors", _bj2561, scratch);
            }
            _bj2561 += 1;
        } else if (_bj2561 < _seq2560.count
            and _same_m_FunctionDef(value.constructors[_i2563], _seq2560[_bj2561], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.constructors[_i2563]);
                base.verify_same($"t.{slot}.constructors", _bj2561, scratch);
            }
            _bj2561 += 1;
        } else {
            _news2562.append(_i2563);
        }
    }
    if (_bj2561 == _seq2560.count) {
        out.unsigned(2);
        out.unsigned(_news2562.count);
        for (var _i2563 in _news2562) {
            out.unsigned(_i2563);
            _m_FunctionDef_write(out, value.constructors[_i2563]);
        }
        base.count("t.*.constructors" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.constructors" + " whole", 0);
        out.unsigned(value.constructors.count);
        for (var _i2563 in 0..value.constructors.count) {
            _m_FunctionDef_write(out, value.constructors[_i2563]);
        }
    }
    _m_FunctionDef_write(out, value.destructor);
    _m_FunctionDef_write(out, value.acquire);
    _m_FunctionDef_write(out, value.release);
    var _seq2579 = base.ref_template_parts[slot].traits;
    ulong _bj2580 = 0;
    var _news2581 = Array<ulong>();
    for (var _i2582 in 0..value.traits.count) {
        if (_bj2580 < _seq2579.count and value.traits[_i2582] === _seq2579[_bj2580]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_TypeName_write(scratch, value.traits[_i2582]);
                base.verify_same($"t.{slot}.traits", _bj2580, scratch);
            }
            _bj2580 += 1;
        } else if (_bj2580 < _seq2579.count and _same_m_TypeName(value.traits[_i2582], _seq2579[_bj2580], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_TypeName_write(scratch, value.traits[_i2582]);
                base.verify_same($"t.{slot}.traits", _bj2580, scratch);
            }
            _bj2580 += 1;
        } else {
            _news2581.append(_i2582);
        }
    }
    if (_bj2580 == _seq2579.count) {
        out.unsigned(2);
        out.unsigned(_news2581.count);
        for (var _i2582 in _news2581) {
            out.unsigned(_i2582);
            _m_TypeName_write(out, value.traits[_i2582]);
        }
        base.count("t.*.traits" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.traits" + " whole", 0);
        out.unsigned(value.traits.count);
        for (var _i2582 in 0..value.traits.count) {
            _m_TypeName_write(out, value.traits[_i2582]);
        }
    }
    var _seq2595 = base.ref_template_parts[slot].attributes;
    ulong _bj2596 = 0;
    var _news2597 = Array<ulong>();
    for (var _i2598 in 0..value.attributes.count) {
        if (_bj2596 < _seq2595.count and value.attributes[_i2598] === _seq2595[_bj2596]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _a_Attribute_write(scratch, value.attributes[_i2598]);
                base.verify_same($"t.{slot}.attributes", _bj2596, scratch);
            }
            _bj2596 += 1;
        } else if (_bj2596 < _seq2595.count and _same_a_Attribute(value.attributes[_i2598], _seq2595[_bj2596], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _a_Attribute_write(scratch, value.attributes[_i2598]);
                base.verify_same($"t.{slot}.attributes", _bj2596, scratch);
            }
            _bj2596 += 1;
        } else {
            _news2597.append(_i2598);
        }
    }
    if (_bj2596 == _seq2595.count) {
        out.unsigned(2);
        out.unsigned(_news2597.count);
        for (var _i2598 in _news2597) {
            out.unsigned(_i2598);
            _a_Attribute_write(out, value.attributes[_i2598]);
        }
        base.count("t.*.attributes" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.attributes" + " whole", 0);
        out.unsigned(value.attributes.count);
        for (var _i2598 in 0..value.attributes.count) {
            _a_Attribute_write(out, value.attributes[_i2598]);
        }
    }
    out.loc(value.loc);
    if (value.enum_cases.is_value()) {
        out.unsigned(1);
        out.unsigned(value.enum_cases.value().count);
        for (var _item2607 in value.enum_cases.value()) {
            _m_EnumCaseDef_write(out, _item2607);
        }
    } else {
        out.unsigned(0);
    }
}

_patch_t_read(input: RecordIn, was: StructDef): StructDef {
    var _f2489 = input.text();
    var _f2490 = _m_TypeName_read(input);
    var _f2500 = Array<GenericParam>();
    var _mode2503 = input.unsigned();
    if (_mode2503 == 2) {
        var _changed2492 = HashMap<ulong, GenericParam>();
        ulong _bi2504 = 0;
        var _n2501 = input.count();
        for (var _ in 0.._n2501) {
            var _at2505 = input.unsigned();
            while (_f2500.count < _at2505 or (input.merging and _bi2504 < was.generic_params.count)) {
                var _c = _changed2492.try_get(_bi2504);
                _f2500.append(_c.is_value() ? _c.value() : was.generic_params[_bi2504]);
                _bi2504 += 1;
            }
            _f2500.append(_m_GenericParam_read(input));
        }
        while (_bi2504 < was.generic_params.count) {
            var _c = _changed2492.try_get(_bi2504);
            _f2500.append(_c.is_value() ? _c.value() : was.generic_params[_bi2504]);
            _bi2504 += 1;
        }
    } else if (_mode2503 == 3) {
        var _n2501 = input.count();
        for (var _ in 0.._n2501) {
            _f2500.append(_m_GenericParam_read(input));
        }
    } else {
        var _n2501 = input.count();
        if (input.merging) {
            input.error = "t.*.generic_params" + " written by place";
        }
        for (var _ in 0.._n2501) {
            var _tag2502 = input.unsigned();
            if (_tag2502 & 1 == 1) {
                if (!input.merging) {
                    _f2500.append(was.generic_params[_tag2502 >> 1]);
                }
            } else {
                var _read = _m_GenericParam_read(input);
                if (!input.merging or true) {
                    _f2500.append(_read);
                }
            }
        }
    }
    var _f2516 = Array<VariableDef>();
    var _mode2519 = input.unsigned();
    if (_mode2519 == 2) {
        var _changed2508 = HashMap<ulong, VariableDef>();
        ulong _bi2520 = 0;
        var _n2517 = input.count();
        for (var _ in 0.._n2517) {
            var _at2521 = input.unsigned();
            while (_f2516.count < _at2521 or (input.merging and _bi2520 < was.field_members.count)) {
                var _c = _changed2508.try_get(_bi2520);
                _f2516.append(_c.is_value() ? _c.value() : was.field_members[_bi2520]);
                _bi2520 += 1;
            }
            _f2516.append(_m_VariableDef_read(input));
        }
        while (_bi2520 < was.field_members.count) {
            var _c = _changed2508.try_get(_bi2520);
            _f2516.append(_c.is_value() ? _c.value() : was.field_members[_bi2520]);
            _bi2520 += 1;
        }
    } else if (_mode2519 == 3) {
        var _n2517 = input.count();
        for (var _ in 0.._n2517) {
            _f2516.append(_m_VariableDef_read(input));
        }
    } else {
        var _n2517 = input.count();
        if (input.merging) {
            input.error = "t.*.field_members" + " written by place";
        }
        for (var _ in 0.._n2517) {
            var _tag2518 = input.unsigned();
            if (_tag2518 & 1 == 1) {
                if (!input.merging) {
                    _f2516.append(was.field_members[_tag2518 >> 1]);
                }
            } else {
                var _read = _m_VariableDef_read(input);
                if (!input.merging or true) {
                    _f2516.append(_read);
                }
            }
        }
    }
    var _f2532 = Array<FunctionDef>();
    var _mode2535 = input.unsigned();
    if (_mode2535 == 2) {
        var _changed2524 = HashMap<ulong, FunctionDef>();
        ulong _bi2536 = 0;
        var _n2533 = input.count();
        for (var _ in 0.._n2533) {
            var _at2537 = input.unsigned();
            while (_f2532.count < _at2537 or (input.merging and _bi2536 < was.method_members.count)) {
                var _c = _changed2524.try_get(_bi2536);
                _f2532.append(_c.is_value() ? _c.value() : was.method_members[_bi2536]);
                _bi2536 += 1;
            }
            _f2532.append(_m_FunctionDef_read(input));
        }
        while (_bi2536 < was.method_members.count) {
            var _c = _changed2524.try_get(_bi2536);
            _f2532.append(_c.is_value() ? _c.value() : was.method_members[_bi2536]);
            _bi2536 += 1;
        }
    } else if (_mode2535 == 3) {
        var _n2533 = input.count();
        for (var _ in 0.._n2533) {
            _f2532.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2533 = input.count();
        if (input.merging) {
            input.error = "t.*.method_members" + " written by place";
        }
        for (var _ in 0.._n2533) {
            var _tag2534 = input.unsigned();
            if (_tag2534 & 1 == 1) {
                if (!input.merging) {
                    _f2532.append(was.method_members[_tag2534 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2532.append(_read);
                }
            }
        }
    }
    var _f2548 = Array<FunctionDef>();
    var _mode2551 = input.unsigned();
    if (_mode2551 == 2) {
        var _changed2540 = HashMap<ulong, FunctionDef>();
        ulong _bi2552 = 0;
        var _n2549 = input.count();
        for (var _ in 0.._n2549) {
            var _at2553 = input.unsigned();
            while (_f2548.count < _at2553 or (input.merging and _bi2552 < was.generic_methods.count)) {
                var _c = _changed2540.try_get(_bi2552);
                _f2548.append(_c.is_value() ? _c.value() : was.generic_methods[_bi2552]);
                _bi2552 += 1;
            }
            _f2548.append(_m_FunctionDef_read(input));
        }
        while (_bi2552 < was.generic_methods.count) {
            var _c = _changed2540.try_get(_bi2552);
            _f2548.append(_c.is_value() ? _c.value() : was.generic_methods[_bi2552]);
            _bi2552 += 1;
        }
    } else if (_mode2551 == 3) {
        var _n2549 = input.count();
        for (var _ in 0.._n2549) {
            _f2548.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2549 = input.count();
        if (input.merging) {
            input.error = "t.*.generic_methods" + " written by place";
        }
        for (var _ in 0.._n2549) {
            var _tag2550 = input.unsigned();
            if (_tag2550 & 1 == 1) {
                if (!input.merging) {
                    _f2548.append(was.generic_methods[_tag2550 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2548.append(_read);
                }
            }
        }
    }
    var _f2564 = Array<FunctionDef>();
    var _mode2567 = input.unsigned();
    if (_mode2567 == 2) {
        var _changed2556 = HashMap<ulong, FunctionDef>();
        ulong _bi2568 = 0;
        var _n2565 = input.count();
        for (var _ in 0.._n2565) {
            var _at2569 = input.unsigned();
            while (_f2564.count < _at2569 or (input.merging and _bi2568 < was.constructors.count)) {
                var _c = _changed2556.try_get(_bi2568);
                _f2564.append(_c.is_value() ? _c.value() : was.constructors[_bi2568]);
                _bi2568 += 1;
            }
            _f2564.append(_m_FunctionDef_read(input));
        }
        while (_bi2568 < was.constructors.count) {
            var _c = _changed2556.try_get(_bi2568);
            _f2564.append(_c.is_value() ? _c.value() : was.constructors[_bi2568]);
            _bi2568 += 1;
        }
    } else if (_mode2567 == 3) {
        var _n2565 = input.count();
        for (var _ in 0.._n2565) {
            _f2564.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2565 = input.count();
        if (input.merging) {
            input.error = "t.*.constructors" + " written by place";
        }
        for (var _ in 0.._n2565) {
            var _tag2566 = input.unsigned();
            if (_tag2566 & 1 == 1) {
                if (!input.merging) {
                    _f2564.append(was.constructors[_tag2566 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2564.append(_read);
                }
            }
        }
    }
    var _f2571 = _m_FunctionDef_read(input);
    var _f2572 = _m_FunctionDef_read(input);
    var _f2573 = _m_FunctionDef_read(input);
    var _f2583 = Array<TypeName>();
    var _mode2586 = input.unsigned();
    if (_mode2586 == 2) {
        var _changed2575 = HashMap<ulong, TypeName>();
        ulong _bi2587 = 0;
        var _n2584 = input.count();
        for (var _ in 0.._n2584) {
            var _at2588 = input.unsigned();
            while (_f2583.count < _at2588 or (input.merging and _bi2587 < was.traits.count)) {
                var _c = _changed2575.try_get(_bi2587);
                _f2583.append(_c.is_value() ? _c.value() : was.traits[_bi2587]);
                _bi2587 += 1;
            }
            _f2583.append(_m_TypeName_read(input));
        }
        while (_bi2587 < was.traits.count) {
            var _c = _changed2575.try_get(_bi2587);
            _f2583.append(_c.is_value() ? _c.value() : was.traits[_bi2587]);
            _bi2587 += 1;
        }
    } else if (_mode2586 == 3) {
        var _n2584 = input.count();
        for (var _ in 0.._n2584) {
            _f2583.append(_m_TypeName_read(input));
        }
    } else {
        var _n2584 = input.count();
        if (input.merging) {
            input.error = "t.*.traits" + " written by place";
        }
        for (var _ in 0.._n2584) {
            var _tag2585 = input.unsigned();
            if (_tag2585 & 1 == 1) {
                if (!input.merging) {
                    _f2583.append(was.traits[_tag2585 >> 1]);
                }
            } else {
                var _read = _m_TypeName_read(input);
                if (!input.merging or true) {
                    _f2583.append(_read);
                }
            }
        }
    }
    var _f2599 = Array<ast.Attribute>();
    var _mode2602 = input.unsigned();
    if (_mode2602 == 2) {
        var _changed2591 = HashMap<ulong, ast.Attribute>();
        ulong _bi2603 = 0;
        var _n2600 = input.count();
        for (var _ in 0.._n2600) {
            var _at2604 = input.unsigned();
            while (_f2599.count < _at2604 or (input.merging and _bi2603 < was.attributes.count)) {
                var _c = _changed2591.try_get(_bi2603);
                _f2599.append(_c.is_value() ? _c.value() : was.attributes[_bi2603]);
                _bi2603 += 1;
            }
            _f2599.append(_a_Attribute_read(input));
        }
        while (_bi2603 < was.attributes.count) {
            var _c = _changed2591.try_get(_bi2603);
            _f2599.append(_c.is_value() ? _c.value() : was.attributes[_bi2603]);
            _bi2603 += 1;
        }
    } else if (_mode2602 == 3) {
        var _n2600 = input.count();
        for (var _ in 0.._n2600) {
            _f2599.append(_a_Attribute_read(input));
        }
    } else {
        var _n2600 = input.count();
        if (input.merging) {
            input.error = "t.*.attributes" + " written by place";
        }
        for (var _ in 0.._n2600) {
            var _tag2601 = input.unsigned();
            if (_tag2601 & 1 == 1) {
                if (!input.merging) {
                    _f2599.append(was.attributes[_tag2601 >> 1]);
                }
            } else {
                var _read = _a_Attribute_read(input);
                if (!input.merging or true) {
                    _f2599.append(_read);
                }
            }
        }
    }
    var _f2606 = input.loc();
    var _o2608 = Optional<Array<EnumCaseDef>>.Empty;
    if (input.unsigned() == 1) {
        var _v2609 = Array<EnumCaseDef>();
        var _n2610 = input.count();
        for (var _ in 0.._n2610) {
            _v2609.append(_m_EnumCaseDef_read(input));
        }
        _o2608 = Optional<Array<EnumCaseDef>>.Value(_v2609);
    }
    var _f2611 = _o2608;
    return StructDef(
        _f2489, _f2490, _f2500, _f2516, _f2532, _f2548, _f2564, _f2571, _f2572, _f2573, _f2583, _f2599, _f2606, _f2611
    );
}

_patch_t_index(value: StructDef, base: DeltaBase, slot: ulong) {
    if (base.verifying) {
        ulong _j2506 = 0;
        for (var _item2491 in value.generic_params) {
            var scratch = base.scratch();
            _m_GenericParam_write(scratch, _item2491);
            base.add($"t.{slot}.generic_params", scratch, _j2506);
            _j2506 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2522 = 0;
        for (var _item2507 in value.field_members) {
            var scratch = base.scratch();
            _m_VariableDef_write(scratch, _item2507);
            base.add($"t.{slot}.field_members", scratch, _j2522);
            _j2522 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2538 = 0;
        for (var _item2523 in value.method_members) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2523);
            base.add($"t.{slot}.method_members", scratch, _j2538);
            _j2538 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2554 = 0;
        for (var _item2539 in value.generic_methods) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2539);
            base.add($"t.{slot}.generic_methods", scratch, _j2554);
            _j2554 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2570 = 0;
        for (var _item2555 in value.constructors) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2555);
            base.add($"t.{slot}.constructors", scratch, _j2570);
            _j2570 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2589 = 0;
        for (var _item2574 in value.traits) {
            var scratch = base.scratch();
            _m_TypeName_write(scratch, _item2574);
            base.add($"t.{slot}.traits", scratch, _j2589);
            _j2589 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2605 = 0;
        for (var _item2590 in value.attributes) {
            var scratch = base.scratch();
            _a_Attribute_write(scratch, _item2590);
            base.add($"t.{slot}.attributes", scratch, _j2605);
            _j2605 += 1;
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
        for (var _item2612 in value.imports) {
            _a_Import_write(out, _item2612);
        }
        found.append(("imports", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.structs.count);
        for (var _item2613 in value.structs) {
            _m_StructDef_write(out, _item2613);
        }
        found.append(("structs", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.blank_bodies = false;
        out.unsigned(value.traits.count);
        for (var _item2614 in value.traits) {
            _m_TraitDef_write(out, _item2614);
        }
        found.append(("traits", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.extensions.count);
        for (var _item2615 in value.extensions) {
            _m_ExtensionDef_write(out, _item2615);
        }
        found.append(("extensions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.functions.count);
        for (var _item2616 in value.functions) {
            _m_FunctionDef_write(out, _item2616);
        }
        found.append(("functions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.externs.count);
        for (var _item2617 in value.externs) {
            _m_ExternDef_write(out, _item2617);
        }
        found.append(("externs", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.globals.count);
        for (var _item2618 in value.globals) {
            _m_VariableDef_write(out, _item2618);
        }
        found.append(("globals", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.static_blocks.count);
        for (var _item2619 in value.static_blocks) {
            _m_ModuleStaticBlock_write(out, _item2619);
        }
        found.append(("static_blocks", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.enums.count);
        for (var _item2620 in value.enums) {
            _m_EnumDef_write(out, _item2620);
        }
        found.append(("enums", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.struct_specs.count);
        for (var _item2621 in value.struct_specs) {
            _m_TypeName_write(out, _item2621);
        }
        found.append(("struct_specs", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.func_specs.count);
        for (var _item2622 in value.func_specs) {
            _m_TypeName_write(out, _item2622);
        }
        found.append(("func_specs", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.type_aliases.count);
        for (var _item2623 in value.type_aliases) {
            _m_TypeAliasDef_write(out, _item2623);
        }
        found.append(("type_aliases", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.withheld.count);
        for (var _item2624 in value.withheld) {
            _m_Withheld_write(out, _item2624);
        }
        found.append(("withheld", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.properties.count);
        for (var _item2625 in value.properties) {
            _m_PropertyDef_write(out, _item2625);
        }
        found.append(("properties", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.type_uses.count);
        for (var _item2626 in value.type_uses) {
            _m_TypeUse_write(out, _item2626);
        }
        found.append(("type_uses", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.use_contexts.count);
        for (var _item2627 in value.use_contexts) {
            _m_UseContext_write(out, _item2627);
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
            for (var _item2628 in value.literal_args) {
                var (_t2629, _t2630, _t2631) = _item2628;
                out.loc(_t2629);
                out.unsigned(_t2630);
                out.loc(_t2631);
            }
        }
        found.append(("literal_args", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.constrained_aliases.count);
        for (var _item2632 in value.constrained_aliases) {
            _m_TypeAliasDef_write(out, _item2632);
        }
        found.append(("constrained_aliases", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.trait_types.count);
        for (var _item2633 in value.trait_types) {
            _m_TraitType_write(out, _item2633);
        }
        found.append(("trait_types", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.conversions.count);
        for (var _item2634 in value.conversions) {
            _m_Conversion_write(out, _item2634);
        }
        found.append(("conversions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2636 = Array<(u8[], u8[], String)>();
        for (var (_key2635, _) in value.overload_sets) {
            var _scratch2637 = out.scratch();
            _scratch2637.text(_key2635);
            var _vscratch2639 = out.scratch();
            _vscratch2639.unsigned(value.overload_sets[_key2635].count);
            for (var _item2640 in value.overload_sets[_key2635]) {
                _vscratch2639.text(_item2640);
            }
            _keys2636.append((_scratch2637.finish(), _vscratch2639.finish(), _key2635));
        }
        _keys2636.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2636.count);
        for (var (_bytes2638, _, _key2635) in _keys2636) {
            out.text(_key2635);
            out.unsigned(value.overload_sets[_key2635].count);
            for (var _item2641 in value.overload_sets[_key2635]) {
                out.text(_item2641);
            }
        }
        found.append(("overload_sets", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2643 = Array<(u8[], u8[], String)>();
        for (var (_key2642, _) in value.overload_unions) {
            var _scratch2644 = out.scratch();
            _scratch2644.text(_key2642);
            var _vscratch2646 = out.scratch();
            _vscratch2646.unsigned(value.overload_unions[_key2642].count);
            for (var _item2647 in value.overload_unions[_key2642]) {
                _vscratch2646.unsigned(_item2647.count);
                for (var _item2648 in _item2647) {
                    _vscratch2646.text(_item2648);
                }
            }
            _keys2643.append((_scratch2644.finish(), _vscratch2646.finish(), _key2642));
        }
        _keys2643.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2643.count);
        for (var (_bytes2645, _, _key2642) in _keys2643) {
            out.text(_key2642);
            out.unsigned(value.overload_unions[_key2642].count);
            for (var _item2649 in value.overload_unions[_key2642]) {
                out.unsigned(_item2649.count);
                for (var _item2650 in _item2649) {
                    out.text(_item2650);
                }
            }
        }
        found.append(("overload_unions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2652 = Array<(u8[], u8[], String)>();
        for (var (_key2651, _) in value.method_overload_sets) {
            var _scratch2653 = out.scratch();
            _scratch2653.text(_key2651);
            var _vscratch2655 = out.scratch();
            var _keys2657 = Array<(u8[], u8[], String)>();
            for (var (_key2656, _) in value.method_overload_sets[_key2651]) {
                var _scratch2658 = _vscratch2655.scratch();
                _scratch2658.text(_key2656);
                var _vscratch2660 = _vscratch2655.scratch();
                _vscratch2660.unsigned(value.method_overload_sets[_key2651][_key2656].count);
                for (var _item2661 in value.method_overload_sets[_key2651][_key2656]) {
                    _vscratch2660.text(_item2661);
                }
                _keys2657.append((_scratch2658.finish(), _vscratch2660.finish(), _key2656));
            }
            _keys2657.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            _vscratch2655.unsigned(_keys2657.count);
            for (var (_bytes2659, _, _key2656) in _keys2657) {
                _vscratch2655.text(_key2656);
                _vscratch2655.unsigned(value.method_overload_sets[_key2651][_key2656].count);
                for (var _item2662 in value.method_overload_sets[_key2651][_key2656]) {
                    _vscratch2655.text(_item2662);
                }
            }
            _keys2652.append((_scratch2653.finish(), _vscratch2655.finish(), _key2651));
        }
        _keys2652.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2652.count);
        for (var (_bytes2654, _, _key2651) in _keys2652) {
            out.text(_key2651);
            var _keys2664 = Array<(u8[], u8[], String)>();
            for (var (_key2663, _) in value.method_overload_sets[_key2651]) {
                var _scratch2665 = out.scratch();
                _scratch2665.text(_key2663);
                var _vscratch2667 = out.scratch();
                _vscratch2667.unsigned(value.method_overload_sets[_key2651][_key2663].count);
                for (var _item2668 in value.method_overload_sets[_key2651][_key2663]) {
                    _vscratch2667.text(_item2668);
                }
                _keys2664.append((_scratch2665.finish(), _vscratch2667.finish(), _key2663));
            }
            _keys2664.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            out.unsigned(_keys2664.count);
            for (var (_bytes2666, _, _key2663) in _keys2664) {
                out.text(_key2663);
                out.unsigned(value.method_overload_sets[_key2651][_key2663].count);
                for (var _item2669 in value.method_overload_sets[_key2651][_key2663]) {
                    out.text(_item2669);
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
        var _keys2671 = Array<(u8[], u8[], Loc)>();
        for (var _key2670 in value.private_functions) {
            var _scratch2672 = out.scratch();
            _scratch2672.loc(_key2670);
            var _vscratch2674 = out.scratch();
            _keys2671.append((_scratch2672.finish(), _vscratch2674.finish(), _key2670));
        }
        _keys2671.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2671.count);
        for (var (_bytes2673, _, _key2670) in _keys2671) {
            out.loc(_key2670);
        }
        found.append(("private_functions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2676 = Array<(u8[], u8[], Loc)>();
        for (var _key2675 in value.file_private_functions) {
            var _scratch2677 = out.scratch();
            _scratch2677.loc(_key2675);
            var _vscratch2679 = out.scratch();
            _keys2676.append((_scratch2677.finish(), _vscratch2679.finish(), _key2675));
        }
        _keys2676.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2676.count);
        for (var (_bytes2678, _, _key2675) in _keys2676) {
            out.loc(_key2675);
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
            for (var _item2680 in value.call_targets) {
                var (_t2681, _t2682) = _item2680;
                out.loc(_t2681);
                out.text(_t2682);
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
            for (var _item2683 in value.argument_names) {
                var (_t2684, _t2685) = _item2683;
                out.loc(_t2684);
                out.text(_t2685);
            }
        }
        found.append(("argument_names", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.namespaces.count);
        for (var _item2686 in value.namespaces) {
            out.text(_item2686);
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
            for (var _item2687 in value.cached_files) {
                out.flag(_item2687);
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
            var _keys2689 = Array<(u8[], u8[], Loc)>();
            for (var (_key2688, _) in value.recorded_summaries) {
                var _scratch2690 = out.scratch();
                _scratch2690.loc(_key2688);
                var _vscratch2692 = out.scratch();
                _vscratch2692.text(value.recorded_summaries[_key2688]);
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
                out.text(value.recorded_summaries[_key2688]);
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
            var _keys2694 = Array<(u8[], u8[], Loc)>();
            for (var _key2693 in value.stripped) {
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
        var _keys2699 = Array<(u8[], u8[], String)>();
        for (var (_key2698, _) in value.spec_requests) {
            var _scratch2700 = out.scratch();
            _scratch2700.text(_key2698);
            var _vscratch2702 = out.scratch();
            _m_SpecRequest_write(_vscratch2702, value.spec_requests[_key2698]);
            _keys2699.append((_scratch2700.finish(), _vscratch2702.finish(), _key2698));
        }
        _keys2699.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2699.count);
        for (var (_bytes2701, _, _key2698) in _keys2699) {
            out.text(_key2698);
            _m_SpecRequest_write(out, value.spec_requests[_key2698]);
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
            for (var _item2703 in value.summaries_to_record) {
                var (_t2704, _t2705) = _item2703;
                out.loc(_t2704);
                out.text(_t2705);
            }
        }
        found.append(("summaries_to_record", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2707 = Array<(u8[], u8[], String)>();
        for (var (_key2706, _) in value.caller_copies) {
            var _scratch2708 = out.scratch();
            _scratch2708.text(_key2706);
            var _vscratch2710 = out.scratch();
            _vscratch2710.unsigned(value.caller_copies[_key2706].count);
            for (var _item2711 in value.caller_copies[_key2706]) {
                _vscratch2710.flag(_item2711);
            }
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
            out.text(_key2706);
            out.unsigned(value.caller_copies[_key2706].count);
            for (var _item2712 in value.caller_copies[_key2706]) {
                out.flag(_item2712);
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
    for (var _item2713 in value.structs) {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        _m_StructDef_write(out, _item2713);
        found.append(("structs " + _item2713.name, interface_text(out)));
    }
    for (var _item2714 in value.functions) {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        _m_FunctionDef_write(out, _item2714);
        found.append(("functions " + _item2714.name, interface_text(out)));
    }
    return found;
}
