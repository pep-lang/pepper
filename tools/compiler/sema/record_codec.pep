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
    return FunctionCallExpression(_f1408, _f1411, _f1412, _f1414);
}

_m_NamedArgumentExpression_write(out: RecordOut, value: NamedArgumentExpression) {
    out.text(value.name);
    _m_Expression_write(out, value.value);
    out.loc(value.loc);
}

_m_NamedArgumentExpression_read(input: RecordIn): NamedArgumentExpression {
    var _f1415 = input.text();
    var _f1416 = _m_Expression_read(input);
    var _f1417 = input.loc();
    return NamedArgumentExpression(_f1416, _f1415, _f1417);
}

_m_DefaultArgumentExpression_write(out: RecordOut, value: DefaultArgumentExpression) {
    _m_TypeName_write(out, value.ty);
}

_m_DefaultArgumentExpression_read(input: RecordIn): DefaultArgumentExpression {
    var _f1418 = _m_TypeName_read(input);
    return DefaultArgumentExpression(_f1418);
}

_m_MethodCallExpression_write(out: RecordOut, value: MethodCallExpression) {
    _m_Expression_write(out, value.this_value);
    out.text(value.method);
    out.unsigned(value.args.count);
    for (var _item1419 in value.args) {
        _m_Expression_write(out, _item1419);
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
    var _f1420 = _m_Expression_read(input);
    var _f1421 = input.text();
    var _v1422 = Array<Expression>();
    var _n1423 = input.count();
    for (var _ in 0.._n1423) {
        _v1422.append(_m_Expression_read(input));
    }
    var _f1424 = _v1422;
    var _f1425 = input.loc();
    var _o1426 = Optional<TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o1426 = Optional<TypeName>.Value(_m_TypeName_read(input));
    }
    var _f1427 = _o1426;
    return MethodCallExpression(_f1420, _f1421, _f1424, _f1425, _f1427);
}

_m_FunctionRefExpression_write(out: RecordOut, value: FunctionRefExpression) {
    out.text(value.function);
    _m_TypeName_write(out, value.ty);
    out.loc(value.loc);
}

_m_FunctionRefExpression_read(input: RecordIn): FunctionRefExpression {
    var _f1428 = input.text();
    var _f1429 = _m_TypeName_read(input);
    var _f1430 = input.loc();
    return FunctionRefExpression(_f1428, _f1429, _f1430);
}

_m_InvokeExpression_write(out: RecordOut, value: InvokeExpression) {
    _m_Expression_write(out, value.callee);
    out.unsigned(value.args.count);
    for (var _item1431 in value.args) {
        _m_Expression_write(out, _item1431);
    }
}

_m_InvokeExpression_read(input: RecordIn): InvokeExpression {
    var _f1432 = _m_Expression_read(input);
    var _v1433 = Array<Expression>();
    var _n1434 = input.count();
    for (var _ in 0.._n1434) {
        _v1433.append(_m_Expression_read(input));
    }
    var _f1435 = _v1433;
    return InvokeExpression(_f1432, _f1435);
}

_m_MakeClosureExpression_write(out: RecordOut, value: MakeClosureExpression) {
    _m_Expression_write(out, value.value);
    out.text(value.closure);
    _m_TypeName_write(out, value.ty);
    out.loc(value.loc);
}

_m_MakeClosureExpression_read(input: RecordIn): MakeClosureExpression {
    var _f1437 = _m_Expression_read(input);
    var _f1438 = input.text();
    var _f1439 = _m_TypeName_read(input);
    var _f1440 = input.loc();
    return MakeClosureExpression(_f1437, _f1438, _f1439, _f1440);
}

_m_CallPointerExpression_write(out: RecordOut, value: CallPointerExpression) {
    _m_Expression_write(out, value.pointer);
    out.unsigned(value.args.count);
    for (var _item1442 in value.args) {
        _m_Expression_write(out, _item1442);
    }
}

_m_CallPointerExpression_read(input: RecordIn): CallPointerExpression {
    var _f1443 = _m_Expression_read(input);
    var _v1444 = Array<Expression>();
    var _n1445 = input.count();
    for (var _ in 0.._n1445) {
        _v1444.append(_m_Expression_read(input));
    }
    var _f1446 = _v1444;
    return CallPointerExpression(_f1443, _f1446);
}

_m_MoveExpression_write(out: RecordOut, value: MoveExpression) {
    _m_Expression_write(out, value.value);
    out.loc(value.loc);
}

_m_MoveExpression_read(input: RecordIn): MoveExpression {
    var _f1449 = _m_Expression_read(input);
    var _f1450 = input.loc();
    return MoveExpression(_f1449, _f1450);
}

_m_DestructureExpression_write(out: RecordOut, value: DestructureExpression) {
    _m_Expression_write(out, value.value);
    out.unsigned(value.count);
    out.loc(value.loc);
}

_m_DestructureExpression_read(input: RecordIn): DestructureExpression {
    var _f1451 = _m_Expression_read(input);
    var _f1452 = input.unsigned();
    var _f1453 = input.loc();
    return DestructureExpression(_f1451, _f1452, _f1453);
}

_m_StaticCaseExpression_write(out: RecordOut, value: StaticCaseExpression) {
    _m_TypeName_write(out, value.ty);
    out.signed(value.tag as long);
}

_m_StaticCaseExpression_read(input: RecordIn): StaticCaseExpression {
    var _f1456 = _m_TypeName_read(input);
    var _f1457 = input.signed();
    return StaticCaseExpression(_f1456, _f1457);
}

_m_StaticStringExpression_write(out: RecordOut, value: StaticStringExpression) {
    out.text(value.value);
    out.loc(value.loc);
}

_m_StaticStringExpression_read(input: RecordIn): StaticStringExpression {
    var _f1458 = input.text();
    var _f1459 = input.loc();
    return StaticStringExpression(_f1458, _f1459);
}

_m_SubjectExpression_write(out: RecordOut, value: SubjectExpression) {
    out.unsigned(value.id);
    _m_TypeName_write(out, value.ty);
    out.loc(value.loc);
}

_m_SubjectExpression_read(input: RecordIn): SubjectExpression {
    var _f1461 = input.unsigned();
    var _f1462 = _m_TypeName_read(input);
    var _f1463 = input.loc();
    return SubjectExpression(_f1461, _f1462, _f1463);
}

_m_ToTraitExpression_write(out: RecordOut, value: ToTraitExpression) {
    _m_Expression_write(out, value.value);
    _m_TypeName_write(out, value.from);
    _m_TypeName_write(out, value.to);
    out.loc(value.loc);
}

_m_ToTraitExpression_read(input: RecordIn): ToTraitExpression {
    var _f1464 = _m_Expression_read(input);
    var _f1465 = _m_TypeName_read(input);
    var _f1466 = _m_TypeName_read(input);
    var _f1467 = input.loc();
    return ToTraitExpression(_f1464, _f1465, _f1466, _f1467);
}

_m_FromTraitExpression_write(out: RecordOut, value: FromTraitExpression) {
    _m_Expression_write(out, value.value);
    _m_TypeName_write(out, value.from);
    _m_TypeName_write(out, value.to);
    out.unsigned(value.candidates.count);
    for (var _item1468 in value.candidates) {
        _m_TypeName_write(out, _item1468);
    }
    out.flag(value.test);
    out.loc(value.loc);
}

_m_FromTraitExpression_read(input: RecordIn): FromTraitExpression {
    var _f1469 = _m_Expression_read(input);
    var _f1470 = _m_TypeName_read(input);
    var _f1471 = _m_TypeName_read(input);
    var _v1472 = Array<TypeName>();
    var _n1473 = input.count();
    for (var _ in 0.._n1473) {
        _v1472.append(_m_TypeName_read(input));
    }
    var _f1474 = _v1472;
    var _f1475 = input.flag();
    var _f1476 = input.loc();
    return FromTraitExpression(_f1469, _f1470, _f1471, _f1474, _f1475, _f1476);
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
        var _f1436 = _m_ClosureLiteral_read(input);
        return Expression.ClosureLiteral(_f1436);
    }
    if (tag == 36) {
        return Expression.MakeClosure(_m_MakeClosureExpression_read(input));
    }
    if (tag == 37) {
        var _f1441 = input.text();
        return Expression.MethodAddress(_f1441);
    }
    if (tag == 38) {
        return Expression.CallPointer(_m_CallPointerExpression_read(input));
    }
    if (tag == 39) {
        var _f1447 = _m_Expression_read(input);
        return Expression.ForIterator(_f1447);
    }
    if (tag == 40) {
        var _f1448 = _m_Expression_read(input);
        return Expression.WithEntered(_f1448);
    }
    if (tag == 41) {
        return Expression.Move(_m_MoveExpression_read(input));
    }
    if (tag == 42) {
        return Expression.Destructure(_m_DestructureExpression_read(input));
    }
    if (tag == 43) {
        var _f1454 = _m_MatchArmTest_read(input);
        return Expression.MatchArm(_f1454);
    }
    if (tag == 44) {
        var _f1455 = _m_CaseValue_read(input);
        return Expression.CaseValue(_f1455);
    }
    if (tag == 45) {
        return Expression.StaticCase(_m_StaticCaseExpression_read(input));
    }
    if (tag == 46) {
        return Expression.StaticString(_m_StaticStringExpression_read(input));
    }
    if (tag == 47) {
        var _f1460 = _m_WithSubject_read(input);
        return Expression.WithSubject(_f1460);
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
        var _f1477 = _m_StaticValue_read(input);
        return Expression.StaticValue(_f1477);
    }
    if (tag == 53) {
        var _f1478 = _m_StaticMember_read(input);
        return Expression.StaticMember(_f1478);
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
        var _f1479 = _m_VariableDef_read(input);
        return Declaration.Variable(_f1479);
    }
    if (tag == 1) {
        var _f1480 = _m_FunctionDef_read(input);
        return Declaration.Function(_f1480);
    }
    if (tag == 2) {
        var _f1481 = _m_StructDef_read(input);
        return Declaration.Struct(_f1481);
    }
    if (tag == 3) {
        var _f1482 = _m_TraitDef_read(input);
        return Declaration.Trait(_f1482);
    }
    if (tag == 4) {
        var _f1483 = _m_ExtensionDef_read(input);
        return Declaration.Extension(_f1483);
    }
    if (tag == 5) {
        var _f1484 = _m_ExternDef_read(input);
        return Declaration.Extern(_f1484);
    }
    if (tag == 6) {
        var _f1485 = _m_TypeAliasDef_read(input);
        return Declaration.TypeAlias(_f1485);
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
    var _hs1491 = Array<String>();
    for (var _item1486 in value.imports) {
        var scratch = base.scratch();
        _a_Import_write(scratch, _item1486);
        _hs1491.append(base.hash_of(scratch));
    }
    var _seq1492 = base.sequence("imports");
    ulong _bj1493 = 0;
    var _news1494 = Array<ulong>();
    for (var _i1495 in 0.._hs1491.count) {
        if (_bj1493 < _seq1492.count and _hs1491[_i1495] == _seq1492[_bj1493]) {
            _bj1493 += 1;
        } else {
            _news1494.append(_i1495);
        }
    }
    if (_bj1493 == _seq1492.count) {
        out.unsigned(2);
        out.unsigned(_news1494.count);
        for (var _i1495 in _news1494) {
            out.unsigned(_i1495);
            _a_Import_write(out, value.imports[_i1495]);
            {
                var _own1496 = RecordOut();
                _own1496.blank_bodies = true;
                _own1496.blank_locs = true;
                _own1496.pending_as_bytes = true;
                _a_Import_write(_own1496, value.imports[_i1495]);
                base.own("imports", interface_text(_own1496));
            }
        }
        base.count("imports" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("imports" + " whole", 0);
        out.unsigned(value.imports.count);
        for (var _i1495 in 0..value.imports.count) {
            _a_Import_write(out, value.imports[_i1495]);
            {
                var _own1497 = RecordOut();
                _own1497.blank_bodies = true;
                _own1497.blank_locs = true;
                _own1497.pending_as_bytes = true;
                _a_Import_write(_own1497, value.imports[_i1495]);
                base.own("imports", interface_text(_own1497));
            }
        }
    }
    base.stat("imports", out.values.count - _mark);
    _mark = out.values.count;
    var _seq1507 = base.ref_structs;
    ulong _bj1508 = 0;
    var _news1510 = Array<ulong>();
    var _patches1511 = Array<(ulong, ulong)>();
    for (var _i1512 in 0..value.structs.count) {
        if (_bj1508 < _seq1507.count
            and value.structs[_i1512] === _seq1507[_bj1508]
            and !value.extended_checked.contains(value.structs[_i1512].name)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_StructDef_write(scratch, value.structs[_i1512]);
                base.verify_same("s", _bj1508, scratch, value.structs[_i1512].name);
            }
            _bj1508 += 1;
        } else if (_bj1508 < _seq1507.count
            and !(value.structs[_i1512] === _seq1507[_bj1508])
            and _same_m_StructDef(value.structs[_i1512], _seq1507[_bj1508], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_StructDef_write(scratch, value.structs[_i1512]);
                base.verify_same("s", _bj1508, scratch, value.structs[_i1512].name);
            }
            _bj1508 += 1;
        } else if (_bj1508 < _seq1507.count and value.structs[_i1512].name == _seq1507[_bj1508].name) {
            _patches1511.append((_i1512, _bj1508));
            _bj1508 += 1;
        } else {
            _news1510.append(_i1512);
        }
    }
    if (_bj1508 == _seq1507.count) {
        out.unsigned(2);
        out.unsigned(_patches1511.count);
        for (var (_i1512, _b) in _patches1511) {
            ulong _before = out.values.count;
            out.text(value.structs[_i1512].name);
            out.unsigned(_b);
            _patch_s_write(out, value.structs[_i1512], base, _b);
            base.count("s patched", out.values.count - _before);
            {
                var _own1513 = RecordOut();
                _own1513.blank_bodies = true;
                _own1513.blank_locs = true;
                _own1513.pending_as_bytes = true;
                var _s1514 = value.structs[_i1512];
                var _methods1515 = _s1514.method_members;
                _s1514.method_members = Array<FunctionDef>();
                var _fields1516 = _s1514.field_members;
                var split__fields1516 = splits_fields(_s1514);
                if (split__fields1516) {
                    _s1514.field_members = Array<VariableDef>();
                }
                _m_StructDef_write(_own1513, _s1514);
                _s1514.method_members = _methods1515;
                _s1514.field_members = _fields1516;
                base.own_named("structs", _s1514.name, interface_text(_own1513));
                for (var _m1517 in _methods1515) {
                    var _own1518 = RecordOut();
                    _own1518.blank_bodies = true;
                    _own1518.blank_locs = true;
                    _own1518.pending_as_bytes = true;
                    _m_FunctionDef_write(_own1518, _m1517);
                    base.own_method("structs", _s1514.name, _m1517.name, interface_text(_own1518));
                }
                if (_s1514.is_value()) {
                    for (var _m1517 in _s1514.constructors) {
                        var _own1518 = RecordOut();
                        _own1518.blank_locs = true;
                        _own1518.pending_as_bytes = true;
                        _m_FunctionDef_write(_own1518, _m1517);
                        base.own_method("structs", _s1514.name, "__ctor", interface_text(_own1518));
                    }
                }
                if (split__fields1516) {
                    var _order1520 = StringBuilder();
                    for (var _f1519 in _fields1516) {
                        var _own1521 = RecordOut();
                        _own1521.blank_locs = true;
                        _m_VariableDef_write(_own1521, _f1519);
                        base.own_method("structs", _s1514.name, "." + _f1519.name, interface_text(_own1521));
                        _order1520.append(_f1519.name);
                        _order1520.append(",");
                    }
                    base.own_method("structs", _s1514.name, ".#order", _order1520.to_string());
                }
            }
        }
        out.unsigned(_news1510.count);
        for (var _i1512 in _news1510) {
            ulong _before = out.values.count;
            out.unsigned(_i1512);
            _m_StructDef_write(out, value.structs[_i1512]);
            base.count("s new", out.values.count - _before);
            {
                var _own1522 = RecordOut();
                _own1522.blank_bodies = true;
                _own1522.blank_locs = true;
                _own1522.pending_as_bytes = true;
                var _s1523 = value.structs[_i1512];
                var _methods1524 = _s1523.method_members;
                _s1523.method_members = Array<FunctionDef>();
                var _fields1525 = _s1523.field_members;
                var split__fields1525 = splits_fields(_s1523);
                if (split__fields1525) {
                    _s1523.field_members = Array<VariableDef>();
                }
                _m_StructDef_write(_own1522, _s1523);
                _s1523.method_members = _methods1524;
                _s1523.field_members = _fields1525;
                base.own_named("structs", _s1523.name, interface_text(_own1522));
                for (var _m1526 in _methods1524) {
                    var _own1527 = RecordOut();
                    _own1527.blank_bodies = true;
                    _own1527.blank_locs = true;
                    _own1527.pending_as_bytes = true;
                    _m_FunctionDef_write(_own1527, _m1526);
                    base.own_method("structs", _s1523.name, _m1526.name, interface_text(_own1527));
                }
                if (_s1523.is_value()) {
                    for (var _m1526 in _s1523.constructors) {
                        var _own1527 = RecordOut();
                        _own1527.blank_locs = true;
                        _own1527.pending_as_bytes = true;
                        _m_FunctionDef_write(_own1527, _m1526);
                        base.own_method("structs", _s1523.name, "__ctor", interface_text(_own1527));
                    }
                }
                if (split__fields1525) {
                    var _order1529 = StringBuilder();
                    for (var _f1528 in _fields1525) {
                        var _own1530 = RecordOut();
                        _own1530.blank_locs = true;
                        _m_VariableDef_write(_own1530, _f1528);
                        base.own_method("structs", _s1523.name, "." + _f1528.name, interface_text(_own1530));
                        _order1529.append(_f1528.name);
                        _order1529.append(",");
                    }
                    base.own_method("structs", _s1523.name, ".#order", _order1529.to_string());
                }
            }
        }
        base.count("s merged", 0);
    } else {
        out.unsigned(1);
        base.count("s by place", 0);
        var _struct_hits1506 = HashSet<long>();
        var _slots1509 = HashMap<String, long>();
        for (var _i1512 in 0.._seq1507.count) {
            if (!_slots1509.contains(_seq1507[_i1512].name)) {
                _slots1509[_seq1507[_i1512].name] = _i1512 as long;
            }
        }
        out.unsigned(value.structs.count);
        for (var _i1512 in 0..value.structs.count) {
            var _item1505 = value.structs[_i1512];
            var _slot = _slots1509.try_get(_item1505.name);
            long named = _slot.is_value() ? _slot.value() : -1;
            long at = -1;
            if (named >= 0
                and _seq1507[named as ulong] === _item1505
                and !value.extended_checked.contains(_item1505.name)) {
                at = named;
            }
            ulong _before = out.values.count;
            if (at >= 0) {
                _struct_hits1506.insert(at);
                out.unsigned((at as ulong) * 2 + 1);
            } else if (named >= 0) {
                _struct_hits1506.insert(named);
                out.unsigned(2);
                out.unsigned(named as ulong);
                _patch_s_write(out, _item1505, base, named as ulong);
                base.count("s patched", out.values.count - _before);
            } else {
                out.unsigned(0);
                _m_StructDef_write(out, _item1505);
                base.count("s new", out.values.count - _before);
            }
        }
        base.missed("s", "s", _struct_hits1506.count);
    }
    base.stat("structs", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1544 = Array<String>();
    for (var _item1539 in value.traits) {
        var scratch = base.scratch();
        _m_TraitDef_write(scratch, _item1539);
        _hs1544.append(base.hash_of(scratch));
    }
    var _seq1545 = base.sequence("traits");
    ulong _bj1546 = 0;
    var _news1547 = Array<ulong>();
    for (var _i1548 in 0.._hs1544.count) {
        if (_bj1546 < _seq1545.count and _hs1544[_i1548] == _seq1545[_bj1546]) {
            _bj1546 += 1;
        } else {
            _news1547.append(_i1548);
        }
    }
    if (_bj1546 == _seq1545.count) {
        out.unsigned(2);
        out.unsigned(_news1547.count);
        for (var _i1548 in _news1547) {
            out.unsigned(_i1548);
            _m_TraitDef_write(out, value.traits[_i1548]);
            {
                var _own1549 = RecordOut();
                _own1549.blank_bodies = false;
                _own1549.blank_locs = true;
                _own1549.pending_as_bytes = true;
                _m_TraitDef_write(_own1549, value.traits[_i1548]);
                base.own("traits", interface_text(_own1549));
            }
        }
        base.count("traits" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("traits" + " whole", 0);
        out.unsigned(value.traits.count);
        for (var _i1548 in 0..value.traits.count) {
            _m_TraitDef_write(out, value.traits[_i1548]);
            {
                var _own1550 = RecordOut();
                _own1550.blank_bodies = false;
                _own1550.blank_locs = true;
                _own1550.pending_as_bytes = true;
                _m_TraitDef_write(_own1550, value.traits[_i1548]);
                base.own("traits", interface_text(_own1550));
            }
        }
    }
    base.stat("traits", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1563 = Array<String>();
    for (var _item1558 in value.extensions) {
        var scratch = base.scratch();
        _m_ExtensionDef_write(scratch, _item1558);
        _hs1563.append(base.hash_of(scratch));
    }
    var _seq1564 = base.sequence("extensions");
    ulong _bj1565 = 0;
    var _news1566 = Array<ulong>();
    for (var _i1567 in 0.._hs1563.count) {
        if (_bj1565 < _seq1564.count and _hs1563[_i1567] == _seq1564[_bj1565]) {
            _bj1565 += 1;
        } else {
            _news1566.append(_i1567);
        }
    }
    if (_bj1565 == _seq1564.count) {
        out.unsigned(2);
        out.unsigned(_news1566.count);
        for (var _i1567 in _news1566) {
            out.unsigned(_i1567);
            _m_ExtensionDef_write(out, value.extensions[_i1567]);
            {
                var _own1568 = RecordOut();
                _own1568.blank_bodies = true;
                _own1568.blank_locs = true;
                _own1568.pending_as_bytes = true;
                _m_ExtensionDef_write(_own1568, value.extensions[_i1567]);
                base.own("extensions", interface_text(_own1568));
            }
        }
        base.count("extensions" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("extensions" + " whole", 0);
        out.unsigned(value.extensions.count);
        for (var _i1567 in 0..value.extensions.count) {
            _m_ExtensionDef_write(out, value.extensions[_i1567]);
            {
                var _own1569 = RecordOut();
                _own1569.blank_bodies = true;
                _own1569.blank_locs = true;
                _own1569.pending_as_bytes = true;
                _m_ExtensionDef_write(_own1569, value.extensions[_i1567]);
                base.own("extensions", interface_text(_own1569));
            }
        }
    }
    base.stat("extensions", out.values.count - _mark);
    _mark = out.values.count;
    var _seq1582 = base.ref_functions;
    ulong _bj1583 = 0;
    var _news1584 = Array<ulong>();
    var _changed1578 = Array<(ulong, ulong)>();
    for (var _i1585 in 0..value.functions.count) {
        if (_bj1583 < _seq1582.count and value.functions[_i1585] === _seq1582[_bj1583]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.functions[_i1585]);
                base.verify_same("functions", _bj1583, scratch);
            }
            _bj1583 += 1;
        } else if (_bj1583 < _seq1582.count and _same_m_FunctionDef(value.functions[_i1585], _seq1582[_bj1583], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.functions[_i1585]);
                base.verify_same("functions", _bj1583, scratch);
            }
            _bj1583 += 1;
        } else if (_bj1583 < _seq1582.count and value.functions[_i1585].name == _seq1582[_bj1583].name) {
            _changed1578.append((_i1585, _bj1583));
            _bj1583 += 1;
        } else {
            _news1584.append(_i1585);
        }
    }
    if (_bj1583 == _seq1582.count) {
        out.unsigned(2);
        out.unsigned(_changed1578.count);
        for (var (_i1585, _b) in _changed1578) {
            out.text(value.functions[_i1585].name);
            out.unsigned(_b);
            _m_FunctionDef_write(out, value.functions[_i1585]);
            {
                var _own1586 = RecordOut();
                _own1586.blank_bodies = true;
                _own1586.blank_locs = true;
                _own1586.pending_as_bytes = true;
                _m_FunctionDef_write(_own1586, value.functions[_i1585]);
                base.own_function("functions", value.functions[_i1585], interface_text(_own1586));
            }
        }
        base.count("functions" + " changed", _changed1578.count);
        out.unsigned(_news1584.count);
        for (var _i1585 in _news1584) {
            out.unsigned(_i1585);
            _m_FunctionDef_write(out, value.functions[_i1585]);
            {
                var _own1587 = RecordOut();
                _own1587.blank_bodies = true;
                _own1587.blank_locs = true;
                _own1587.pending_as_bytes = true;
                _m_FunctionDef_write(_own1587, value.functions[_i1585]);
                base.own_function("functions", value.functions[_i1585], interface_text(_own1587));
            }
        }
        base.count("functions" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("functions" + " whole", 0);
        out.unsigned(value.functions.count);
        for (var _i1585 in 0..value.functions.count) {
            _m_FunctionDef_write(out, value.functions[_i1585]);
            {
                var _own1588 = RecordOut();
                _own1588.blank_bodies = true;
                _own1588.blank_locs = true;
                _own1588.pending_as_bytes = true;
                _m_FunctionDef_write(_own1588, value.functions[_i1585]);
                base.own_function("functions", value.functions[_i1585], interface_text(_own1588));
            }
        }
    }
    base.stat("functions", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1601 = Array<String>();
    for (var _item1596 in value.externs) {
        var scratch = base.scratch();
        _m_ExternDef_write(scratch, _item1596);
        _hs1601.append(base.hash_of(scratch));
    }
    var _seq1602 = base.sequence("externs");
    ulong _bj1603 = 0;
    var _news1604 = Array<ulong>();
    for (var _i1605 in 0.._hs1601.count) {
        if (_bj1603 < _seq1602.count and _hs1601[_i1605] == _seq1602[_bj1603]) {
            _bj1603 += 1;
        } else {
            _news1604.append(_i1605);
        }
    }
    if (_bj1603 == _seq1602.count) {
        out.unsigned(2);
        out.unsigned(_news1604.count);
        for (var _i1605 in _news1604) {
            out.unsigned(_i1605);
            _m_ExternDef_write(out, value.externs[_i1605]);
            {
                var _own1606 = RecordOut();
                _own1606.blank_bodies = true;
                _own1606.blank_locs = true;
                _own1606.pending_as_bytes = true;
                _m_ExternDef_write(_own1606, value.externs[_i1605]);
                base.own("externs", interface_text(_own1606));
            }
        }
        base.count("externs" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("externs" + " whole", 0);
        out.unsigned(value.externs.count);
        for (var _i1605 in 0..value.externs.count) {
            _m_ExternDef_write(out, value.externs[_i1605]);
            {
                var _own1607 = RecordOut();
                _own1607.blank_bodies = true;
                _own1607.blank_locs = true;
                _own1607.pending_as_bytes = true;
                _m_ExternDef_write(_own1607, value.externs[_i1605]);
                base.own("externs", interface_text(_own1607));
            }
        }
    }
    base.stat("externs", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1620 = Array<String>();
    for (var _item1615 in value.globals) {
        var scratch = base.scratch();
        _m_VariableDef_write(scratch, _item1615);
        _hs1620.append(base.hash_of(scratch));
    }
    var _seq1621 = base.sequence("globals");
    ulong _bj1622 = 0;
    var _news1623 = Array<ulong>();
    for (var _i1624 in 0.._hs1620.count) {
        if (_bj1622 < _seq1621.count and _hs1620[_i1624] == _seq1621[_bj1622]) {
            _bj1622 += 1;
        } else {
            _news1623.append(_i1624);
        }
    }
    if (_bj1622 == _seq1621.count) {
        out.unsigned(2);
        out.unsigned(_news1623.count);
        for (var _i1624 in _news1623) {
            out.unsigned(_i1624);
            _m_VariableDef_write(out, value.globals[_i1624]);
            {
                var _own1625 = RecordOut();
                _own1625.blank_bodies = true;
                _own1625.blank_locs = true;
                _own1625.pending_as_bytes = true;
                _m_VariableDef_write(_own1625, value.globals[_i1624]);
                base.own("globals", interface_text(_own1625));
            }
        }
        base.count("globals" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("globals" + " whole", 0);
        out.unsigned(value.globals.count);
        for (var _i1624 in 0..value.globals.count) {
            _m_VariableDef_write(out, value.globals[_i1624]);
            {
                var _own1626 = RecordOut();
                _own1626.blank_bodies = true;
                _own1626.blank_locs = true;
                _own1626.pending_as_bytes = true;
                _m_VariableDef_write(_own1626, value.globals[_i1624]);
                base.own("globals", interface_text(_own1626));
            }
        }
    }
    base.stat("globals", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1639 = Array<String>();
    for (var _item1634 in value.static_blocks) {
        var scratch = base.scratch();
        _m_ModuleStaticBlock_write(scratch, _item1634);
        _hs1639.append(base.hash_of(scratch));
    }
    var _seq1640 = base.sequence("static_blocks");
    ulong _bj1641 = 0;
    var _news1642 = Array<ulong>();
    for (var _i1643 in 0.._hs1639.count) {
        if (_bj1641 < _seq1640.count and _hs1639[_i1643] == _seq1640[_bj1641]) {
            _bj1641 += 1;
        } else {
            _news1642.append(_i1643);
        }
    }
    if (_bj1641 == _seq1640.count) {
        out.unsigned(2);
        out.unsigned(_news1642.count);
        for (var _i1643 in _news1642) {
            out.unsigned(_i1643);
            _m_ModuleStaticBlock_write(out, value.static_blocks[_i1643]);
            {
                var _own1644 = RecordOut();
                _own1644.blank_bodies = true;
                _own1644.blank_locs = true;
                _own1644.pending_as_bytes = true;
                _m_ModuleStaticBlock_write(_own1644, value.static_blocks[_i1643]);
                base.own("static_blocks", interface_text(_own1644));
            }
        }
        base.count("static_blocks" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("static_blocks" + " whole", 0);
        out.unsigned(value.static_blocks.count);
        for (var _i1643 in 0..value.static_blocks.count) {
            _m_ModuleStaticBlock_write(out, value.static_blocks[_i1643]);
            {
                var _own1645 = RecordOut();
                _own1645.blank_bodies = true;
                _own1645.blank_locs = true;
                _own1645.pending_as_bytes = true;
                _m_ModuleStaticBlock_write(_own1645, value.static_blocks[_i1643]);
                base.own("static_blocks", interface_text(_own1645));
            }
        }
    }
    base.stat("static_blocks", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1658 = Array<String>();
    for (var _item1653 in value.enums) {
        var scratch = base.scratch();
        _m_EnumDef_write(scratch, _item1653);
        _hs1658.append(base.hash_of(scratch));
    }
    var _seq1659 = base.sequence("enums");
    ulong _bj1660 = 0;
    var _news1661 = Array<ulong>();
    for (var _i1662 in 0.._hs1658.count) {
        if (_bj1660 < _seq1659.count and _hs1658[_i1662] == _seq1659[_bj1660]) {
            _bj1660 += 1;
        } else {
            _news1661.append(_i1662);
        }
    }
    if (_bj1660 == _seq1659.count) {
        out.unsigned(2);
        out.unsigned(_news1661.count);
        for (var _i1662 in _news1661) {
            out.unsigned(_i1662);
            _m_EnumDef_write(out, value.enums[_i1662]);
            {
                var _own1663 = RecordOut();
                _own1663.blank_bodies = true;
                _own1663.blank_locs = true;
                _own1663.pending_as_bytes = true;
                _m_EnumDef_write(_own1663, value.enums[_i1662]);
                base.own_named("enums", value.enums[_i1662].name, interface_text(_own1663));
            }
        }
        base.count("enums" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("enums" + " whole", 0);
        out.unsigned(value.enums.count);
        for (var _i1662 in 0..value.enums.count) {
            _m_EnumDef_write(out, value.enums[_i1662]);
            {
                var _own1664 = RecordOut();
                _own1664.blank_bodies = true;
                _own1664.blank_locs = true;
                _own1664.pending_as_bytes = true;
                _m_EnumDef_write(_own1664, value.enums[_i1662]);
                base.own_named("enums", value.enums[_i1662].name, interface_text(_own1664));
            }
        }
    }
    base.stat("enums", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1677 = Array<String>();
    for (var _item1672 in value.struct_specs) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item1672);
        _hs1677.append(base.hash_of(scratch));
    }
    var _seq1678 = base.sequence("struct_specs");
    ulong _bj1679 = 0;
    var _news1680 = Array<ulong>();
    for (var _i1681 in 0.._hs1677.count) {
        if (_bj1679 < _seq1678.count and _hs1677[_i1681] == _seq1678[_bj1679]) {
            _bj1679 += 1;
        } else {
            _news1680.append(_i1681);
        }
    }
    if (_bj1679 == _seq1678.count) {
        out.unsigned(2);
        out.unsigned(_news1680.count);
        for (var _i1681 in _news1680) {
            out.unsigned(_i1681);
            _m_TypeName_write(out, value.struct_specs[_i1681]);
            {
                var _own1682 = RecordOut();
                _own1682.blank_bodies = true;
                _own1682.blank_locs = true;
                _own1682.pending_as_bytes = true;
                _m_TypeName_write(_own1682, value.struct_specs[_i1681]);
                base.own("struct_specs", interface_text(_own1682));
            }
        }
        base.count("struct_specs" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("struct_specs" + " whole", 0);
        out.unsigned(value.struct_specs.count);
        for (var _i1681 in 0..value.struct_specs.count) {
            _m_TypeName_write(out, value.struct_specs[_i1681]);
            {
                var _own1683 = RecordOut();
                _own1683.blank_bodies = true;
                _own1683.blank_locs = true;
                _own1683.pending_as_bytes = true;
                _m_TypeName_write(_own1683, value.struct_specs[_i1681]);
                base.own("struct_specs", interface_text(_own1683));
            }
        }
    }
    base.stat("struct_specs", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1696 = Array<String>();
    for (var _item1691 in value.func_specs) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item1691);
        _hs1696.append(base.hash_of(scratch));
    }
    var _seq1697 = base.sequence("func_specs");
    ulong _bj1698 = 0;
    var _news1699 = Array<ulong>();
    for (var _i1700 in 0.._hs1696.count) {
        if (_bj1698 < _seq1697.count and _hs1696[_i1700] == _seq1697[_bj1698]) {
            _bj1698 += 1;
        } else {
            _news1699.append(_i1700);
        }
    }
    if (_bj1698 == _seq1697.count) {
        out.unsigned(2);
        out.unsigned(_news1699.count);
        for (var _i1700 in _news1699) {
            out.unsigned(_i1700);
            _m_TypeName_write(out, value.func_specs[_i1700]);
            {
                var _own1701 = RecordOut();
                _own1701.blank_bodies = true;
                _own1701.blank_locs = true;
                _own1701.pending_as_bytes = true;
                _m_TypeName_write(_own1701, value.func_specs[_i1700]);
                base.own("func_specs", interface_text(_own1701));
            }
        }
        base.count("func_specs" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("func_specs" + " whole", 0);
        out.unsigned(value.func_specs.count);
        for (var _i1700 in 0..value.func_specs.count) {
            _m_TypeName_write(out, value.func_specs[_i1700]);
            {
                var _own1702 = RecordOut();
                _own1702.blank_bodies = true;
                _own1702.blank_locs = true;
                _own1702.pending_as_bytes = true;
                _m_TypeName_write(_own1702, value.func_specs[_i1700]);
                base.own("func_specs", interface_text(_own1702));
            }
        }
    }
    base.stat("func_specs", out.values.count - _mark);
    _mark = out.values.count;
    var _hits1714 = HashSet<long>();
    out.unsigned(value.type_aliases.count);
    for (var _item1710 in value.type_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1710);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed("type_aliases", hash);
        if (at >= 0) {
            _hits1714.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_TypeAliasDef_write(out, _item1710);
        }
    }
    base.missed("type_aliases", "type_aliases", _hits1714.count);
    base.stat("type_aliases", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1724 = Array<String>();
    for (var _item1719 in value.withheld) {
        var scratch = base.scratch();
        _m_Withheld_write(scratch, _item1719);
        _hs1724.append(base.hash_of(scratch));
    }
    var _seq1725 = base.sequence("withheld");
    ulong _bj1726 = 0;
    var _news1727 = Array<ulong>();
    for (var _i1728 in 0.._hs1724.count) {
        if (_bj1726 < _seq1725.count and _hs1724[_i1728] == _seq1725[_bj1726]) {
            _bj1726 += 1;
        } else {
            _news1727.append(_i1728);
        }
    }
    if (_bj1726 == _seq1725.count) {
        out.unsigned(2);
        out.unsigned(_news1727.count);
        for (var _i1728 in _news1727) {
            out.unsigned(_i1728);
            _m_Withheld_write(out, value.withheld[_i1728]);
            {
                var _own1729 = RecordOut();
                _own1729.blank_bodies = true;
                _own1729.blank_locs = true;
                _own1729.pending_as_bytes = true;
                _m_Withheld_write(_own1729, value.withheld[_i1728]);
                base.own("withheld", interface_text(_own1729));
            }
        }
        base.count("withheld" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("withheld" + " whole", 0);
        out.unsigned(value.withheld.count);
        for (var _i1728 in 0..value.withheld.count) {
            _m_Withheld_write(out, value.withheld[_i1728]);
            {
                var _own1730 = RecordOut();
                _own1730.blank_bodies = true;
                _own1730.blank_locs = true;
                _own1730.pending_as_bytes = true;
                _m_Withheld_write(_own1730, value.withheld[_i1728]);
                base.own("withheld", interface_text(_own1730));
            }
        }
    }
    base.stat("withheld", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1743 = Array<String>();
    for (var _item1738 in value.properties) {
        var scratch = base.scratch();
        _m_PropertyDef_write(scratch, _item1738);
        _hs1743.append(base.hash_of(scratch));
    }
    var _seq1744 = base.sequence("properties");
    ulong _bj1745 = 0;
    var _news1746 = Array<ulong>();
    for (var _i1747 in 0.._hs1743.count) {
        if (_bj1745 < _seq1744.count and _hs1743[_i1747] == _seq1744[_bj1745]) {
            _bj1745 += 1;
        } else {
            _news1746.append(_i1747);
        }
    }
    if (_bj1745 == _seq1744.count) {
        out.unsigned(2);
        out.unsigned(_news1746.count);
        for (var _i1747 in _news1746) {
            out.unsigned(_i1747);
            _m_PropertyDef_write(out, value.properties[_i1747]);
            {
                var _own1748 = RecordOut();
                _own1748.blank_bodies = true;
                _own1748.blank_locs = true;
                _own1748.pending_as_bytes = true;
                _m_PropertyDef_write(_own1748, value.properties[_i1747]);
                base.own("properties", interface_text(_own1748));
            }
        }
        base.count("properties" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("properties" + " whole", 0);
        out.unsigned(value.properties.count);
        for (var _i1747 in 0..value.properties.count) {
            _m_PropertyDef_write(out, value.properties[_i1747]);
            {
                var _own1749 = RecordOut();
                _own1749.blank_bodies = true;
                _own1749.blank_locs = true;
                _own1749.pending_as_bytes = true;
                _m_PropertyDef_write(_own1749, value.properties[_i1747]);
                base.own("properties", interface_text(_own1749));
            }
        }
    }
    base.stat("properties", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1762 = Array<String>();
    for (var _item1757 in value.type_uses) {
        var scratch = base.scratch();
        _m_TypeUse_write(scratch, _item1757);
        _hs1762.append(base.hash_of(scratch));
    }
    var _seq1763 = base.sequence("type_uses");
    ulong _bj1764 = 0;
    var _news1765 = Array<ulong>();
    for (var _i1766 in 0.._hs1762.count) {
        if (_bj1764 < _seq1763.count and _hs1762[_i1766] == _seq1763[_bj1764]) {
            _bj1764 += 1;
        } else {
            _news1765.append(_i1766);
        }
    }
    if (_bj1764 == _seq1763.count) {
        out.unsigned(2);
        out.unsigned(_news1765.count);
        for (var _i1766 in _news1765) {
            out.unsigned(_i1766);
            _m_TypeUse_write(out, value.type_uses[_i1766]);
            {
                var _own1767 = RecordOut();
                _own1767.blank_bodies = true;
                _own1767.blank_locs = true;
                _own1767.pending_as_bytes = true;
                _m_TypeUse_write(_own1767, value.type_uses[_i1766]);
                base.own("type_uses", interface_text(_own1767));
            }
        }
        base.count("type_uses" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("type_uses" + " whole", 0);
        out.unsigned(value.type_uses.count);
        for (var _i1766 in 0..value.type_uses.count) {
            _m_TypeUse_write(out, value.type_uses[_i1766]);
            {
                var _own1768 = RecordOut();
                _own1768.blank_bodies = true;
                _own1768.blank_locs = true;
                _own1768.pending_as_bytes = true;
                _m_TypeUse_write(_own1768, value.type_uses[_i1766]);
                base.own("type_uses", interface_text(_own1768));
            }
        }
    }
    base.stat("type_uses", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1781 = Array<String>();
    for (var _item1776 in value.use_contexts) {
        var scratch = base.scratch();
        _m_UseContext_write(scratch, _item1776);
        _hs1781.append(base.hash_of(scratch));
    }
    var _seq1782 = base.sequence("use_contexts");
    ulong _bj1783 = 0;
    var _news1784 = Array<ulong>();
    for (var _i1785 in 0.._hs1781.count) {
        if (_bj1783 < _seq1782.count and _hs1781[_i1785] == _seq1782[_bj1783]) {
            _bj1783 += 1;
        } else {
            _news1784.append(_i1785);
        }
    }
    if (_bj1783 == _seq1782.count) {
        out.unsigned(2);
        out.unsigned(_news1784.count);
        for (var _i1785 in _news1784) {
            out.unsigned(_i1785);
            _m_UseContext_write(out, value.use_contexts[_i1785]);
            {
                var _own1786 = RecordOut();
                _own1786.blank_bodies = true;
                _own1786.blank_locs = true;
                _own1786.pending_as_bytes = true;
                _m_UseContext_write(_own1786, value.use_contexts[_i1785]);
                base.own("use_contexts", interface_text(_own1786));
            }
        }
        base.count("use_contexts" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("use_contexts" + " whole", 0);
        out.unsigned(value.use_contexts.count);
        for (var _i1785 in 0..value.use_contexts.count) {
            _m_UseContext_write(out, value.use_contexts[_i1785]);
            {
                var _own1787 = RecordOut();
                _own1787.blank_bodies = true;
                _own1787.blank_locs = true;
                _own1787.pending_as_bytes = true;
                _m_UseContext_write(_own1787, value.use_contexts[_i1785]);
                base.own("use_contexts", interface_text(_own1787));
            }
        }
    }
    base.stat("use_contexts", out.values.count - _mark);
    _mark = out.values.count;
    var _n1797 = base.size("literal_args");
    var _scratch1796 = base.scratch();
    if (value.literal_args.count >= _n1797) {
        for (var _i1798 in 0.._n1797) {
            var (_t1799, _t1800, _t1801) = value.literal_args[_i1798];
            _scratch1796.loc(_t1799);
            _scratch1796.unsigned(_t1800);
            _scratch1796.loc(_t1801);
        }
    }
    if (value.literal_args.count >= _n1797 and base.same_list("literal_args", _scratch1796)) {
        out.unsigned(1);
        out.unsigned(_n1797);
        out.unsigned(value.literal_args.count - _n1797);
        for (var _i1798 in _n1797..value.literal_args.count) {
            var (_t1802, _t1803, _t1804) = value.literal_args[_i1798];
            out.loc(_t1802);
            out.unsigned(_t1803);
            out.loc(_t1804);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.literal_args.count);
        for (var _item1805 in value.literal_args) {
            var (_t1806, _t1807, _t1808) = _item1805;
            out.loc(_t1806);
            out.unsigned(_t1807);
            out.loc(_t1808);
        }
        base.count("literal_args whole", 0);
    }
    base.stat("literal_args", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1831 = Array<String>();
    for (var _item1826 in value.constrained_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1826);
        _hs1831.append(base.hash_of(scratch));
    }
    var _seq1832 = base.sequence("constrained_aliases");
    ulong _bj1833 = 0;
    var _news1834 = Array<ulong>();
    for (var _i1835 in 0.._hs1831.count) {
        if (_bj1833 < _seq1832.count and _hs1831[_i1835] == _seq1832[_bj1833]) {
            _bj1833 += 1;
        } else {
            _news1834.append(_i1835);
        }
    }
    if (_bj1833 == _seq1832.count) {
        out.unsigned(2);
        out.unsigned(_news1834.count);
        for (var _i1835 in _news1834) {
            out.unsigned(_i1835);
            _m_TypeAliasDef_write(out, value.constrained_aliases[_i1835]);
            {
                var _own1836 = RecordOut();
                _own1836.blank_bodies = true;
                _own1836.blank_locs = true;
                _own1836.pending_as_bytes = true;
                _m_TypeAliasDef_write(_own1836, value.constrained_aliases[_i1835]);
                base.own("constrained_aliases", interface_text(_own1836));
            }
        }
        base.count("constrained_aliases" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("constrained_aliases" + " whole", 0);
        out.unsigned(value.constrained_aliases.count);
        for (var _i1835 in 0..value.constrained_aliases.count) {
            _m_TypeAliasDef_write(out, value.constrained_aliases[_i1835]);
            {
                var _own1837 = RecordOut();
                _own1837.blank_bodies = true;
                _own1837.blank_locs = true;
                _own1837.pending_as_bytes = true;
                _m_TypeAliasDef_write(_own1837, value.constrained_aliases[_i1835]);
                base.own("constrained_aliases", interface_text(_own1837));
            }
        }
    }
    base.stat("constrained_aliases", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1850 = Array<String>();
    for (var _item1845 in value.trait_types) {
        var scratch = base.scratch();
        _m_TraitType_write(scratch, _item1845);
        _hs1850.append(base.hash_of(scratch));
    }
    var _seq1851 = base.sequence("trait_types");
    ulong _bj1852 = 0;
    var _news1853 = Array<ulong>();
    for (var _i1854 in 0.._hs1850.count) {
        if (_bj1852 < _seq1851.count and _hs1850[_i1854] == _seq1851[_bj1852]) {
            _bj1852 += 1;
        } else {
            _news1853.append(_i1854);
        }
    }
    if (_bj1852 == _seq1851.count) {
        out.unsigned(2);
        out.unsigned(_news1853.count);
        for (var _i1854 in _news1853) {
            out.unsigned(_i1854);
            _m_TraitType_write(out, value.trait_types[_i1854]);
            {
                var _own1855 = RecordOut();
                _own1855.blank_bodies = true;
                _own1855.blank_locs = true;
                _own1855.pending_as_bytes = true;
                _m_TraitType_write(_own1855, value.trait_types[_i1854]);
                base.own("trait_types", interface_text(_own1855));
            }
        }
        base.count("trait_types" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("trait_types" + " whole", 0);
        out.unsigned(value.trait_types.count);
        for (var _i1854 in 0..value.trait_types.count) {
            _m_TraitType_write(out, value.trait_types[_i1854]);
            {
                var _own1856 = RecordOut();
                _own1856.blank_bodies = true;
                _own1856.blank_locs = true;
                _own1856.pending_as_bytes = true;
                _m_TraitType_write(_own1856, value.trait_types[_i1854]);
                base.own("trait_types", interface_text(_own1856));
            }
        }
    }
    base.stat("trait_types", out.values.count - _mark);
    _mark = out.values.count;
    out.unsigned(value.conversions.count);
    for (var _item1864 in value.conversions) {
        _m_Conversion_write(out, _item1864);
    }
    for (var _conv1865 in value.conversions) {
        var _own1866 = RecordOut();
        _own1866.blank_locs = true;
        _m_Conversion_write(_own1866, _conv1865);
        var _h = interface_text(_own1866);
        if (base.find_hashed("conversions", _h) < 0) {
            base.own("conversions", _h);
        }
    }
    base.stat("conversions", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept1874 = 0;
    var _news1875 = Map<String, Array<String>>();
    for (var (_key1871, _) in value.overload_sets) {
        var _kscratch1872 = base.scratch();
        _kscratch1872.text(_key1871);
        var _vscratch1873 = base.scratch();
        _vscratch1873.unsigned(value.overload_sets[_key1871].count);
        for (var _item1876 in value.overload_sets[_key1871]) {
            _vscratch1873.text(_item1876);
        }
        var _had = base.entry("overload_sets", _kscratch1872, _vscratch1873);
        if (_had >= 0) {
            _kept1874 += 1;
        }
        if (_had != 1) {
            _news1875[_key1871] = value.overload_sets[_key1871];
        }
    }
    if (_kept1874 == base.size("overload_sets")) {
        out.unsigned(1);
        var _keys1878 = Array<(u8[], u8[], String)>();
        for (var (_key1877, _) in _news1875) {
            var _scratch1879 = out.scratch();
            _scratch1879.text(_key1877);
            var _vscratch1881 = out.scratch();
            _vscratch1881.unsigned(_news1875[_key1877].count);
            for (var _item1882 in _news1875[_key1877]) {
                _vscratch1881.text(_item1882);
            }
            _keys1878.append((_scratch1879.finish(), _vscratch1881.finish(), _key1877));
        }
        _keys1878.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1878.count);
        for (var (_bytes1880, _, _key1877) in _keys1878) {
            out.text(_key1877);
            out.unsigned(_news1875[_key1877].count);
            for (var _item1883 in _news1875[_key1877]) {
                out.text(_item1883);
            }
        }
        for (var (_okey1884, _) in _news1875) {
            var _own1885 = RecordOut();
            _own1885.blank_bodies = true;
            _own1885.blank_locs = true;
            _own1885.pending_as_bytes = true;
            _own1885.text(_okey1884);
            _own1885.unsigned(_news1875[_okey1884].count);
            for (var _item1886 in _news1875[_okey1884]) {
                _own1885.text(_item1886);
            }
            base.own("overload_sets", interface_text(_own1885));
        }
    } else {
        out.unsigned(0);
        var _keys1888 = Array<(u8[], u8[], String)>();
        for (var (_key1887, _) in value.overload_sets) {
            var _scratch1889 = out.scratch();
            _scratch1889.text(_key1887);
            var _vscratch1891 = out.scratch();
            _vscratch1891.unsigned(value.overload_sets[_key1887].count);
            for (var _item1892 in value.overload_sets[_key1887]) {
                _vscratch1891.text(_item1892);
            }
            _keys1888.append((_scratch1889.finish(), _vscratch1891.finish(), _key1887));
        }
        _keys1888.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1888.count);
        for (var (_bytes1890, _, _key1887) in _keys1888) {
            out.text(_key1887);
            out.unsigned(value.overload_sets[_key1887].count);
            for (var _item1893 in value.overload_sets[_key1887]) {
                out.text(_item1893);
            }
        }
        for (var (_okey1894, _) in value.overload_sets) {
            var _own1895 = RecordOut();
            _own1895.blank_bodies = true;
            _own1895.blank_locs = true;
            _own1895.pending_as_bytes = true;
            _own1895.text(_okey1894);
            _own1895.unsigned(value.overload_sets[_okey1894].count);
            for (var _item1896 in value.overload_sets[_okey1894]) {
                _own1895.text(_item1896);
            }
            base.own("overload_sets", interface_text(_own1895));
        }
        base.count("overload_sets whole", 0);
    }
    base.stat("overload_sets", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept1914 = 0;
    var _news1915 = Map<String, Array<Array<String>>>();
    for (var (_key1911, _) in value.overload_unions) {
        var _kscratch1912 = base.scratch();
        _kscratch1912.text(_key1911);
        var _vscratch1913 = base.scratch();
        _vscratch1913.unsigned(value.overload_unions[_key1911].count);
        for (var _item1916 in value.overload_unions[_key1911]) {
            _vscratch1913.unsigned(_item1916.count);
            for (var _item1917 in _item1916) {
                _vscratch1913.text(_item1917);
            }
        }
        var _had = base.entry("overload_unions", _kscratch1912, _vscratch1913);
        if (_had >= 0) {
            _kept1914 += 1;
        }
        if (_had != 1) {
            _news1915[_key1911] = value.overload_unions[_key1911];
        }
    }
    if (_kept1914 == base.size("overload_unions")) {
        out.unsigned(1);
        var _keys1919 = Array<(u8[], u8[], String)>();
        for (var (_key1918, _) in _news1915) {
            var _scratch1920 = out.scratch();
            _scratch1920.text(_key1918);
            var _vscratch1922 = out.scratch();
            _vscratch1922.unsigned(_news1915[_key1918].count);
            for (var _item1923 in _news1915[_key1918]) {
                _vscratch1922.unsigned(_item1923.count);
                for (var _item1924 in _item1923) {
                    _vscratch1922.text(_item1924);
                }
            }
            _keys1919.append((_scratch1920.finish(), _vscratch1922.finish(), _key1918));
        }
        _keys1919.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1919.count);
        for (var (_bytes1921, _, _key1918) in _keys1919) {
            out.text(_key1918);
            out.unsigned(_news1915[_key1918].count);
            for (var _item1925 in _news1915[_key1918]) {
                out.unsigned(_item1925.count);
                for (var _item1926 in _item1925) {
                    out.text(_item1926);
                }
            }
        }
        for (var (_okey1927, _) in _news1915) {
            var _own1928 = RecordOut();
            _own1928.blank_bodies = true;
            _own1928.blank_locs = true;
            _own1928.pending_as_bytes = true;
            _own1928.text(_okey1927);
            _own1928.unsigned(_news1915[_okey1927].count);
            for (var _item1929 in _news1915[_okey1927]) {
                _own1928.unsigned(_item1929.count);
                for (var _item1930 in _item1929) {
                    _own1928.text(_item1930);
                }
            }
            base.own("overload_unions", interface_text(_own1928));
        }
    } else {
        out.unsigned(0);
        var _keys1932 = Array<(u8[], u8[], String)>();
        for (var (_key1931, _) in value.overload_unions) {
            var _scratch1933 = out.scratch();
            _scratch1933.text(_key1931);
            var _vscratch1935 = out.scratch();
            _vscratch1935.unsigned(value.overload_unions[_key1931].count);
            for (var _item1936 in value.overload_unions[_key1931]) {
                _vscratch1935.unsigned(_item1936.count);
                for (var _item1937 in _item1936) {
                    _vscratch1935.text(_item1937);
                }
            }
            _keys1932.append((_scratch1933.finish(), _vscratch1935.finish(), _key1931));
        }
        _keys1932.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1932.count);
        for (var (_bytes1934, _, _key1931) in _keys1932) {
            out.text(_key1931);
            out.unsigned(value.overload_unions[_key1931].count);
            for (var _item1938 in value.overload_unions[_key1931]) {
                out.unsigned(_item1938.count);
                for (var _item1939 in _item1938) {
                    out.text(_item1939);
                }
            }
        }
        for (var (_okey1940, _) in value.overload_unions) {
            var _own1941 = RecordOut();
            _own1941.blank_bodies = true;
            _own1941.blank_locs = true;
            _own1941.pending_as_bytes = true;
            _own1941.text(_okey1940);
            _own1941.unsigned(value.overload_unions[_okey1940].count);
            for (var _item1942 in value.overload_unions[_okey1940]) {
                _own1941.unsigned(_item1942.count);
                for (var _item1943 in _item1942) {
                    _own1941.text(_item1943);
                }
            }
            base.own("overload_unions", interface_text(_own1941));
        }
        base.count("overload_unions whole", 0);
    }
    base.stat("overload_unions", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept1966 = 0;
    var _news1967 = Map<String, Map<String, Array<String>>>();
    for (var (_key1963, _) in value.method_overload_sets) {
        var _kscratch1964 = base.scratch();
        _kscratch1964.text(_key1963);
        var _vscratch1965 = base.scratch();
        var _keys1969 = Array<(u8[], u8[], String)>();
        for (var (_key1968, _) in value.method_overload_sets[_key1963]) {
            var _scratch1970 = _vscratch1965.scratch();
            _scratch1970.text(_key1968);
            var _vscratch1972 = _vscratch1965.scratch();
            _vscratch1972.unsigned(value.method_overload_sets[_key1963][_key1968].count);
            for (var _item1973 in value.method_overload_sets[_key1963][_key1968]) {
                _vscratch1972.text(_item1973);
            }
            _keys1969.append((_scratch1970.finish(), _vscratch1972.finish(), _key1968));
        }
        _keys1969.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        _vscratch1965.unsigned(_keys1969.count);
        for (var (_bytes1971, _, _key1968) in _keys1969) {
            _vscratch1965.text(_key1968);
            _vscratch1965.unsigned(value.method_overload_sets[_key1963][_key1968].count);
            for (var _item1974 in value.method_overload_sets[_key1963][_key1968]) {
                _vscratch1965.text(_item1974);
            }
        }
        var _had = base.entry("method_overload_sets", _kscratch1964, _vscratch1965);
        if (_had >= 0) {
            _kept1966 += 1;
        }
        if (_had != 1) {
            _news1967[_key1963] = value.method_overload_sets[_key1963];
        }
    }
    if (_kept1966 == base.size("method_overload_sets")) {
        out.unsigned(1);
        var _keys1976 = Array<(u8[], u8[], String)>();
        for (var (_key1975, _) in _news1967) {
            var _scratch1977 = out.scratch();
            _scratch1977.text(_key1975);
            var _vscratch1979 = out.scratch();
            var _keys1981 = Array<(u8[], u8[], String)>();
            for (var (_key1980, _) in _news1967[_key1975]) {
                var _scratch1982 = _vscratch1979.scratch();
                _scratch1982.text(_key1980);
                var _vscratch1984 = _vscratch1979.scratch();
                _vscratch1984.unsigned(_news1967[_key1975][_key1980].count);
                for (var _item1985 in _news1967[_key1975][_key1980]) {
                    _vscratch1984.text(_item1985);
                }
                _keys1981.append((_scratch1982.finish(), _vscratch1984.finish(), _key1980));
            }
            _keys1981.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            _vscratch1979.unsigned(_keys1981.count);
            for (var (_bytes1983, _, _key1980) in _keys1981) {
                _vscratch1979.text(_key1980);
                _vscratch1979.unsigned(_news1967[_key1975][_key1980].count);
                for (var _item1986 in _news1967[_key1975][_key1980]) {
                    _vscratch1979.text(_item1986);
                }
            }
            _keys1976.append((_scratch1977.finish(), _vscratch1979.finish(), _key1975));
        }
        _keys1976.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1976.count);
        for (var (_bytes1978, _, _key1975) in _keys1976) {
            out.text(_key1975);
            var _keys1988 = Array<(u8[], u8[], String)>();
            for (var (_key1987, _) in _news1967[_key1975]) {
                var _scratch1989 = out.scratch();
                _scratch1989.text(_key1987);
                var _vscratch1991 = out.scratch();
                _vscratch1991.unsigned(_news1967[_key1975][_key1987].count);
                for (var _item1992 in _news1967[_key1975][_key1987]) {
                    _vscratch1991.text(_item1992);
                }
                _keys1988.append((_scratch1989.finish(), _vscratch1991.finish(), _key1987));
            }
            _keys1988.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            out.unsigned(_keys1988.count);
            for (var (_bytes1990, _, _key1987) in _keys1988) {
                out.text(_key1987);
                out.unsigned(_news1967[_key1975][_key1987].count);
                for (var _item1993 in _news1967[_key1975][_key1987]) {
                    out.text(_item1993);
                }
            }
        }
        for (var (_okey1994, _) in _news1967) {
            var _own1995 = RecordOut();
            _own1995.blank_bodies = true;
            _own1995.blank_locs = true;
            _own1995.pending_as_bytes = true;
            _own1995.text(_okey1994);
            var _keys1997 = Array<(u8[], u8[], String)>();
            for (var (_key1996, _) in _news1967[_okey1994]) {
                var _scratch1998 = _own1995.scratch();
                _scratch1998.text(_key1996);
                var _vscratch2000 = _own1995.scratch();
                _vscratch2000.unsigned(_news1967[_okey1994][_key1996].count);
                for (var _item2001 in _news1967[_okey1994][_key1996]) {
                    _vscratch2000.text(_item2001);
                }
                _keys1997.append((_scratch1998.finish(), _vscratch2000.finish(), _key1996));
            }
            _keys1997.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            _own1995.unsigned(_keys1997.count);
            for (var (_bytes1999, _, _key1996) in _keys1997) {
                _own1995.text(_key1996);
                _own1995.unsigned(_news1967[_okey1994][_key1996].count);
                for (var _item2002 in _news1967[_okey1994][_key1996]) {
                    _own1995.text(_item2002);
                }
            }
            base.own("method_overload_sets", interface_text(_own1995));
        }
    } else {
        out.unsigned(0);
        var _keys2004 = Array<(u8[], u8[], String)>();
        for (var (_key2003, _) in value.method_overload_sets) {
            var _scratch2005 = out.scratch();
            _scratch2005.text(_key2003);
            var _vscratch2007 = out.scratch();
            var _keys2009 = Array<(u8[], u8[], String)>();
            for (var (_key2008, _) in value.method_overload_sets[_key2003]) {
                var _scratch2010 = _vscratch2007.scratch();
                _scratch2010.text(_key2008);
                var _vscratch2012 = _vscratch2007.scratch();
                _vscratch2012.unsigned(value.method_overload_sets[_key2003][_key2008].count);
                for (var _item2013 in value.method_overload_sets[_key2003][_key2008]) {
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
            _vscratch2007.unsigned(_keys2009.count);
            for (var (_bytes2011, _, _key2008) in _keys2009) {
                _vscratch2007.text(_key2008);
                _vscratch2007.unsigned(value.method_overload_sets[_key2003][_key2008].count);
                for (var _item2014 in value.method_overload_sets[_key2003][_key2008]) {
                    _vscratch2007.text(_item2014);
                }
            }
            _keys2004.append((_scratch2005.finish(), _vscratch2007.finish(), _key2003));
        }
        _keys2004.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2004.count);
        for (var (_bytes2006, _, _key2003) in _keys2004) {
            out.text(_key2003);
            var _keys2016 = Array<(u8[], u8[], String)>();
            for (var (_key2015, _) in value.method_overload_sets[_key2003]) {
                var _scratch2017 = out.scratch();
                _scratch2017.text(_key2015);
                var _vscratch2019 = out.scratch();
                _vscratch2019.unsigned(value.method_overload_sets[_key2003][_key2015].count);
                for (var _item2020 in value.method_overload_sets[_key2003][_key2015]) {
                    _vscratch2019.text(_item2020);
                }
                _keys2016.append((_scratch2017.finish(), _vscratch2019.finish(), _key2015));
            }
            _keys2016.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            out.unsigned(_keys2016.count);
            for (var (_bytes2018, _, _key2015) in _keys2016) {
                out.text(_key2015);
                out.unsigned(value.method_overload_sets[_key2003][_key2015].count);
                for (var _item2021 in value.method_overload_sets[_key2003][_key2015]) {
                    out.text(_item2021);
                }
            }
        }
        for (var (_okey2022, _) in value.method_overload_sets) {
            var _own2023 = RecordOut();
            _own2023.blank_bodies = true;
            _own2023.blank_locs = true;
            _own2023.pending_as_bytes = true;
            _own2023.text(_okey2022);
            var _keys2025 = Array<(u8[], u8[], String)>();
            for (var (_key2024, _) in value.method_overload_sets[_okey2022]) {
                var _scratch2026 = _own2023.scratch();
                _scratch2026.text(_key2024);
                var _vscratch2028 = _own2023.scratch();
                _vscratch2028.unsigned(value.method_overload_sets[_okey2022][_key2024].count);
                for (var _item2029 in value.method_overload_sets[_okey2022][_key2024]) {
                    _vscratch2028.text(_item2029);
                }
                _keys2025.append((_scratch2026.finish(), _vscratch2028.finish(), _key2024));
            }
            _keys2025.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            _own2023.unsigned(_keys2025.count);
            for (var (_bytes2027, _, _key2024) in _keys2025) {
                _own2023.text(_key2024);
                _own2023.unsigned(value.method_overload_sets[_okey2022][_key2024].count);
                for (var _item2030 in value.method_overload_sets[_okey2022][_key2024]) {
                    _own2023.text(_item2030);
                }
            }
            base.own("method_overload_sets", interface_text(_own2023));
        }
        base.count("method_overload_sets whole", 0);
    }
    base.stat("method_overload_sets", out.values.count - _mark);
    _mark = out.values.count;
    _m_ExtensionScopes_write(out, value.extension_scopes);
    base.stat("extension_scopes", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2061 = 0;
    var _news2062 = HashSet<Loc>();
    for (var _key2058 in value.private_functions) {
        var _kscratch2059 = base.scratch();
        _kscratch2059.loc(_key2058);
        var _vscratch2060 = base.scratch();
        var _had = base.entry("private_functions", _kscratch2059, _vscratch2060);
        if (_had >= 0) {
            _kept2061 += 1;
        }
        if (_had != 1) {
            _news2062.insert(_key2058);
        }
    }
    if (_kept2061 == base.size("private_functions")) {
        out.unsigned(1);
        var _keys2064 = Array<(u8[], u8[], Loc)>();
        for (var _key2063 in _news2062) {
            var _scratch2065 = out.scratch();
            _scratch2065.loc(_key2063);
            var _vscratch2067 = out.scratch();
            _keys2064.append((_scratch2065.finish(), _vscratch2067.finish(), _key2063));
        }
        _keys2064.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2064.count);
        for (var (_bytes2066, _, _key2063) in _keys2064) {
            out.loc(_key2063);
        }
        for (var _okey2068 in _news2062) {
            var _own2069 = RecordOut();
            _own2069.blank_bodies = true;
            _own2069.blank_locs = true;
            _own2069.pending_as_bytes = true;
            _own2069.loc(_okey2068);
            base.own_at("private_functions", _okey2068, interface_text(_own2069));
        }
    } else {
        out.unsigned(0);
        var _keys2071 = Array<(u8[], u8[], Loc)>();
        for (var _key2070 in value.private_functions) {
            var _scratch2072 = out.scratch();
            _scratch2072.loc(_key2070);
            var _vscratch2074 = out.scratch();
            _keys2071.append((_scratch2072.finish(), _vscratch2074.finish(), _key2070));
        }
        _keys2071.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2071.count);
        for (var (_bytes2073, _, _key2070) in _keys2071) {
            out.loc(_key2070);
        }
        for (var _okey2075 in value.private_functions) {
            var _own2076 = RecordOut();
            _own2076.blank_bodies = true;
            _own2076.blank_locs = true;
            _own2076.pending_as_bytes = true;
            _own2076.loc(_okey2075);
            base.own_at("private_functions", _okey2075, interface_text(_own2076));
        }
        base.count("private_functions whole", 0);
    }
    base.stat("private_functions", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2087 = 0;
    var _news2088 = HashSet<Loc>();
    for (var _key2084 in value.file_private_functions) {
        var _kscratch2085 = base.scratch();
        _kscratch2085.loc(_key2084);
        var _vscratch2086 = base.scratch();
        var _had = base.entry("file_private_functions", _kscratch2085, _vscratch2086);
        if (_had >= 0) {
            _kept2087 += 1;
        }
        if (_had != 1) {
            _news2088.insert(_key2084);
        }
    }
    if (_kept2087 == base.size("file_private_functions")) {
        out.unsigned(1);
        var _keys2090 = Array<(u8[], u8[], Loc)>();
        for (var _key2089 in _news2088) {
            var _scratch2091 = out.scratch();
            _scratch2091.loc(_key2089);
            var _vscratch2093 = out.scratch();
            _keys2090.append((_scratch2091.finish(), _vscratch2093.finish(), _key2089));
        }
        _keys2090.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2090.count);
        for (var (_bytes2092, _, _key2089) in _keys2090) {
            out.loc(_key2089);
        }
        for (var _okey2094 in _news2088) {
            var _own2095 = RecordOut();
            _own2095.blank_bodies = true;
            _own2095.blank_locs = true;
            _own2095.pending_as_bytes = true;
            _own2095.loc(_okey2094);
            base.own_at("file_private_functions", _okey2094, interface_text(_own2095));
        }
    } else {
        out.unsigned(0);
        var _keys2097 = Array<(u8[], u8[], Loc)>();
        for (var _key2096 in value.file_private_functions) {
            var _scratch2098 = out.scratch();
            _scratch2098.loc(_key2096);
            var _vscratch2100 = out.scratch();
            _keys2097.append((_scratch2098.finish(), _vscratch2100.finish(), _key2096));
        }
        _keys2097.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2097.count);
        for (var (_bytes2099, _, _key2096) in _keys2097) {
            out.loc(_key2096);
        }
        for (var _okey2101 in value.file_private_functions) {
            var _own2102 = RecordOut();
            _own2102.blank_bodies = true;
            _own2102.blank_locs = true;
            _own2102.pending_as_bytes = true;
            _own2102.loc(_okey2101);
            base.own_at("file_private_functions", _okey2101, interface_text(_own2102));
        }
        base.count("file_private_functions whole", 0);
    }
    base.stat("file_private_functions", out.values.count - _mark);
    _mark = out.values.count;
    var _n2112 = base.size("call_targets");
    var _scratch2111 = base.scratch();
    if (value.call_targets.count >= _n2112) {
        for (var _i2113 in 0.._n2112) {
            var (_t2114, _t2115) = value.call_targets[_i2113];
            _scratch2111.loc(_t2114);
            _scratch2111.text(_t2115);
        }
    }
    if (value.call_targets.count >= _n2112 and base.same_list("call_targets", _scratch2111)) {
        out.unsigned(1);
        out.unsigned(_n2112);
        out.unsigned(value.call_targets.count - _n2112);
        for (var _i2113 in _n2112..value.call_targets.count) {
            var (_t2116, _t2117) = value.call_targets[_i2113];
            out.loc(_t2116);
            out.text(_t2117);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.call_targets.count);
        for (var _item2118 in value.call_targets) {
            var (_t2119, _t2120) = _item2118;
            out.loc(_t2119);
            out.text(_t2120);
        }
        base.count("call_targets whole", 0);
    }
    base.stat("call_targets", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2137 = 0;
    var _news2138 = Array<(Loc, String)>();
    for (var _item2135 in value.argument_names) {
        var _escratch2136 = base.scratch();
        var (_t2139, _t2140) = _item2135;
        _escratch2136.loc(_t2139);
        _escratch2136.text(_t2140);
        if (base.entry("argument_names", _escratch2136, base.scratch()) >= 0) {
            _kept2137 += 1;
        } else {
            _news2138.append(_item2135);
        }
    }
    if (_kept2137 == base.size("argument_names")) {
        out.unsigned(1);
        out.unsigned(_news2138.count);
        for (var _item2141 in _news2138) {
            var (_t2142, _t2143) = _item2141;
            out.loc(_t2142);
            out.text(_t2143);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.argument_names.count);
        for (var _item2144 in value.argument_names) {
            var (_t2145, _t2146) = _item2144;
            out.loc(_t2145);
            out.text(_t2146);
        }
        base.count("argument_names whole", 0);
    }
    base.stat("argument_names", out.values.count - _mark);
    _mark = out.values.count;
    var _n2161 = base.size("namespaces");
    var _scratch2160 = base.scratch();
    if (value.namespaces.count >= _n2161) {
        for (var _i2162 in 0.._n2161) {
            _scratch2160.text(value.namespaces[_i2162]);
        }
    }
    if (value.namespaces.count >= _n2161 and base.same_list("namespaces", _scratch2160)) {
        out.unsigned(1);
        out.unsigned(_n2161);
        out.unsigned(value.namespaces.count - _n2161);
        for (var _i2162 in _n2161..value.namespaces.count) {
            out.text(value.namespaces[_i2162]);
            {
                var _own2163 = RecordOut();
                _own2163.blank_bodies = true;
                _own2163.blank_locs = true;
                _own2163.pending_as_bytes = true;
                _own2163.text(value.namespaces[_i2162]);
                base.own("namespaces", interface_text(_own2163));
            }
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.namespaces.count);
        for (var _item2164 in value.namespaces) {
            out.text(_item2164);
        }
        for (var _i2162 in 0..value.namespaces.count) {
            {
                var _own2165 = RecordOut();
                _own2165.blank_bodies = true;
                _own2165.blank_locs = true;
                _own2165.pending_as_bytes = true;
                _own2165.text(value.namespaces[_i2162]);
                base.own("namespaces", interface_text(_own2165));
            }
        }
        base.count("namespaces whole", 0);
    }
    base.stat("namespaces", out.values.count - _mark);
    _mark = out.values.count;
    var _n2176 = base.size("cached_files");
    var _scratch2175 = base.scratch();
    if (value.cached_files.count >= _n2176) {
        for (var _i2177 in 0.._n2176) {
            _scratch2175.flag(value.cached_files[_i2177]);
        }
    }
    if (value.cached_files.count >= _n2176 and base.same_list("cached_files", _scratch2175)) {
        out.unsigned(1);
        out.unsigned(_n2176);
        out.unsigned(value.cached_files.count - _n2176);
        for (var _i2177 in _n2176..value.cached_files.count) {
            out.flag(value.cached_files[_i2177]);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.cached_files.count);
        for (var _item2178 in value.cached_files) {
            out.flag(_item2178);
        }
        base.count("cached_files whole", 0);
    }
    base.stat("cached_files", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2190 = 0;
    var _news2191 = HashMap<Loc, String>();
    for (var (_key2187, _) in value.recorded_summaries) {
        var _kscratch2188 = base.scratch();
        _kscratch2188.loc(_key2187);
        var _vscratch2189 = base.scratch();
        _vscratch2189.text(value.recorded_summaries[_key2187]);
        var _had = base.entry("recorded_summaries", _kscratch2188, _vscratch2189);
        if (_had >= 0) {
            _kept2190 += 1;
        }
        if (_had != 1) {
            _news2191[_key2187] = value.recorded_summaries[_key2187];
        }
    }
    if (_kept2190 == base.size("recorded_summaries")) {
        out.unsigned(1);
        var _keys2193 = Array<(u8[], u8[], Loc)>();
        for (var (_key2192, _) in _news2191) {
            var _scratch2194 = out.scratch();
            _scratch2194.loc(_key2192);
            var _vscratch2196 = out.scratch();
            _vscratch2196.text(_news2191[_key2192]);
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
            out.text(_news2191[_key2192]);
        }
    } else {
        out.unsigned(0);
        var _keys2198 = Array<(u8[], u8[], Loc)>();
        for (var (_key2197, _) in value.recorded_summaries) {
            var _scratch2199 = out.scratch();
            _scratch2199.loc(_key2197);
            var _vscratch2201 = out.scratch();
            _vscratch2201.text(value.recorded_summaries[_key2197]);
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
            out.text(value.recorded_summaries[_key2197]);
        }
        base.count("recorded_summaries whole", 0);
    }
    base.stat("recorded_summaries", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2214 = 0;
    var _news2215 = HashSet<Loc>();
    for (var _key2211 in value.stripped) {
        var _kscratch2212 = base.scratch();
        _kscratch2212.loc(_key2211);
        var _vscratch2213 = base.scratch();
        var _had = base.entry("stripped", _kscratch2212, _vscratch2213);
        if (_had >= 0) {
            _kept2214 += 1;
        }
        if (_had != 1) {
            _news2215.insert(_key2211);
        }
    }
    if (_kept2214 == base.size("stripped")) {
        out.unsigned(1);
        var _keys2217 = Array<(u8[], u8[], Loc)>();
        for (var _key2216 in _news2215) {
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
    } else {
        out.unsigned(0);
        var _keys2222 = Array<(u8[], u8[], Loc)>();
        for (var _key2221 in value.stripped) {
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
        base.count("stripped whole", 0);
    }
    base.stat("stripped", out.values.count - _mark);
    _mark = out.values.count;
    out.flag(value.templates.frozen);
    var _seq2235 = base.ref_templates;
    ulong _bj2236 = 0;
    var _news2238 = Array<ulong>();
    var _patches2239 = Array<(ulong, ulong)>();
    for (var _i2240 in 0..value.templates.structs.count) {
        if (_bj2236 < _seq2235.count
            and value.templates.structs[_i2240] === _seq2235[_bj2236]
            and !value.extended_checked.contains(value.templates.structs[_i2240].name)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_StructDef_write(scratch, value.templates.structs[_i2240]);
                base.verify_same("t", _bj2236, scratch, value.templates.structs[_i2240].name);
            }
            _bj2236 += 1;
        } else if (_bj2236 < _seq2235.count
            and !(value.templates.structs[_i2240] === _seq2235[_bj2236])
            and _same_m_StructDef(value.templates.structs[_i2240], _seq2235[_bj2236], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_StructDef_write(scratch, value.templates.structs[_i2240]);
                base.verify_same("t", _bj2236, scratch, value.templates.structs[_i2240].name);
            }
            _bj2236 += 1;
        } else if (_bj2236 < _seq2235.count and value.templates.structs[_i2240].name == _seq2235[_bj2236].name) {
            _patches2239.append((_i2240, _bj2236));
            _bj2236 += 1;
        } else {
            _news2238.append(_i2240);
        }
    }
    if (_bj2236 == _seq2235.count) {
        out.unsigned(2);
        out.unsigned(_patches2239.count);
        for (var (_i2240, _b) in _patches2239) {
            ulong _before = out.values.count;
            out.text(value.templates.structs[_i2240].name);
            out.unsigned(_b);
            _patch_t_write(out, value.templates.structs[_i2240], base, _b);
            base.count("t patched", out.values.count - _before);
            {
                var _own2241 = RecordOut();
                _own2241.blank_bodies = false;
                _own2241.blank_locs = true;
                _own2241.pending_as_bytes = true;
                _m_StructDef_write(_own2241, value.templates.structs[_i2240]);
                base.own("templates structs", interface_text(_own2241));
            }
        }
        out.unsigned(_news2238.count);
        for (var _i2240 in _news2238) {
            ulong _before = out.values.count;
            out.unsigned(_i2240);
            _m_StructDef_write(out, value.templates.structs[_i2240]);
            base.count("t new", out.values.count - _before);
            {
                var _own2242 = RecordOut();
                _own2242.blank_bodies = false;
                _own2242.blank_locs = true;
                _own2242.pending_as_bytes = true;
                _m_StructDef_write(_own2242, value.templates.structs[_i2240]);
                base.own("templates structs", interface_text(_own2242));
            }
        }
        base.count("t merged", 0);
    } else {
        out.unsigned(1);
        base.count("t by place", 0);
        var _struct_hits2234 = HashSet<long>();
        var _slots2237 = HashMap<String, long>();
        for (var _i2240 in 0.._seq2235.count) {
            if (!_slots2237.contains(_seq2235[_i2240].name)) {
                _slots2237[_seq2235[_i2240].name] = _i2240 as long;
            }
        }
        out.unsigned(value.templates.structs.count);
        for (var _i2240 in 0..value.templates.structs.count) {
            var _item2233 = value.templates.structs[_i2240];
            var _slot = _slots2237.try_get(_item2233.name);
            long named = _slot.is_value() ? _slot.value() : -1;
            long at = -1;
            if (named >= 0
                and _seq2235[named as ulong] === _item2233
                and !value.extended_checked.contains(_item2233.name)) {
                at = named;
            }
            ulong _before = out.values.count;
            if (at >= 0) {
                _struct_hits2234.insert(at);
                out.unsigned((at as ulong) * 2 + 1);
            } else if (named >= 0) {
                _struct_hits2234.insert(named);
                out.unsigned(2);
                out.unsigned(named as ulong);
                _patch_t_write(out, _item2233, base, named as ulong);
                base.count("t patched", out.values.count - _before);
            } else {
                out.unsigned(0);
                _m_StructDef_write(out, _item2233);
                base.count("t new", out.values.count - _before);
            }
        }
        base.missed("t", "t", _struct_hits2234.count);
    }
    var _seq2256 = base.ref_template_functions;
    ulong _bj2257 = 0;
    var _news2258 = Array<ulong>();
    var _changed2252 = Array<(ulong, ulong)>();
    for (var _i2259 in 0..value.templates.functions.count) {
        if (_bj2257 < _seq2256.count and value.templates.functions[_i2259] === _seq2256[_bj2257]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.templates.functions[_i2259]);
                base.verify_same("tf", _bj2257, scratch);
            }
            _bj2257 += 1;
        } else if (_bj2257 < _seq2256.count
            and _same_m_FunctionDef(value.templates.functions[_i2259], _seq2256[_bj2257], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.templates.functions[_i2259]);
                base.verify_same("tf", _bj2257, scratch);
            }
            _bj2257 += 1;
        } else if (_bj2257 < _seq2256.count and value.templates.functions[_i2259].name == _seq2256[_bj2257].name) {
            _changed2252.append((_i2259, _bj2257));
            _bj2257 += 1;
        } else {
            _news2258.append(_i2259);
        }
    }
    if (_bj2257 == _seq2256.count) {
        out.unsigned(2);
        out.unsigned(_changed2252.count);
        for (var (_i2259, _b) in _changed2252) {
            out.text(value.templates.functions[_i2259].name);
            out.unsigned(_b);
            _m_FunctionDef_write(out, value.templates.functions[_i2259]);
            {
                var _own2260 = RecordOut();
                _own2260.blank_bodies = false;
                _own2260.blank_locs = true;
                _own2260.pending_as_bytes = true;
                _m_FunctionDef_write(_own2260, value.templates.functions[_i2259]);
                base.own("templates functions", interface_text(_own2260));
            }
        }
        base.count("tf" + " changed", _changed2252.count);
        out.unsigned(_news2258.count);
        for (var _i2259 in _news2258) {
            out.unsigned(_i2259);
            _m_FunctionDef_write(out, value.templates.functions[_i2259]);
            {
                var _own2261 = RecordOut();
                _own2261.blank_bodies = false;
                _own2261.blank_locs = true;
                _own2261.pending_as_bytes = true;
                _m_FunctionDef_write(_own2261, value.templates.functions[_i2259]);
                base.own("templates functions", interface_text(_own2261));
            }
        }
        base.count("tf" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("tf" + " whole", 0);
        out.unsigned(value.templates.functions.count);
        for (var _i2259 in 0..value.templates.functions.count) {
            _m_FunctionDef_write(out, value.templates.functions[_i2259]);
            {
                var _own2262 = RecordOut();
                _own2262.blank_bodies = false;
                _own2262.blank_locs = true;
                _own2262.pending_as_bytes = true;
                _m_FunctionDef_write(_own2262, value.templates.functions[_i2259]);
                base.own("templates functions", interface_text(_own2262));
            }
        }
    }
    base.stat("templates", out.values.count - _mark);
    _mark = out.values.count;
    base.write_checked(out, value.checked);
    base.stat("checked", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2275 = 0;
    var _news2276 = HashMap<String, SpecRequest>();
    for (var (_key2272, _) in value.spec_requests) {
        var _kscratch2273 = base.scratch();
        _kscratch2273.text(_key2272);
        var _vscratch2274 = base.scratch();
        _m_SpecRequest_write(_vscratch2274, value.spec_requests[_key2272]);
        var _had = base.entry("spec_requests", _kscratch2273, _vscratch2274);
        if (_had >= 0) {
            _kept2275 += 1;
        }
        if (_had != 1) {
            _news2276[_key2272] = value.spec_requests[_key2272];
        }
    }
    if (_kept2275 == base.size("spec_requests")) {
        out.unsigned(1);
        var _keys2278 = Array<(u8[], u8[], String)>();
        for (var (_key2277, _) in _news2276) {
            var _scratch2279 = out.scratch();
            _scratch2279.text(_key2277);
            var _vscratch2281 = out.scratch();
            _m_SpecRequest_write(_vscratch2281, _news2276[_key2277]);
            _keys2278.append((_scratch2279.finish(), _vscratch2281.finish(), _key2277));
        }
        _keys2278.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2278.count);
        for (var (_bytes2280, _, _key2277) in _keys2278) {
            out.text(_key2277);
            _m_SpecRequest_write(out, _news2276[_key2277]);
        }
        for (var (_okey2282, _) in _news2276) {
            var _own2283 = RecordOut();
            _own2283.blank_bodies = true;
            _own2283.blank_locs = true;
            _own2283.pending_as_bytes = true;
            _own2283.text(_okey2282);
            _m_SpecRequest_write(_own2283, _news2276[_okey2282]);
            base.own("spec_requests", interface_text(_own2283));
        }
    } else {
        out.unsigned(0);
        var _keys2285 = Array<(u8[], u8[], String)>();
        for (var (_key2284, _) in value.spec_requests) {
            var _scratch2286 = out.scratch();
            _scratch2286.text(_key2284);
            var _vscratch2288 = out.scratch();
            _m_SpecRequest_write(_vscratch2288, value.spec_requests[_key2284]);
            _keys2285.append((_scratch2286.finish(), _vscratch2288.finish(), _key2284));
        }
        _keys2285.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2285.count);
        for (var (_bytes2287, _, _key2284) in _keys2285) {
            out.text(_key2284);
            _m_SpecRequest_write(out, value.spec_requests[_key2284]);
        }
        for (var (_okey2289, _) in value.spec_requests) {
            var _own2290 = RecordOut();
            _own2290.blank_bodies = true;
            _own2290.blank_locs = true;
            _own2290.pending_as_bytes = true;
            _own2290.text(_okey2289);
            _m_SpecRequest_write(_own2290, value.spec_requests[_okey2289]);
            base.own("spec_requests", interface_text(_own2290));
        }
        base.count("spec_requests whole", 0);
    }
    base.stat("spec_requests", out.values.count - _mark);
    _mark = out.values.count;
    out.flag(value.record_summaries);
    base.stat("record_summaries", out.values.count - _mark);
    _mark = out.values.count;
    var _n2303 = base.size("summaries_to_record");
    var _scratch2302 = base.scratch();
    if (value.summaries_to_record.count >= _n2303) {
        for (var _i2304 in 0.._n2303) {
            var (_t2305, _t2306) = value.summaries_to_record[_i2304];
            _scratch2302.loc(_t2305);
            _scratch2302.text(_t2306);
        }
    }
    if (value.summaries_to_record.count >= _n2303 and base.same_list("summaries_to_record", _scratch2302)) {
        out.unsigned(1);
        out.unsigned(_n2303);
        out.unsigned(value.summaries_to_record.count - _n2303);
        for (var _i2304 in _n2303..value.summaries_to_record.count) {
            var (_t2307, _t2308) = value.summaries_to_record[_i2304];
            out.loc(_t2307);
            out.text(_t2308);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.summaries_to_record.count);
        for (var _item2309 in value.summaries_to_record) {
            var (_t2310, _t2311) = _item2309;
            out.loc(_t2310);
            out.text(_t2311);
        }
        base.count("summaries_to_record whole", 0);
    }
    base.stat("summaries_to_record", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2329 = 0;
    var _news2330 = HashMap<String, Array<bool>>();
    for (var (_key2326, _) in value.caller_copies) {
        var _kscratch2327 = base.scratch();
        _kscratch2327.text(_key2326);
        var _vscratch2328 = base.scratch();
        _vscratch2328.unsigned(value.caller_copies[_key2326].count);
        for (var _item2331 in value.caller_copies[_key2326]) {
            _vscratch2328.flag(_item2331);
        }
        var _had = base.entry("caller_copies", _kscratch2327, _vscratch2328);
        if (_had >= 0) {
            _kept2329 += 1;
        }
        if (_had != 1) {
            _news2330[_key2326] = value.caller_copies[_key2326];
        }
    }
    if (_kept2329 == base.size("caller_copies")) {
        out.unsigned(1);
        var _keys2333 = Array<(u8[], u8[], String)>();
        for (var (_key2332, _) in _news2330) {
            var _scratch2334 = out.scratch();
            _scratch2334.text(_key2332);
            var _vscratch2336 = out.scratch();
            _vscratch2336.unsigned(_news2330[_key2332].count);
            for (var _item2337 in _news2330[_key2332]) {
                _vscratch2336.flag(_item2337);
            }
            _keys2333.append((_scratch2334.finish(), _vscratch2336.finish(), _key2332));
        }
        _keys2333.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2333.count);
        for (var (_bytes2335, _, _key2332) in _keys2333) {
            out.text(_key2332);
            out.unsigned(_news2330[_key2332].count);
            for (var _item2338 in _news2330[_key2332]) {
                out.flag(_item2338);
            }
        }
        for (var (_okey2339, _) in _news2330) {
            var _own2340 = RecordOut();
            _own2340.blank_bodies = true;
            _own2340.blank_locs = true;
            _own2340.pending_as_bytes = true;
            _own2340.text(_okey2339);
            _own2340.unsigned(_news2330[_okey2339].count);
            for (var _item2341 in _news2330[_okey2339]) {
                _own2340.flag(_item2341);
            }
            base.own("caller_copies", interface_text(_own2340));
        }
    } else {
        out.unsigned(0);
        var _keys2343 = Array<(u8[], u8[], String)>();
        for (var (_key2342, _) in value.caller_copies) {
            var _scratch2344 = out.scratch();
            _scratch2344.text(_key2342);
            var _vscratch2346 = out.scratch();
            _vscratch2346.unsigned(value.caller_copies[_key2342].count);
            for (var _item2347 in value.caller_copies[_key2342]) {
                _vscratch2346.flag(_item2347);
            }
            _keys2343.append((_scratch2344.finish(), _vscratch2346.finish(), _key2342));
        }
        _keys2343.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2343.count);
        for (var (_bytes2345, _, _key2342) in _keys2343) {
            out.text(_key2342);
            out.unsigned(value.caller_copies[_key2342].count);
            for (var _item2348 in value.caller_copies[_key2342]) {
                out.flag(_item2348);
            }
        }
        for (var (_okey2349, _) in value.caller_copies) {
            var _own2350 = RecordOut();
            _own2350.blank_bodies = true;
            _own2350.blank_locs = true;
            _own2350.pending_as_bytes = true;
            _own2350.text(_okey2349);
            _own2350.unsigned(value.caller_copies[_okey2349].count);
            for (var _item2351 in value.caller_copies[_okey2349]) {
                _own2350.flag(_item2351);
            }
            base.own("caller_copies", interface_text(_own2350));
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
    var _f1498 = Array<ast.Import>();
    var _mode1501 = input.unsigned();
    if (_mode1501 == 2) {
        var _changed1487 = HashMap<ulong, ast.Import>();
        ulong _bi1502 = 0;
        var _n1499 = input.count();
        for (var _ in 0.._n1499) {
            var _at1503 = input.unsigned();
            while (_f1498.count < _at1503 or (input.merging and _bi1502 < base.imports.count)) {
                var _c = _changed1487.try_get(_bi1502);
                _f1498.append(_c.is_value() ? _c.value() : base.imports[_bi1502]);
                _bi1502 += 1;
            }
            _f1498.append(_a_Import_read(input));
        }
        while (_bi1502 < base.imports.count) {
            var _c = _changed1487.try_get(_bi1502);
            _f1498.append(_c.is_value() ? _c.value() : base.imports[_bi1502]);
            _bi1502 += 1;
        }
    } else if (_mode1501 == 3) {
        var _n1499 = input.count();
        for (var _ in 0.._n1499) {
            _f1498.append(_a_Import_read(input));
        }
    } else {
        var _n1499 = input.count();
        if (input.merging) {
            input.error = "imports" + " written by place";
        }
        for (var _ in 0.._n1499) {
            var _tag1500 = input.unsigned();
            if (_tag1500 & 1 == 1) {
                if (!input.merging) {
                    _f1498.append(base.imports[_tag1500 >> 1]);
                }
            } else {
                var _read = _a_Import_read(input);
                if (!input.merging or true) {
                    _f1498.append(_read);
                }
            }
        }
    }
    var _f1531 = Array<StructDef>();
    var _mode1534 = input.unsigned();
    if (_mode1534 == 2) {
        var _patched1537 = HashMap<ulong, StructDef>();
        var _n1532 = input.count();
        for (var _ in 0.._n1532) {
            var _name = input.text();
            var _slot = input.unsigned();
            if (input.merging) {
                _slot = struct_named(base.structs, _name);
            }
            if (_slot >= base.structs.count) {
                input.error = $"no struct {_name} to patch";
                break;
            }
            _patched1537[_slot] = _patch_s_read(input, base.structs[_slot]);
        }
        ulong _bi1535 = 0;
        var _added = input.count();
        for (var _ in 0.._added) {
            var _at1536 = input.unsigned();
            while (_f1531.count < _at1536 or (input.merging and _bi1535 < base.structs.count)) {
                var _p = _patched1537.try_get(_bi1535);
                _f1531.append(_p.is_value() ? _p.value() : base.structs[_bi1535]);
                _bi1535 += 1;
            }
            _f1531.append(_m_StructDef_read_lazy(input));
        }
        while (_bi1535 < base.structs.count) {
            var _p = _patched1537.try_get(_bi1535);
            _f1531.append(_p.is_value() ? _p.value() : base.structs[_bi1535]);
            _bi1535 += 1;
        }
    } else {
        if (input.merging) {
            input.error = "structs written by place";
        }
        var _n1532 = input.count();
        for (var _ in 0.._n1532) {
            var _tag1533 = input.unsigned();
            if (_tag1533 & 1 == 1) {
                _f1531.append(base.structs[(_tag1533 >> 1) < base.structs.count ? _tag1533 >> 1 : 0]);
            } else if (_tag1533 == 2) {
                var _was = base.structs[input.unsigned()];
                _f1531.append(_patch_s_read(input, _was));
            } else {
                _f1531.append(_m_StructDef_read_lazy(input));
            }
        }
    }
    var _f1551 = Array<TraitDef>();
    var _mode1554 = input.unsigned();
    if (_mode1554 == 2) {
        var _changed1540 = HashMap<ulong, TraitDef>();
        ulong _bi1555 = 0;
        var _n1552 = input.count();
        for (var _ in 0.._n1552) {
            var _at1556 = input.unsigned();
            while (_f1551.count < _at1556 or (input.merging and _bi1555 < base.traits.count)) {
                var _c = _changed1540.try_get(_bi1555);
                _f1551.append(_c.is_value() ? _c.value() : base.traits[_bi1555]);
                _bi1555 += 1;
            }
            _f1551.append(_m_TraitDef_read(input));
        }
        while (_bi1555 < base.traits.count) {
            var _c = _changed1540.try_get(_bi1555);
            _f1551.append(_c.is_value() ? _c.value() : base.traits[_bi1555]);
            _bi1555 += 1;
        }
    } else if (_mode1554 == 3) {
        var _n1552 = input.count();
        for (var _ in 0.._n1552) {
            _f1551.append(_m_TraitDef_read(input));
        }
    } else {
        var _n1552 = input.count();
        if (input.merging) {
            input.error = "traits" + " written by place";
        }
        for (var _ in 0.._n1552) {
            var _tag1553 = input.unsigned();
            if (_tag1553 & 1 == 1) {
                if (!input.merging) {
                    _f1551.append(base.traits[_tag1553 >> 1]);
                }
            } else {
                var _read = _m_TraitDef_read(input);
                if (!input.merging or true) {
                    _f1551.append(_read);
                }
            }
        }
    }
    var _f1570 = Array<ExtensionDef>();
    var _mode1573 = input.unsigned();
    if (_mode1573 == 2) {
        var _changed1559 = HashMap<ulong, ExtensionDef>();
        ulong _bi1574 = 0;
        var _n1571 = input.count();
        for (var _ in 0.._n1571) {
            var _at1575 = input.unsigned();
            while (_f1570.count < _at1575 or (input.merging and _bi1574 < base.extensions.count)) {
                var _c = _changed1559.try_get(_bi1574);
                _f1570.append(_c.is_value() ? _c.value() : base.extensions[_bi1574]);
                _bi1574 += 1;
            }
            _f1570.append(_m_ExtensionDef_read(input));
        }
        while (_bi1574 < base.extensions.count) {
            var _c = _changed1559.try_get(_bi1574);
            _f1570.append(_c.is_value() ? _c.value() : base.extensions[_bi1574]);
            _bi1574 += 1;
        }
    } else if (_mode1573 == 3) {
        var _n1571 = input.count();
        for (var _ in 0.._n1571) {
            _f1570.append(_m_ExtensionDef_read(input));
        }
    } else {
        var _n1571 = input.count();
        if (input.merging) {
            input.error = "extensions" + " written by place";
        }
        for (var _ in 0.._n1571) {
            var _tag1572 = input.unsigned();
            if (_tag1572 & 1 == 1) {
                if (!input.merging) {
                    _f1570.append(base.extensions[_tag1572 >> 1]);
                }
            } else {
                var _read = _m_ExtensionDef_read(input);
                if (!input.merging or true) {
                    _f1570.append(_read);
                }
            }
        }
    }
    var _f1589 = Array<FunctionDef>();
    var _mode1592 = input.unsigned();
    if (_mode1592 == 2) {
        var _changed1578 = HashMap<ulong, FunctionDef>();
        var _nc1580 = input.count();
        for (var _ in 0.._nc1580) {
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
                _changed1578[_slot] = _el;
            } else {
                input.error = $"no {_name} to change";
            }
        }
        ulong _bi1593 = 0;
        var _n1590 = input.count();
        for (var _ in 0.._n1590) {
            var _at1594 = input.unsigned();
            while (_f1589.count < _at1594 or (input.merging and _bi1593 < base.functions.count)) {
                var _c = _changed1578.try_get(_bi1593);
                _f1589.append(_c.is_value() ? _c.value() : base.functions[_bi1593]);
                _bi1593 += 1;
            }
            _f1589.append(_m_FunctionDef_read_lazy(input));
        }
        while (_bi1593 < base.functions.count) {
            var _c = _changed1578.try_get(_bi1593);
            _f1589.append(_c.is_value() ? _c.value() : base.functions[_bi1593]);
            _bi1593 += 1;
        }
    } else if (_mode1592 == 3) {
        var _n1590 = input.count();
        for (var _ in 0.._n1590) {
            _f1589.append(_m_FunctionDef_read_lazy(input));
        }
    } else {
        var _n1590 = input.count();
        if (input.merging) {
            input.error = "functions" + " written by place";
        }
        for (var _ in 0.._n1590) {
            var _tag1591 = input.unsigned();
            if (_tag1591 & 1 == 1) {
                if (!input.merging) {
                    _f1589.append(base.functions[_tag1591 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read_lazy(input);
                if (!input.merging or true) {
                    _f1589.append(_read);
                }
            }
        }
    }
    var _f1608 = Array<ExternDef>();
    var _mode1611 = input.unsigned();
    if (_mode1611 == 2) {
        var _changed1597 = HashMap<ulong, ExternDef>();
        ulong _bi1612 = 0;
        var _n1609 = input.count();
        for (var _ in 0.._n1609) {
            var _at1613 = input.unsigned();
            while (_f1608.count < _at1613 or (input.merging and _bi1612 < base.externs.count)) {
                var _c = _changed1597.try_get(_bi1612);
                _f1608.append(_c.is_value() ? _c.value() : base.externs[_bi1612]);
                _bi1612 += 1;
            }
            _f1608.append(_m_ExternDef_read(input));
        }
        while (_bi1612 < base.externs.count) {
            var _c = _changed1597.try_get(_bi1612);
            _f1608.append(_c.is_value() ? _c.value() : base.externs[_bi1612]);
            _bi1612 += 1;
        }
    } else if (_mode1611 == 3) {
        var _n1609 = input.count();
        for (var _ in 0.._n1609) {
            _f1608.append(_m_ExternDef_read(input));
        }
    } else {
        var _n1609 = input.count();
        if (input.merging) {
            input.error = "externs" + " written by place";
        }
        for (var _ in 0.._n1609) {
            var _tag1610 = input.unsigned();
            if (_tag1610 & 1 == 1) {
                if (!input.merging) {
                    _f1608.append(base.externs[_tag1610 >> 1]);
                }
            } else {
                var _read = _m_ExternDef_read(input);
                if (!input.merging or true) {
                    _f1608.append(_read);
                }
            }
        }
    }
    var _f1627 = Array<VariableDef>();
    var _mode1630 = input.unsigned();
    if (_mode1630 == 2) {
        var _changed1616 = HashMap<ulong, VariableDef>();
        ulong _bi1631 = 0;
        var _n1628 = input.count();
        for (var _ in 0.._n1628) {
            var _at1632 = input.unsigned();
            while (_f1627.count < _at1632 or (input.merging and _bi1631 < base.globals.count)) {
                var _c = _changed1616.try_get(_bi1631);
                _f1627.append(_c.is_value() ? _c.value() : base.globals[_bi1631]);
                _bi1631 += 1;
            }
            _f1627.append(_m_VariableDef_read(input));
        }
        while (_bi1631 < base.globals.count) {
            var _c = _changed1616.try_get(_bi1631);
            _f1627.append(_c.is_value() ? _c.value() : base.globals[_bi1631]);
            _bi1631 += 1;
        }
    } else if (_mode1630 == 3) {
        var _n1628 = input.count();
        for (var _ in 0.._n1628) {
            _f1627.append(_m_VariableDef_read(input));
        }
    } else {
        var _n1628 = input.count();
        if (input.merging) {
            input.error = "globals" + " written by place";
        }
        for (var _ in 0.._n1628) {
            var _tag1629 = input.unsigned();
            if (_tag1629 & 1 == 1) {
                if (!input.merging) {
                    _f1627.append(base.globals[_tag1629 >> 1]);
                }
            } else {
                var _read = _m_VariableDef_read(input);
                if (!input.merging or true) {
                    _f1627.append(_read);
                }
            }
        }
    }
    var _f1646 = Array<ModuleStaticBlock>();
    var _mode1649 = input.unsigned();
    if (_mode1649 == 2) {
        var _changed1635 = HashMap<ulong, ModuleStaticBlock>();
        ulong _bi1650 = 0;
        var _n1647 = input.count();
        for (var _ in 0.._n1647) {
            var _at1651 = input.unsigned();
            while (_f1646.count < _at1651 or (input.merging and _bi1650 < base.static_blocks.count)) {
                var _c = _changed1635.try_get(_bi1650);
                _f1646.append(_c.is_value() ? _c.value() : base.static_blocks[_bi1650]);
                _bi1650 += 1;
            }
            _f1646.append(_m_ModuleStaticBlock_read(input));
        }
        while (_bi1650 < base.static_blocks.count) {
            var _c = _changed1635.try_get(_bi1650);
            _f1646.append(_c.is_value() ? _c.value() : base.static_blocks[_bi1650]);
            _bi1650 += 1;
        }
    } else if (_mode1649 == 3) {
        var _n1647 = input.count();
        for (var _ in 0.._n1647) {
            _f1646.append(_m_ModuleStaticBlock_read(input));
        }
    } else {
        var _n1647 = input.count();
        if (input.merging) {
            input.error = "static_blocks" + " written by place";
        }
        for (var _ in 0.._n1647) {
            var _tag1648 = input.unsigned();
            if (_tag1648 & 1 == 1) {
                if (!input.merging) {
                    _f1646.append(base.static_blocks[_tag1648 >> 1]);
                }
            } else {
                var _read = _m_ModuleStaticBlock_read(input);
                if (!input.merging or true) {
                    _f1646.append(_read);
                }
            }
        }
    }
    var _f1665 = Array<EnumDef>();
    var _mode1668 = input.unsigned();
    if (_mode1668 == 2) {
        var _changed1654 = HashMap<ulong, EnumDef>();
        ulong _bi1669 = 0;
        var _n1666 = input.count();
        for (var _ in 0.._n1666) {
            var _at1670 = input.unsigned();
            while (_f1665.count < _at1670 or (input.merging and _bi1669 < base.enums.count)) {
                var _c = _changed1654.try_get(_bi1669);
                _f1665.append(_c.is_value() ? _c.value() : base.enums[_bi1669]);
                _bi1669 += 1;
            }
            _f1665.append(_m_EnumDef_read(input));
        }
        while (_bi1669 < base.enums.count) {
            var _c = _changed1654.try_get(_bi1669);
            _f1665.append(_c.is_value() ? _c.value() : base.enums[_bi1669]);
            _bi1669 += 1;
        }
    } else if (_mode1668 == 3) {
        var _n1666 = input.count();
        for (var _ in 0.._n1666) {
            _f1665.append(_m_EnumDef_read(input));
        }
    } else {
        var _n1666 = input.count();
        if (input.merging) {
            input.error = "enums" + " written by place";
        }
        for (var _ in 0.._n1666) {
            var _tag1667 = input.unsigned();
            if (_tag1667 & 1 == 1) {
                if (!input.merging) {
                    _f1665.append(base.enums[_tag1667 >> 1]);
                }
            } else {
                var _read = _m_EnumDef_read(input);
                if (!input.merging or true) {
                    _f1665.append(_read);
                }
            }
        }
    }
    var _f1684 = Array<TypeName>();
    var _mode1687 = input.unsigned();
    if (_mode1687 == 2) {
        var _changed1673 = HashMap<ulong, TypeName>();
        ulong _bi1688 = 0;
        var _n1685 = input.count();
        for (var _ in 0.._n1685) {
            var _at1689 = input.unsigned();
            while (_f1684.count < _at1689 or (input.merging and _bi1688 < base.struct_specs.count)) {
                var _c = _changed1673.try_get(_bi1688);
                _f1684.append(_c.is_value() ? _c.value() : base.struct_specs[_bi1688]);
                _bi1688 += 1;
            }
            _f1684.append(_m_TypeName_read(input));
        }
        while (_bi1688 < base.struct_specs.count) {
            var _c = _changed1673.try_get(_bi1688);
            _f1684.append(_c.is_value() ? _c.value() : base.struct_specs[_bi1688]);
            _bi1688 += 1;
        }
    } else if (_mode1687 == 3) {
        var _n1685 = input.count();
        for (var _ in 0.._n1685) {
            _f1684.append(_m_TypeName_read(input));
        }
    } else {
        var _n1685 = input.count();
        if (input.merging) {
            input.error = "struct_specs" + " written by place";
        }
        for (var _ in 0.._n1685) {
            var _tag1686 = input.unsigned();
            if (_tag1686 & 1 == 1) {
                if (!input.merging) {
                    _f1684.append(base.struct_specs[_tag1686 >> 1]);
                }
            } else {
                var _read = _m_TypeName_read(input);
                if (!input.merging or true) {
                    _f1684.append(_read);
                }
            }
        }
    }
    var _f1703 = Array<TypeName>();
    var _mode1706 = input.unsigned();
    if (_mode1706 == 2) {
        var _changed1692 = HashMap<ulong, TypeName>();
        ulong _bi1707 = 0;
        var _n1704 = input.count();
        for (var _ in 0.._n1704) {
            var _at1708 = input.unsigned();
            while (_f1703.count < _at1708 or (input.merging and _bi1707 < base.func_specs.count)) {
                var _c = _changed1692.try_get(_bi1707);
                _f1703.append(_c.is_value() ? _c.value() : base.func_specs[_bi1707]);
                _bi1707 += 1;
            }
            _f1703.append(_m_TypeName_read(input));
        }
        while (_bi1707 < base.func_specs.count) {
            var _c = _changed1692.try_get(_bi1707);
            _f1703.append(_c.is_value() ? _c.value() : base.func_specs[_bi1707]);
            _bi1707 += 1;
        }
    } else if (_mode1706 == 3) {
        var _n1704 = input.count();
        for (var _ in 0.._n1704) {
            _f1703.append(_m_TypeName_read(input));
        }
    } else {
        var _n1704 = input.count();
        if (input.merging) {
            input.error = "func_specs" + " written by place";
        }
        for (var _ in 0.._n1704) {
            var _tag1705 = input.unsigned();
            if (_tag1705 & 1 == 1) {
                if (!input.merging) {
                    _f1703.append(base.func_specs[_tag1705 >> 1]);
                }
            } else {
                var _read = _m_TypeName_read(input);
                if (!input.merging or true) {
                    _f1703.append(_read);
                }
            }
        }
    }
    var _f1715 = Array<TypeAliasDef>();
    var _n1716 = input.count();
    if (input.merging) {
        for (var _b in base.type_aliases) {
            _f1715.append(_b);
        }
    }
    for (var _ in 0.._n1716) {
        var _tag1717 = input.unsigned();
        if (_tag1717 & 1 == 1) {
            if (!input.merging) {
                _f1715.append(base.type_aliases[_tag1717 >> 1]);
            }
        } else {
            var _read = _m_TypeAliasDef_read(input);
            if (!input.merging or false) {
                _f1715.append(_read);
            }
        }
    }
    var _f1731 = Array<Withheld>();
    var _mode1734 = input.unsigned();
    if (_mode1734 == 2) {
        var _changed1720 = HashMap<ulong, Withheld>();
        ulong _bi1735 = 0;
        var _n1732 = input.count();
        for (var _ in 0.._n1732) {
            var _at1736 = input.unsigned();
            while (_f1731.count < _at1736 or (input.merging and _bi1735 < base.withheld.count)) {
                var _c = _changed1720.try_get(_bi1735);
                _f1731.append(_c.is_value() ? _c.value() : base.withheld[_bi1735]);
                _bi1735 += 1;
            }
            _f1731.append(_m_Withheld_read(input));
        }
        while (_bi1735 < base.withheld.count) {
            var _c = _changed1720.try_get(_bi1735);
            _f1731.append(_c.is_value() ? _c.value() : base.withheld[_bi1735]);
            _bi1735 += 1;
        }
    } else if (_mode1734 == 3) {
        var _n1732 = input.count();
        for (var _ in 0.._n1732) {
            _f1731.append(_m_Withheld_read(input));
        }
    } else {
        var _n1732 = input.count();
        if (input.merging) {
            input.error = "withheld" + " written by place";
        }
        for (var _ in 0.._n1732) {
            var _tag1733 = input.unsigned();
            if (_tag1733 & 1 == 1) {
                if (!input.merging) {
                    _f1731.append(base.withheld[_tag1733 >> 1]);
                }
            } else {
                var _read = _m_Withheld_read(input);
                if (!input.merging or true) {
                    _f1731.append(_read);
                }
            }
        }
    }
    var _f1750 = Array<PropertyDef>();
    var _mode1753 = input.unsigned();
    if (_mode1753 == 2) {
        var _changed1739 = HashMap<ulong, PropertyDef>();
        ulong _bi1754 = 0;
        var _n1751 = input.count();
        for (var _ in 0.._n1751) {
            var _at1755 = input.unsigned();
            while (_f1750.count < _at1755 or (input.merging and _bi1754 < base.properties.count)) {
                var _c = _changed1739.try_get(_bi1754);
                _f1750.append(_c.is_value() ? _c.value() : base.properties[_bi1754]);
                _bi1754 += 1;
            }
            _f1750.append(_m_PropertyDef_read(input));
        }
        while (_bi1754 < base.properties.count) {
            var _c = _changed1739.try_get(_bi1754);
            _f1750.append(_c.is_value() ? _c.value() : base.properties[_bi1754]);
            _bi1754 += 1;
        }
    } else if (_mode1753 == 3) {
        var _n1751 = input.count();
        for (var _ in 0.._n1751) {
            _f1750.append(_m_PropertyDef_read(input));
        }
    } else {
        var _n1751 = input.count();
        if (input.merging) {
            input.error = "properties" + " written by place";
        }
        for (var _ in 0.._n1751) {
            var _tag1752 = input.unsigned();
            if (_tag1752 & 1 == 1) {
                if (!input.merging) {
                    _f1750.append(base.properties[_tag1752 >> 1]);
                }
            } else {
                var _read = _m_PropertyDef_read(input);
                if (!input.merging or true) {
                    _f1750.append(_read);
                }
            }
        }
    }
    var _f1769 = Array<TypeUse>();
    var _mode1772 = input.unsigned();
    if (_mode1772 == 2) {
        var _changed1758 = HashMap<ulong, TypeUse>();
        ulong _bi1773 = 0;
        var _n1770 = input.count();
        for (var _ in 0.._n1770) {
            var _at1774 = input.unsigned();
            while (_f1769.count < _at1774 or (input.merging and _bi1773 < base.type_uses.count)) {
                var _c = _changed1758.try_get(_bi1773);
                _f1769.append(_c.is_value() ? _c.value() : base.type_uses[_bi1773]);
                _bi1773 += 1;
            }
            _f1769.append(_m_TypeUse_read(input));
        }
        while (_bi1773 < base.type_uses.count) {
            var _c = _changed1758.try_get(_bi1773);
            _f1769.append(_c.is_value() ? _c.value() : base.type_uses[_bi1773]);
            _bi1773 += 1;
        }
    } else if (_mode1772 == 3) {
        var _n1770 = input.count();
        for (var _ in 0.._n1770) {
            _f1769.append(_m_TypeUse_read(input));
        }
    } else {
        var _n1770 = input.count();
        if (input.merging) {
            input.error = "type_uses" + " written by place";
        }
        for (var _ in 0.._n1770) {
            var _tag1771 = input.unsigned();
            if (_tag1771 & 1 == 1) {
                if (!input.merging) {
                    _f1769.append(base.type_uses[_tag1771 >> 1]);
                }
            } else {
                var _read = _m_TypeUse_read(input);
                if (!input.merging or true) {
                    _f1769.append(_read);
                }
            }
        }
    }
    var _f1788 = Array<UseContext>();
    var _mode1791 = input.unsigned();
    if (_mode1791 == 2) {
        var _changed1777 = HashMap<ulong, UseContext>();
        ulong _bi1792 = 0;
        var _n1789 = input.count();
        for (var _ in 0.._n1789) {
            var _at1793 = input.unsigned();
            while (_f1788.count < _at1793 or (input.merging and _bi1792 < base.use_contexts.count)) {
                var _c = _changed1777.try_get(_bi1792);
                _f1788.append(_c.is_value() ? _c.value() : base.use_contexts[_bi1792]);
                _bi1792 += 1;
            }
            _f1788.append(_m_UseContext_read(input));
        }
        while (_bi1792 < base.use_contexts.count) {
            var _c = _changed1777.try_get(_bi1792);
            _f1788.append(_c.is_value() ? _c.value() : base.use_contexts[_bi1792]);
            _bi1792 += 1;
        }
    } else if (_mode1791 == 3) {
        var _n1789 = input.count();
        for (var _ in 0.._n1789) {
            _f1788.append(_m_UseContext_read(input));
        }
    } else {
        var _n1789 = input.count();
        if (input.merging) {
            input.error = "use_contexts" + " written by place";
        }
        for (var _ in 0.._n1789) {
            var _tag1790 = input.unsigned();
            if (_tag1790 & 1 == 1) {
                if (!input.merging) {
                    _f1788.append(base.use_contexts[_tag1790 >> 1]);
                }
            } else {
                var _read = _m_UseContext_read(input);
                if (!input.merging or true) {
                    _f1788.append(_read);
                }
            }
        }
    }
    var _f1809 = Array<(Loc, ulong, Loc)>();
    var _tag1810 = input.unsigned();
    if (_tag1810 == 1) {
        input.unsigned();
        for (var _i1798 in 0..base.literal_args.count) {
            _f1809.append(base.literal_args[_i1798]);
        }
        var _more1812 = input.count();
        for (var _ in 0.._more1812) {
            var _t1813 = input.loc();
            var _t1814 = input.unsigned();
            var _t1815 = input.loc();
            _f1809.append((_t1813, _t1814, _t1815));
        }
    } else {
        var _v1816 = Array<(Loc, ulong, Loc)>();
        var _n1817 = input.count();
        for (var _ in 0.._n1817) {
            var _t1818 = input.loc();
            var _t1819 = input.unsigned();
            var _t1820 = input.loc();
            _v1816.append((_t1818, _t1819, _t1820));
        }
        _f1809 = _v1816;
    }
    var _f1838 = Array<TypeAliasDef>();
    var _mode1841 = input.unsigned();
    if (_mode1841 == 2) {
        var _changed1827 = HashMap<ulong, TypeAliasDef>();
        ulong _bi1842 = 0;
        var _n1839 = input.count();
        for (var _ in 0.._n1839) {
            var _at1843 = input.unsigned();
            while (_f1838.count < _at1843 or (input.merging and _bi1842 < base.constrained_aliases.count)) {
                var _c = _changed1827.try_get(_bi1842);
                _f1838.append(_c.is_value() ? _c.value() : base.constrained_aliases[_bi1842]);
                _bi1842 += 1;
            }
            _f1838.append(_m_TypeAliasDef_read(input));
        }
        while (_bi1842 < base.constrained_aliases.count) {
            var _c = _changed1827.try_get(_bi1842);
            _f1838.append(_c.is_value() ? _c.value() : base.constrained_aliases[_bi1842]);
            _bi1842 += 1;
        }
    } else if (_mode1841 == 3) {
        var _n1839 = input.count();
        for (var _ in 0.._n1839) {
            _f1838.append(_m_TypeAliasDef_read(input));
        }
    } else {
        var _n1839 = input.count();
        if (input.merging) {
            input.error = "constrained_aliases" + " written by place";
        }
        for (var _ in 0.._n1839) {
            var _tag1840 = input.unsigned();
            if (_tag1840 & 1 == 1) {
                if (!input.merging) {
                    _f1838.append(base.constrained_aliases[_tag1840 >> 1]);
                }
            } else {
                var _read = _m_TypeAliasDef_read(input);
                if (!input.merging or true) {
                    _f1838.append(_read);
                }
            }
        }
    }
    var _f1857 = Array<TraitType>();
    var _mode1860 = input.unsigned();
    if (_mode1860 == 2) {
        var _changed1846 = HashMap<ulong, TraitType>();
        ulong _bi1861 = 0;
        var _n1858 = input.count();
        for (var _ in 0.._n1858) {
            var _at1862 = input.unsigned();
            while (_f1857.count < _at1862 or (input.merging and _bi1861 < base.trait_types.count)) {
                var _c = _changed1846.try_get(_bi1861);
                _f1857.append(_c.is_value() ? _c.value() : base.trait_types[_bi1861]);
                _bi1861 += 1;
            }
            _f1857.append(_m_TraitType_read(input));
        }
        while (_bi1861 < base.trait_types.count) {
            var _c = _changed1846.try_get(_bi1861);
            _f1857.append(_c.is_value() ? _c.value() : base.trait_types[_bi1861]);
            _bi1861 += 1;
        }
    } else if (_mode1860 == 3) {
        var _n1858 = input.count();
        for (var _ in 0.._n1858) {
            _f1857.append(_m_TraitType_read(input));
        }
    } else {
        var _n1858 = input.count();
        if (input.merging) {
            input.error = "trait_types" + " written by place";
        }
        for (var _ in 0.._n1858) {
            var _tag1859 = input.unsigned();
            if (_tag1859 & 1 == 1) {
                if (!input.merging) {
                    _f1857.append(base.trait_types[_tag1859 >> 1]);
                }
            } else {
                var _read = _m_TraitType_read(input);
                if (!input.merging or true) {
                    _f1857.append(_read);
                }
            }
        }
    }
    var _v1868 = Array<Conversion>();
    var _n1869 = input.count();
    for (var _ in 0.._n1869) {
        _v1868.append(_m_Conversion_read(input));
    }
    var _f1870 = _v1868;
    var _f1897 = Map<String, Array<String>>();
    var _tag1898 = input.unsigned();
    if (_tag1898 == 1) {
        for (var (_bk1899, _bv) in base.overload_sets) {
            _f1897[_bk1899] = _bv;
        }
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
        for (var (_bk1899, _av) in _v1900) {
            _f1897[_bk1899] = _av;
        }
    } else {
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
        _f1897 = _v1905;
    }
    var _f1944 = Map<String, Array<Array<String>>>();
    var _tag1945 = input.unsigned();
    if (_tag1945 == 1) {
        for (var (_bk1946, _bv) in base.overload_unions) {
            _f1944[_bk1946] = _bv;
        }
        var _v1947 = Map<String, Array<Array<String>>>();
        var _n1948 = input.count();
        for (var _ in 0.._n1948) {
            var _k1949 = input.text();
            var _v1950 = Array<Array<String>>();
            var _n1951 = input.count();
            for (var _ in 0.._n1951) {
                var _v1952 = Array<String>();
                var _n1953 = input.count();
                for (var _ in 0.._n1953) {
                    _v1952.append(input.text());
                }
                _v1950.append(_v1952);
            }
            _v1947[_k1949] = _v1950;
        }
        for (var (_bk1946, _av) in _v1947) {
            _f1944[_bk1946] = _av;
        }
    } else {
        var _v1954 = Map<String, Array<Array<String>>>();
        var _n1955 = input.count();
        for (var _ in 0.._n1955) {
            var _k1956 = input.text();
            var _v1957 = Array<Array<String>>();
            var _n1958 = input.count();
            for (var _ in 0.._n1958) {
                var _v1959 = Array<String>();
                var _n1960 = input.count();
                for (var _ in 0.._n1960) {
                    _v1959.append(input.text());
                }
                _v1957.append(_v1959);
            }
            _v1954[_k1956] = _v1957;
        }
        _f1944 = _v1954;
    }
    var _f2031 = Map<String, Map<String, Array<String>>>();
    var _tag2032 = input.unsigned();
    if (_tag2032 == 1) {
        for (var (_bk2033, _bv) in base.method_overload_sets) {
            _f2031[_bk2033] = _bv;
        }
        var _v2034 = Map<String, Map<String, Array<String>>>();
        var _n2035 = input.count();
        for (var _ in 0.._n2035) {
            var _k2036 = input.text();
            var _v2037 = Map<String, Array<String>>();
            var _n2038 = input.count();
            for (var _ in 0.._n2038) {
                var _k2039 = input.text();
                var _v2040 = Array<String>();
                var _n2041 = input.count();
                for (var _ in 0.._n2041) {
                    _v2040.append(input.text());
                }
                _v2037[_k2039] = _v2040;
            }
            _v2034[_k2036] = _v2037;
        }
        for (var (_bk2033, _av) in _v2034) {
            _f2031[_bk2033] = _av;
        }
    } else {
        var _v2042 = Map<String, Map<String, Array<String>>>();
        var _n2043 = input.count();
        for (var _ in 0.._n2043) {
            var _k2044 = input.text();
            var _v2045 = Map<String, Array<String>>();
            var _n2046 = input.count();
            for (var _ in 0.._n2046) {
                var _k2047 = input.text();
                var _v2048 = Array<String>();
                var _n2049 = input.count();
                for (var _ in 0.._n2049) {
                    _v2048.append(input.text());
                }
                _v2045[_k2047] = _v2048;
            }
            _v2042[_k2044] = _v2045;
        }
        _f2031 = _v2042;
    }
    var _f2057 = _m_ExtensionScopes_read(input);
    var _f2077 = HashSet<Loc>();
    var _tag2078 = input.unsigned();
    if (_tag2078 == 1) {
        for (var _bk2079 in base.private_functions) {
            _f2077.insert(_bk2079);
        }
        var _v2080 = HashSet<Loc>();
        var _n2081 = input.count();
        for (var _ in 0.._n2081) {
            _v2080.insert(input.loc());
        }
        for (var _bk2079 in _v2080) {
            _f2077.insert(_bk2079);
        }
    } else {
        var _v2082 = HashSet<Loc>();
        var _n2083 = input.count();
        for (var _ in 0.._n2083) {
            _v2082.insert(input.loc());
        }
        _f2077 = _v2082;
    }
    var _f2103 = HashSet<Loc>();
    var _tag2104 = input.unsigned();
    if (_tag2104 == 1) {
        for (var _bk2105 in base.file_private_functions) {
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
    var _f2121 = Array<(Loc, String)>();
    var _tag2122 = input.unsigned();
    if (_tag2122 == 1) {
        input.unsigned();
        for (var _i2113 in 0..base.call_targets.count) {
            _f2121.append(base.call_targets[_i2113]);
        }
        var _more2124 = input.count();
        for (var _ in 0.._more2124) {
            var _t2125 = input.loc();
            var _t2126 = input.text();
            _f2121.append((_t2125, _t2126));
        }
    } else {
        var _v2127 = Array<(Loc, String)>();
        var _n2128 = input.count();
        for (var _ in 0.._n2128) {
            var _t2129 = input.loc();
            var _t2130 = input.text();
            _v2127.append((_t2129, _t2130));
        }
        _f2121 = _v2127;
    }
    var _f2147 = Array<(Loc, String)>();
    var _tag2148 = input.unsigned();
    if (_tag2148 == 1) {
        var _v2149 = Array<(Loc, String)>();
        var _n2150 = input.count();
        for (var _ in 0.._n2150) {
            var _t2151 = input.loc();
            var _t2152 = input.text();
            _v2149.append((_t2151, _t2152));
        }
        _f2147 = merge_by_place(base.argument_names, _v2149);
    } else {
        var _v2153 = Array<(Loc, String)>();
        var _n2154 = input.count();
        for (var _ in 0.._n2154) {
            var _t2155 = input.loc();
            var _t2156 = input.text();
            _v2153.append((_t2155, _t2156));
        }
        _f2147 = _v2153;
    }
    var _f2166 = Array<String>();
    var _tag2167 = input.unsigned();
    if (_tag2167 == 1) {
        input.unsigned();
        for (var _i2162 in 0..base.namespaces.count) {
            _f2166.append(base.namespaces[_i2162]);
        }
        var _more2169 = input.count();
        for (var _ in 0.._more2169) {
            _f2166.append(input.text());
        }
    } else {
        var _v2170 = Array<String>();
        var _n2171 = input.count();
        for (var _ in 0.._n2171) {
            _v2170.append(input.text());
        }
        _f2166 = _v2170;
    }
    var _f2179 = Array<bool>();
    var _tag2180 = input.unsigned();
    if (_tag2180 == 1) {
        input.unsigned();
        for (var _i2177 in 0..base.cached_files.count) {
            _f2179.append(base.cached_files[_i2177]);
        }
        var _more2182 = input.count();
        for (var _ in 0.._more2182) {
            _f2179.append(input.flag());
        }
    } else {
        var _v2183 = Array<bool>();
        var _n2184 = input.count();
        for (var _ in 0.._n2184) {
            _v2183.append(input.flag());
        }
        _f2179 = _v2183;
    }
    var _f2202 = HashMap<Loc, String>();
    var _tag2203 = input.unsigned();
    if (_tag2203 == 1) {
        for (var (_bk2204, _bv) in base.recorded_summaries) {
            _f2202[_bk2204] = _bv;
        }
        var _v2205 = HashMap<Loc, String>();
        var _n2206 = input.count();
        for (var _ in 0.._n2206) {
            var _k2207 = input.loc();
            _v2205[_k2207] = input.text();
        }
        for (var (_bk2204, _av) in _v2205) {
            _f2202[_bk2204] = _av;
        }
    } else {
        var _v2208 = HashMap<Loc, String>();
        var _n2209 = input.count();
        for (var _ in 0.._n2209) {
            var _k2210 = input.loc();
            _v2208[_k2210] = input.text();
        }
        _f2202 = _v2208;
    }
    var _f2226 = HashSet<Loc>();
    var _tag2227 = input.unsigned();
    if (_tag2227 == 1) {
        for (var _bk2228 in base.stripped) {
            _f2226.insert(_bk2228);
        }
        var _v2229 = HashSet<Loc>();
        var _n2230 = input.count();
        for (var _ in 0.._n2230) {
            _v2229.insert(input.loc());
        }
        for (var _bk2228 in _v2229) {
            _f2226.insert(_bk2228);
        }
    } else {
        var _v2231 = HashSet<Loc>();
        var _n2232 = input.count();
        for (var _ in 0.._n2232) {
            _v2231.insert(input.loc());
        }
        _f2226 = _v2231;
    }
    var _frozen = input.flag();
    var _f2243 = Array<StructDef>();
    var _mode2246 = input.unsigned();
    if (_mode2246 == 2) {
        var _patched2249 = HashMap<ulong, StructDef>();
        var _n2244 = input.count();
        for (var _ in 0.._n2244) {
            var _name = input.text();
            var _slot = input.unsigned();
            if (input.merging) {
                _slot = struct_named(base.templates.structs, _name);
            }
            if (_slot >= base.templates.structs.count) {
                input.error = $"no struct {_name} to patch";
                break;
            }
            _patched2249[_slot] = _patch_t_read(input, base.templates.structs[_slot]);
        }
        ulong _bi2247 = 0;
        var _added = input.count();
        for (var _ in 0.._added) {
            var _at2248 = input.unsigned();
            while (_f2243.count < _at2248 or (input.merging and _bi2247 < base.templates.structs.count)) {
                var _p = _patched2249.try_get(_bi2247);
                _f2243.append(_p.is_value() ? _p.value() : base.templates.structs[_bi2247]);
                _bi2247 += 1;
            }
            _f2243.append(_m_StructDef_read(input));
        }
        while (_bi2247 < base.templates.structs.count) {
            var _p = _patched2249.try_get(_bi2247);
            _f2243.append(_p.is_value() ? _p.value() : base.templates.structs[_bi2247]);
            _bi2247 += 1;
        }
    } else {
        if (input.merging) {
            input.error = "structs written by place";
        }
        var _n2244 = input.count();
        for (var _ in 0.._n2244) {
            var _tag2245 = input.unsigned();
            if (_tag2245 & 1 == 1) {
                _f2243.append(
                    base.templates.structs[(_tag2245 >> 1) < base.templates.structs.count ? _tag2245 >> 1 : 0]
                );
            } else if (_tag2245 == 2) {
                var _was = base.templates.structs[input.unsigned()];
                _f2243.append(_patch_t_read(input, _was));
            } else {
                _f2243.append(_m_StructDef_read(input));
            }
        }
    }
    var _f2263 = Array<FunctionDef>();
    var _mode2266 = input.unsigned();
    if (_mode2266 == 2) {
        var _changed2252 = HashMap<ulong, FunctionDef>();
        var _nc2254 = input.count();
        for (var _ in 0.._nc2254) {
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
                _changed2252[_slot] = _el;
            } else {
                input.error = $"no {_name} to change";
            }
        }
        ulong _bi2267 = 0;
        var _n2264 = input.count();
        for (var _ in 0.._n2264) {
            var _at2268 = input.unsigned();
            while (_f2263.count < _at2268 or (input.merging and _bi2267 < base.templates.functions.count)) {
                var _c = _changed2252.try_get(_bi2267);
                _f2263.append(_c.is_value() ? _c.value() : base.templates.functions[_bi2267]);
                _bi2267 += 1;
            }
            _f2263.append(_m_FunctionDef_read(input));
        }
        while (_bi2267 < base.templates.functions.count) {
            var _c = _changed2252.try_get(_bi2267);
            _f2263.append(_c.is_value() ? _c.value() : base.templates.functions[_bi2267]);
            _bi2267 += 1;
        }
    } else if (_mode2266 == 3) {
        var _n2264 = input.count();
        for (var _ in 0.._n2264) {
            _f2263.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2264 = input.count();
        if (input.merging) {
            input.error = "tf" + " written by place";
        }
        for (var _ in 0.._n2264) {
            var _tag2265 = input.unsigned();
            if (_tag2265 & 1 == 1) {
                if (!input.merging) {
                    _f2263.append(base.templates.functions[_tag2265 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2263.append(_read);
                }
            }
        }
    }
    var _f2270 = Templates(_frozen, _f2243, _f2263);
    var _f2271 = DeltaBase.read_checked(input, base.checked);
    var _f2291 = HashMap<String, SpecRequest>();
    var _tag2292 = input.unsigned();
    if (_tag2292 == 1) {
        for (var (_bk2293, _bv) in base.spec_requests) {
            _f2291[_bk2293] = _bv;
        }
        var _v2294 = HashMap<String, SpecRequest>();
        var _n2295 = input.count();
        for (var _ in 0.._n2295) {
            var _k2296 = input.text();
            _v2294[_k2296] = _m_SpecRequest_read(input);
        }
        for (var (_bk2293, _av) in _v2294) {
            _f2291[_bk2293] = _av;
        }
    } else {
        var _v2297 = HashMap<String, SpecRequest>();
        var _n2298 = input.count();
        for (var _ in 0.._n2298) {
            var _k2299 = input.text();
            _v2297[_k2299] = _m_SpecRequest_read(input);
        }
        _f2291 = _v2297;
    }
    var _f2300 = input.flag();
    var _f2312 = Array<(Loc, String)>();
    var _tag2313 = input.unsigned();
    if (_tag2313 == 1) {
        input.unsigned();
        for (var _i2304 in 0..base.summaries_to_record.count) {
            _f2312.append(base.summaries_to_record[_i2304]);
        }
        var _more2315 = input.count();
        for (var _ in 0.._more2315) {
            var _t2316 = input.loc();
            var _t2317 = input.text();
            _f2312.append((_t2316, _t2317));
        }
    } else {
        var _v2318 = Array<(Loc, String)>();
        var _n2319 = input.count();
        for (var _ in 0.._n2319) {
            var _t2320 = input.loc();
            var _t2321 = input.text();
            _v2318.append((_t2320, _t2321));
        }
        _f2312 = _v2318;
    }
    var _f2352 = HashMap<String, Array<bool>>();
    var _tag2353 = input.unsigned();
    if (_tag2353 == 1) {
        for (var (_bk2354, _bv) in base.caller_copies) {
            _f2352[_bk2354] = _bv;
        }
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
        for (var (_bk2354, _av) in _v2355) {
            _f2352[_bk2354] = _av;
        }
    } else {
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
        _f2352 = _v2360;
    }
    var _f2366 = input.flag();
    return Module(
        _f1498,
        _f1531,
        _f1551,
        _f1570,
        _f1589,
        _f1608,
        _f1627,
        _f1646,
        _f1665,
        _f1684,
        _f1703,
        _f1715,
        _f1731,
        _f1750,
        _f1769,
        _f1788,
        _f1809,
        _f1838,
        _f1857,
        _f1870,
        _f1897,
        _f1944,
        _f2031,
        _f2057,
        _f2077,
        _f2103,
        _f2121,
        _f2147,
        _f2166,
        _f2179,
        _f2202,
        _f2226,
        _f2270,
        _f2271,
        _f2291,
        _f2300,
        _f2312,
        _f2352,
        _f2366
    );
}

_m_Module_index(value: Module, base: DeltaBase) {
    ulong _j1504 = 0;
    for (var _item1486 in value.imports) {
        var scratch = base.scratch();
        _a_Import_write(scratch, _item1486);
        base.add("imports", scratch, _j1504);
        _j1504 += 1;
    }
    if (base.verifying) {
        ulong _j1538 = 0;
        for (var _item1505 in value.structs) {
            var scratch = base.scratch();
            _m_StructDef_write(scratch, _item1505);
            base.add("s", scratch, _j1538);
            base.name("s", _item1505.name, _j1538);
            _patch_s_index(_item1505, base, _j1538);
            _j1538 += 1;
        }
    }
    base.ref_structs = value.structs.clone();
    base.ref_struct_parts = Array<StructDef>();
    for (var _item1505 in value.structs) {
        base.ref_struct_parts.append(_m_StructDef_shallow(_item1505));
    }
    ulong _j1557 = 0;
    for (var _item1539 in value.traits) {
        var scratch = base.scratch();
        _m_TraitDef_write(scratch, _item1539);
        base.add("traits", scratch, _j1557);
        _j1557 += 1;
    }
    ulong _j1576 = 0;
    for (var _item1558 in value.extensions) {
        var scratch = base.scratch();
        _m_ExtensionDef_write(scratch, _item1558);
        base.add("extensions", scratch, _j1576);
        _j1576 += 1;
    }
    if (base.verifying) {
        ulong _j1595 = 0;
        for (var _item1577 in value.functions) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item1577);
            base.add("functions", scratch, _j1595);
            base.name("functions", _item1577.name, _j1595);
            _j1595 += 1;
        }
    }
    base.ref_functions = value.functions.clone();
    ulong _j1614 = 0;
    for (var _item1596 in value.externs) {
        var scratch = base.scratch();
        _m_ExternDef_write(scratch, _item1596);
        base.add("externs", scratch, _j1614);
        _j1614 += 1;
    }
    ulong _j1633 = 0;
    for (var _item1615 in value.globals) {
        var scratch = base.scratch();
        _m_VariableDef_write(scratch, _item1615);
        base.add("globals", scratch, _j1633);
        _j1633 += 1;
    }
    ulong _j1652 = 0;
    for (var _item1634 in value.static_blocks) {
        var scratch = base.scratch();
        _m_ModuleStaticBlock_write(scratch, _item1634);
        base.add("static_blocks", scratch, _j1652);
        _j1652 += 1;
    }
    ulong _j1671 = 0;
    for (var _item1653 in value.enums) {
        var scratch = base.scratch();
        _m_EnumDef_write(scratch, _item1653);
        base.add("enums", scratch, _j1671);
        _j1671 += 1;
    }
    ulong _j1690 = 0;
    for (var _item1672 in value.struct_specs) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item1672);
        base.add("struct_specs", scratch, _j1690);
        _j1690 += 1;
    }
    ulong _j1709 = 0;
    for (var _item1691 in value.func_specs) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item1691);
        base.add("func_specs", scratch, _j1709);
        _j1709 += 1;
    }
    ulong _j1718 = 0;
    for (var _item1710 in value.type_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1710);
        base.add("type_aliases", scratch, _j1718);
        _j1718 += 1;
    }
    ulong _j1737 = 0;
    for (var _item1719 in value.withheld) {
        var scratch = base.scratch();
        _m_Withheld_write(scratch, _item1719);
        base.add("withheld", scratch, _j1737);
        _j1737 += 1;
    }
    ulong _j1756 = 0;
    for (var _item1738 in value.properties) {
        var scratch = base.scratch();
        _m_PropertyDef_write(scratch, _item1738);
        base.add("properties", scratch, _j1756);
        _j1756 += 1;
    }
    ulong _j1775 = 0;
    for (var _item1757 in value.type_uses) {
        var scratch = base.scratch();
        _m_TypeUse_write(scratch, _item1757);
        base.add("type_uses", scratch, _j1775);
        _j1775 += 1;
    }
    ulong _j1794 = 0;
    for (var _item1776 in value.use_contexts) {
        var scratch = base.scratch();
        _m_UseContext_write(scratch, _item1776);
        base.add("use_contexts", scratch, _j1794);
        _j1794 += 1;
    }
    var _xscratch1821 = base.scratch();
    for (var _xitem1822 in value.literal_args) {
        var (_t1823, _t1824, _t1825) = _xitem1822;
        _xscratch1821.loc(_t1823);
        _xscratch1821.unsigned(_t1824);
        _xscratch1821.loc(_t1825);
    }
    base.keep_list("literal_args", value.literal_args.count, _xscratch1821);
    ulong _j1844 = 0;
    for (var _item1826 in value.constrained_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1826);
        base.add("constrained_aliases", scratch, _j1844);
        _j1844 += 1;
    }
    ulong _j1863 = 0;
    for (var _item1845 in value.trait_types) {
        var scratch = base.scratch();
        _m_TraitType_write(scratch, _item1845);
        base.add("trait_types", scratch, _j1863);
        _j1863 += 1;
    }
    ulong _cj1867 = 0;
    for (var _conv1865 in value.conversions) {
        var _own1866 = RecordOut();
        _own1866.blank_locs = true;
        _m_Conversion_write(_own1866, _conv1865);
        base.add_hashed("conversions", interface_text(_own1866), _cj1867);
        _cj1867 += 1;
    }
    for (var (_key1871, _) in value.overload_sets) {
        var _kscratch1872 = base.scratch();
        _kscratch1872.text(_key1871);
        var _vscratch1873 = base.scratch();
        _vscratch1873.unsigned(value.overload_sets[_key1871].count);
        for (var _item1910 in value.overload_sets[_key1871]) {
            _vscratch1873.text(_item1910);
        }
        base.keep_entry("overload_sets", _kscratch1872, _vscratch1873);
    }
    for (var (_key1911, _) in value.overload_unions) {
        var _kscratch1912 = base.scratch();
        _kscratch1912.text(_key1911);
        var _vscratch1913 = base.scratch();
        _vscratch1913.unsigned(value.overload_unions[_key1911].count);
        for (var _item1961 in value.overload_unions[_key1911]) {
            _vscratch1913.unsigned(_item1961.count);
            for (var _item1962 in _item1961) {
                _vscratch1913.text(_item1962);
            }
        }
        base.keep_entry("overload_unions", _kscratch1912, _vscratch1913);
    }
    for (var (_key1963, _) in value.method_overload_sets) {
        var _kscratch1964 = base.scratch();
        _kscratch1964.text(_key1963);
        var _vscratch1965 = base.scratch();
        var _keys2051 = Array<(u8[], u8[], String)>();
        for (var (_key2050, _) in value.method_overload_sets[_key1963]) {
            var _scratch2052 = _vscratch1965.scratch();
            _scratch2052.text(_key2050);
            var _vscratch2054 = _vscratch1965.scratch();
            _vscratch2054.unsigned(value.method_overload_sets[_key1963][_key2050].count);
            for (var _item2055 in value.method_overload_sets[_key1963][_key2050]) {
                _vscratch2054.text(_item2055);
            }
            _keys2051.append((_scratch2052.finish(), _vscratch2054.finish(), _key2050));
        }
        _keys2051.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        _vscratch1965.unsigned(_keys2051.count);
        for (var (_bytes2053, _, _key2050) in _keys2051) {
            _vscratch1965.text(_key2050);
            _vscratch1965.unsigned(value.method_overload_sets[_key1963][_key2050].count);
            for (var _item2056 in value.method_overload_sets[_key1963][_key2050]) {
                _vscratch1965.text(_item2056);
            }
        }
        base.keep_entry("method_overload_sets", _kscratch1964, _vscratch1965);
    }
    for (var _key2058 in value.private_functions) {
        var _kscratch2059 = base.scratch();
        _kscratch2059.loc(_key2058);
        var _vscratch2060 = base.scratch();
        base.keep_entry("private_functions", _kscratch2059, _vscratch2060);
    }
    for (var _key2084 in value.file_private_functions) {
        var _kscratch2085 = base.scratch();
        _kscratch2085.loc(_key2084);
        var _vscratch2086 = base.scratch();
        base.keep_entry("file_private_functions", _kscratch2085, _vscratch2086);
    }
    var _xscratch2131 = base.scratch();
    for (var _xitem2132 in value.call_targets) {
        var (_t2133, _t2134) = _xitem2132;
        _xscratch2131.loc(_t2133);
        _xscratch2131.text(_t2134);
    }
    base.keep_list("call_targets", value.call_targets.count, _xscratch2131);
    for (var _item2135 in value.argument_names) {
        var _escratch2136 = base.scratch();
        var (_t2157, _t2158) = _item2135;
        _escratch2136.loc(_t2157);
        _escratch2136.text(_t2158);
        base.keep_entry("argument_names", _escratch2136, base.scratch());
    }
    var _xscratch2172 = base.scratch();
    for (var _xitem2173 in value.namespaces) {
        _xscratch2172.text(_xitem2173);
    }
    base.keep_list("namespaces", value.namespaces.count, _xscratch2172);
    var _xscratch2185 = base.scratch();
    for (var _xitem2186 in value.cached_files) {
        _xscratch2185.flag(_xitem2186);
    }
    base.keep_list("cached_files", value.cached_files.count, _xscratch2185);
    for (var (_key2187, _) in value.recorded_summaries) {
        var _kscratch2188 = base.scratch();
        _kscratch2188.loc(_key2187);
        var _vscratch2189 = base.scratch();
        _vscratch2189.text(value.recorded_summaries[_key2187]);
        base.keep_entry("recorded_summaries", _kscratch2188, _vscratch2189);
    }
    for (var _key2211 in value.stripped) {
        var _kscratch2212 = base.scratch();
        _kscratch2212.loc(_key2211);
        var _vscratch2213 = base.scratch();
        base.keep_entry("stripped", _kscratch2212, _vscratch2213);
    }
    if (base.verifying) {
        ulong _j2250 = 0;
        for (var _item2233 in value.templates.structs) {
            var scratch = base.scratch();
            _m_StructDef_write(scratch, _item2233);
            base.add("t", scratch, _j2250);
            base.name("t", _item2233.name, _j2250);
            _patch_t_index(_item2233, base, _j2250);
            _j2250 += 1;
        }
    }
    base.ref_templates = value.templates.structs.clone();
    base.ref_template_parts = Array<StructDef>();
    for (var _item2233 in value.templates.structs) {
        base.ref_template_parts.append(_m_StructDef_shallow(_item2233));
    }
    if (base.verifying) {
        ulong _j2269 = 0;
        for (var _item2251 in value.templates.functions) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2251);
            base.add("tf", scratch, _j2269);
            base.name("tf", _item2251.name, _j2269);
            _j2269 += 1;
        }
    }
    base.ref_template_functions = value.templates.functions.clone();
    base.keep_checked(value.checked);
    for (var (_key2272, _) in value.spec_requests) {
        var _kscratch2273 = base.scratch();
        _kscratch2273.text(_key2272);
        var _vscratch2274 = base.scratch();
        _m_SpecRequest_write(_vscratch2274, value.spec_requests[_key2272]);
        base.keep_entry("spec_requests", _kscratch2273, _vscratch2274);
    }
    var _xscratch2322 = base.scratch();
    for (var _xitem2323 in value.summaries_to_record) {
        var (_t2324, _t2325) = _xitem2323;
        _xscratch2322.loc(_t2324);
        _xscratch2322.text(_t2325);
    }
    base.keep_list("summaries_to_record", value.summaries_to_record.count, _xscratch2322);
    for (var (_key2326, _) in value.caller_copies) {
        var _kscratch2327 = base.scratch();
        _kscratch2327.text(_key2326);
        var _vscratch2328 = base.scratch();
        _vscratch2328.unsigned(value.caller_copies[_key2326].count);
        for (var _item2365 in value.caller_copies[_key2326]) {
            _vscratch2328.flag(_item2365);
        }
        base.keep_entry("caller_copies", _kscratch2327, _vscratch2328);
    }
}

_m_Module_index_resumed(value: Module, base: DeltaBase) {
    ulong _j1718 = 0;
    for (var _item1710 in value.type_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1710);
        base.add("type_aliases", scratch, _j1718);
        _j1718 += 1;
    }
    for (var (_key2187, _) in value.recorded_summaries) {
        var _kscratch2188 = base.scratch();
        _kscratch2188.loc(_key2187);
        var _vscratch2189 = base.scratch();
        _vscratch2189.text(value.recorded_summaries[_key2187]);
        base.keep_entry("recorded_summaries", _kscratch2188, _vscratch2189);
    }
    var _xscratch2322 = base.scratch();
    for (var _xitem2323 in value.summaries_to_record) {
        var (_t2324, _t2325) = _xitem2323;
        _xscratch2322.loc(_t2324);
        _xscratch2322.text(_t2325);
    }
    base.keep_list("summaries_to_record", value.summaries_to_record.count, _xscratch2322);
}

_patch_s_write(out: RecordOut, value: StructDef, base: DeltaBase, slot: ulong) {
    out.text(value.name);
    _m_TypeName_write(out, value.ty);
    var _seq2374 = base.ref_struct_parts[slot].generic_params;
    ulong _bj2375 = 0;
    var _news2376 = Array<ulong>();
    for (var _i2377 in 0..value.generic_params.count) {
        if (_bj2375 < _seq2374.count and value.generic_params[_i2377] === _seq2374[_bj2375]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_GenericParam_write(scratch, value.generic_params[_i2377]);
                base.verify_same($"s.{slot}.generic_params", _bj2375, scratch);
            }
            _bj2375 += 1;
        } else if (_bj2375 < _seq2374.count
            and _same_m_GenericParam(value.generic_params[_i2377], _seq2374[_bj2375], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_GenericParam_write(scratch, value.generic_params[_i2377]);
                base.verify_same($"s.{slot}.generic_params", _bj2375, scratch);
            }
            _bj2375 += 1;
        } else {
            _news2376.append(_i2377);
        }
    }
    if (_bj2375 == _seq2374.count) {
        out.unsigned(2);
        out.unsigned(_news2376.count);
        for (var _i2377 in _news2376) {
            out.unsigned(_i2377);
            _m_GenericParam_write(out, value.generic_params[_i2377]);
        }
        base.count("s.*.generic_params" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.generic_params" + " whole", 0);
        out.unsigned(value.generic_params.count);
        for (var _i2377 in 0..value.generic_params.count) {
            _m_GenericParam_write(out, value.generic_params[_i2377]);
        }
    }
    var _seq2390 = base.ref_struct_parts[slot].field_members;
    ulong _bj2391 = 0;
    var _news2392 = Array<ulong>();
    for (var _i2393 in 0..value.field_members.count) {
        if (_bj2391 < _seq2390.count and value.field_members[_i2393] === _seq2390[_bj2391]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_VariableDef_write(scratch, value.field_members[_i2393]);
                base.verify_same($"s.{slot}.field_members", _bj2391, scratch);
            }
            _bj2391 += 1;
        } else if (_bj2391 < _seq2390.count
            and _same_m_VariableDef(value.field_members[_i2393], _seq2390[_bj2391], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_VariableDef_write(scratch, value.field_members[_i2393]);
                base.verify_same($"s.{slot}.field_members", _bj2391, scratch);
            }
            _bj2391 += 1;
        } else {
            _news2392.append(_i2393);
        }
    }
    if (_bj2391 == _seq2390.count) {
        out.unsigned(2);
        out.unsigned(_news2392.count);
        for (var _i2393 in _news2392) {
            out.unsigned(_i2393);
            _m_VariableDef_write(out, value.field_members[_i2393]);
        }
        base.count("s.*.field_members" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.field_members" + " whole", 0);
        out.unsigned(value.field_members.count);
        for (var _i2393 in 0..value.field_members.count) {
            _m_VariableDef_write(out, value.field_members[_i2393]);
        }
    }
    var _seq2406 = base.ref_struct_parts[slot].method_members;
    ulong _bj2407 = 0;
    var _news2408 = Array<ulong>();
    for (var _i2409 in 0..value.method_members.count) {
        if (_bj2407 < _seq2406.count and value.method_members[_i2409] === _seq2406[_bj2407]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.method_members[_i2409]);
                base.verify_same($"s.{slot}.method_members", _bj2407, scratch);
            }
            _bj2407 += 1;
        } else if (_bj2407 < _seq2406.count
            and _same_m_FunctionDef(value.method_members[_i2409], _seq2406[_bj2407], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.method_members[_i2409]);
                base.verify_same($"s.{slot}.method_members", _bj2407, scratch);
            }
            _bj2407 += 1;
        } else {
            _news2408.append(_i2409);
        }
    }
    if (_bj2407 == _seq2406.count) {
        out.unsigned(2);
        out.unsigned(_news2408.count);
        for (var _i2409 in _news2408) {
            out.unsigned(_i2409);
            _m_FunctionDef_write(out, value.method_members[_i2409]);
        }
        base.count("s.*.method_members" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.method_members" + " whole", 0);
        out.unsigned(value.method_members.count);
        for (var _i2409 in 0..value.method_members.count) {
            _m_FunctionDef_write(out, value.method_members[_i2409]);
        }
    }
    var _seq2422 = base.ref_struct_parts[slot].generic_methods;
    ulong _bj2423 = 0;
    var _news2424 = Array<ulong>();
    for (var _i2425 in 0..value.generic_methods.count) {
        if (_bj2423 < _seq2422.count and value.generic_methods[_i2425] === _seq2422[_bj2423]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.generic_methods[_i2425]);
                base.verify_same($"s.{slot}.generic_methods", _bj2423, scratch);
            }
            _bj2423 += 1;
        } else if (_bj2423 < _seq2422.count
            and _same_m_FunctionDef(value.generic_methods[_i2425], _seq2422[_bj2423], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.generic_methods[_i2425]);
                base.verify_same($"s.{slot}.generic_methods", _bj2423, scratch);
            }
            _bj2423 += 1;
        } else {
            _news2424.append(_i2425);
        }
    }
    if (_bj2423 == _seq2422.count) {
        out.unsigned(2);
        out.unsigned(_news2424.count);
        for (var _i2425 in _news2424) {
            out.unsigned(_i2425);
            _m_FunctionDef_write(out, value.generic_methods[_i2425]);
        }
        base.count("s.*.generic_methods" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.generic_methods" + " whole", 0);
        out.unsigned(value.generic_methods.count);
        for (var _i2425 in 0..value.generic_methods.count) {
            _m_FunctionDef_write(out, value.generic_methods[_i2425]);
        }
    }
    var _seq2438 = base.ref_struct_parts[slot].constructors;
    ulong _bj2439 = 0;
    var _news2440 = Array<ulong>();
    for (var _i2441 in 0..value.constructors.count) {
        if (_bj2439 < _seq2438.count and value.constructors[_i2441] === _seq2438[_bj2439]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.constructors[_i2441]);
                base.verify_same($"s.{slot}.constructors", _bj2439, scratch);
            }
            _bj2439 += 1;
        } else if (_bj2439 < _seq2438.count
            and _same_m_FunctionDef(value.constructors[_i2441], _seq2438[_bj2439], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.constructors[_i2441]);
                base.verify_same($"s.{slot}.constructors", _bj2439, scratch);
            }
            _bj2439 += 1;
        } else {
            _news2440.append(_i2441);
        }
    }
    if (_bj2439 == _seq2438.count) {
        out.unsigned(2);
        out.unsigned(_news2440.count);
        for (var _i2441 in _news2440) {
            out.unsigned(_i2441);
            _m_FunctionDef_write(out, value.constructors[_i2441]);
        }
        base.count("s.*.constructors" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.constructors" + " whole", 0);
        out.unsigned(value.constructors.count);
        for (var _i2441 in 0..value.constructors.count) {
            _m_FunctionDef_write(out, value.constructors[_i2441]);
        }
    }
    _m_FunctionDef_write(out, value.destructor);
    _m_FunctionDef_write(out, value.acquire);
    _m_FunctionDef_write(out, value.release);
    var _seq2457 = base.ref_struct_parts[slot].traits;
    ulong _bj2458 = 0;
    var _news2459 = Array<ulong>();
    for (var _i2460 in 0..value.traits.count) {
        if (_bj2458 < _seq2457.count and value.traits[_i2460] === _seq2457[_bj2458]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_TypeName_write(scratch, value.traits[_i2460]);
                base.verify_same($"s.{slot}.traits", _bj2458, scratch);
            }
            _bj2458 += 1;
        } else if (_bj2458 < _seq2457.count and _same_m_TypeName(value.traits[_i2460], _seq2457[_bj2458], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_TypeName_write(scratch, value.traits[_i2460]);
                base.verify_same($"s.{slot}.traits", _bj2458, scratch);
            }
            _bj2458 += 1;
        } else {
            _news2459.append(_i2460);
        }
    }
    if (_bj2458 == _seq2457.count) {
        out.unsigned(2);
        out.unsigned(_news2459.count);
        for (var _i2460 in _news2459) {
            out.unsigned(_i2460);
            _m_TypeName_write(out, value.traits[_i2460]);
        }
        base.count("s.*.traits" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.traits" + " whole", 0);
        out.unsigned(value.traits.count);
        for (var _i2460 in 0..value.traits.count) {
            _m_TypeName_write(out, value.traits[_i2460]);
        }
    }
    var _seq2473 = base.ref_struct_parts[slot].attributes;
    ulong _bj2474 = 0;
    var _news2475 = Array<ulong>();
    for (var _i2476 in 0..value.attributes.count) {
        if (_bj2474 < _seq2473.count and value.attributes[_i2476] === _seq2473[_bj2474]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _a_Attribute_write(scratch, value.attributes[_i2476]);
                base.verify_same($"s.{slot}.attributes", _bj2474, scratch);
            }
            _bj2474 += 1;
        } else if (_bj2474 < _seq2473.count and _same_a_Attribute(value.attributes[_i2476], _seq2473[_bj2474], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _a_Attribute_write(scratch, value.attributes[_i2476]);
                base.verify_same($"s.{slot}.attributes", _bj2474, scratch);
            }
            _bj2474 += 1;
        } else {
            _news2475.append(_i2476);
        }
    }
    if (_bj2474 == _seq2473.count) {
        out.unsigned(2);
        out.unsigned(_news2475.count);
        for (var _i2476 in _news2475) {
            out.unsigned(_i2476);
            _a_Attribute_write(out, value.attributes[_i2476]);
        }
        base.count("s.*.attributes" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.attributes" + " whole", 0);
        out.unsigned(value.attributes.count);
        for (var _i2476 in 0..value.attributes.count) {
            _a_Attribute_write(out, value.attributes[_i2476]);
        }
    }
    out.loc(value.loc);
    if (value.enum_cases.is_value()) {
        out.unsigned(1);
        out.unsigned(value.enum_cases.value().count);
        for (var _item2485 in value.enum_cases.value()) {
            _m_EnumCaseDef_write(out, _item2485);
        }
    } else {
        out.unsigned(0);
    }
}

_patch_s_read(input: RecordIn, was: StructDef): StructDef {
    var _f2367 = input.text();
    var _f2368 = _m_TypeName_read(input);
    var _f2378 = Array<GenericParam>();
    var _mode2381 = input.unsigned();
    if (_mode2381 == 2) {
        var _changed2370 = HashMap<ulong, GenericParam>();
        ulong _bi2382 = 0;
        var _n2379 = input.count();
        for (var _ in 0.._n2379) {
            var _at2383 = input.unsigned();
            while (_f2378.count < _at2383 or (input.merging and _bi2382 < was.generic_params.count)) {
                var _c = _changed2370.try_get(_bi2382);
                _f2378.append(_c.is_value() ? _c.value() : was.generic_params[_bi2382]);
                _bi2382 += 1;
            }
            _f2378.append(_m_GenericParam_read(input));
        }
        while (_bi2382 < was.generic_params.count) {
            var _c = _changed2370.try_get(_bi2382);
            _f2378.append(_c.is_value() ? _c.value() : was.generic_params[_bi2382]);
            _bi2382 += 1;
        }
    } else if (_mode2381 == 3) {
        var _n2379 = input.count();
        for (var _ in 0.._n2379) {
            _f2378.append(_m_GenericParam_read(input));
        }
    } else {
        var _n2379 = input.count();
        if (input.merging) {
            input.error = "s.*.generic_params" + " written by place";
        }
        for (var _ in 0.._n2379) {
            var _tag2380 = input.unsigned();
            if (_tag2380 & 1 == 1) {
                if (!input.merging) {
                    _f2378.append(was.generic_params[_tag2380 >> 1]);
                }
            } else {
                var _read = _m_GenericParam_read(input);
                if (!input.merging or true) {
                    _f2378.append(_read);
                }
            }
        }
    }
    var _f2394 = Array<VariableDef>();
    var _mode2397 = input.unsigned();
    if (_mode2397 == 2) {
        var _changed2386 = HashMap<ulong, VariableDef>();
        ulong _bi2398 = 0;
        var _n2395 = input.count();
        for (var _ in 0.._n2395) {
            var _at2399 = input.unsigned();
            while (_f2394.count < _at2399 or (input.merging and _bi2398 < was.field_members.count)) {
                var _c = _changed2386.try_get(_bi2398);
                _f2394.append(_c.is_value() ? _c.value() : was.field_members[_bi2398]);
                _bi2398 += 1;
            }
            _f2394.append(_m_VariableDef_read(input));
        }
        while (_bi2398 < was.field_members.count) {
            var _c = _changed2386.try_get(_bi2398);
            _f2394.append(_c.is_value() ? _c.value() : was.field_members[_bi2398]);
            _bi2398 += 1;
        }
    } else if (_mode2397 == 3) {
        var _n2395 = input.count();
        for (var _ in 0.._n2395) {
            _f2394.append(_m_VariableDef_read(input));
        }
    } else {
        var _n2395 = input.count();
        if (input.merging) {
            input.error = "s.*.field_members" + " written by place";
        }
        for (var _ in 0.._n2395) {
            var _tag2396 = input.unsigned();
            if (_tag2396 & 1 == 1) {
                if (!input.merging) {
                    _f2394.append(was.field_members[_tag2396 >> 1]);
                }
            } else {
                var _read = _m_VariableDef_read(input);
                if (!input.merging or true) {
                    _f2394.append(_read);
                }
            }
        }
    }
    var _f2410 = Array<FunctionDef>();
    var _mode2413 = input.unsigned();
    if (_mode2413 == 2) {
        var _changed2402 = HashMap<ulong, FunctionDef>();
        ulong _bi2414 = 0;
        var _n2411 = input.count();
        for (var _ in 0.._n2411) {
            var _at2415 = input.unsigned();
            while (_f2410.count < _at2415 or (input.merging and _bi2414 < was.method_members.count)) {
                var _c = _changed2402.try_get(_bi2414);
                _f2410.append(_c.is_value() ? _c.value() : was.method_members[_bi2414]);
                _bi2414 += 1;
            }
            _f2410.append(_m_FunctionDef_read(input));
        }
        while (_bi2414 < was.method_members.count) {
            var _c = _changed2402.try_get(_bi2414);
            _f2410.append(_c.is_value() ? _c.value() : was.method_members[_bi2414]);
            _bi2414 += 1;
        }
    } else if (_mode2413 == 3) {
        var _n2411 = input.count();
        for (var _ in 0.._n2411) {
            _f2410.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2411 = input.count();
        if (input.merging) {
            input.error = "s.*.method_members" + " written by place";
        }
        for (var _ in 0.._n2411) {
            var _tag2412 = input.unsigned();
            if (_tag2412 & 1 == 1) {
                if (!input.merging) {
                    _f2410.append(was.method_members[_tag2412 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2410.append(_read);
                }
            }
        }
    }
    var _f2426 = Array<FunctionDef>();
    var _mode2429 = input.unsigned();
    if (_mode2429 == 2) {
        var _changed2418 = HashMap<ulong, FunctionDef>();
        ulong _bi2430 = 0;
        var _n2427 = input.count();
        for (var _ in 0.._n2427) {
            var _at2431 = input.unsigned();
            while (_f2426.count < _at2431 or (input.merging and _bi2430 < was.generic_methods.count)) {
                var _c = _changed2418.try_get(_bi2430);
                _f2426.append(_c.is_value() ? _c.value() : was.generic_methods[_bi2430]);
                _bi2430 += 1;
            }
            _f2426.append(_m_FunctionDef_read(input));
        }
        while (_bi2430 < was.generic_methods.count) {
            var _c = _changed2418.try_get(_bi2430);
            _f2426.append(_c.is_value() ? _c.value() : was.generic_methods[_bi2430]);
            _bi2430 += 1;
        }
    } else if (_mode2429 == 3) {
        var _n2427 = input.count();
        for (var _ in 0.._n2427) {
            _f2426.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2427 = input.count();
        if (input.merging) {
            input.error = "s.*.generic_methods" + " written by place";
        }
        for (var _ in 0.._n2427) {
            var _tag2428 = input.unsigned();
            if (_tag2428 & 1 == 1) {
                if (!input.merging) {
                    _f2426.append(was.generic_methods[_tag2428 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2426.append(_read);
                }
            }
        }
    }
    var _f2442 = Array<FunctionDef>();
    var _mode2445 = input.unsigned();
    if (_mode2445 == 2) {
        var _changed2434 = HashMap<ulong, FunctionDef>();
        ulong _bi2446 = 0;
        var _n2443 = input.count();
        for (var _ in 0.._n2443) {
            var _at2447 = input.unsigned();
            while (_f2442.count < _at2447 or (input.merging and _bi2446 < was.constructors.count)) {
                var _c = _changed2434.try_get(_bi2446);
                _f2442.append(_c.is_value() ? _c.value() : was.constructors[_bi2446]);
                _bi2446 += 1;
            }
            _f2442.append(_m_FunctionDef_read(input));
        }
        while (_bi2446 < was.constructors.count) {
            var _c = _changed2434.try_get(_bi2446);
            _f2442.append(_c.is_value() ? _c.value() : was.constructors[_bi2446]);
            _bi2446 += 1;
        }
    } else if (_mode2445 == 3) {
        var _n2443 = input.count();
        for (var _ in 0.._n2443) {
            _f2442.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2443 = input.count();
        if (input.merging) {
            input.error = "s.*.constructors" + " written by place";
        }
        for (var _ in 0.._n2443) {
            var _tag2444 = input.unsigned();
            if (_tag2444 & 1 == 1) {
                if (!input.merging) {
                    _f2442.append(was.constructors[_tag2444 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2442.append(_read);
                }
            }
        }
    }
    var _f2449 = _m_FunctionDef_read(input);
    var _f2450 = _m_FunctionDef_read(input);
    var _f2451 = _m_FunctionDef_read(input);
    var _f2461 = Array<TypeName>();
    var _mode2464 = input.unsigned();
    if (_mode2464 == 2) {
        var _changed2453 = HashMap<ulong, TypeName>();
        ulong _bi2465 = 0;
        var _n2462 = input.count();
        for (var _ in 0.._n2462) {
            var _at2466 = input.unsigned();
            while (_f2461.count < _at2466 or (input.merging and _bi2465 < was.traits.count)) {
                var _c = _changed2453.try_get(_bi2465);
                _f2461.append(_c.is_value() ? _c.value() : was.traits[_bi2465]);
                _bi2465 += 1;
            }
            _f2461.append(_m_TypeName_read(input));
        }
        while (_bi2465 < was.traits.count) {
            var _c = _changed2453.try_get(_bi2465);
            _f2461.append(_c.is_value() ? _c.value() : was.traits[_bi2465]);
            _bi2465 += 1;
        }
    } else if (_mode2464 == 3) {
        var _n2462 = input.count();
        for (var _ in 0.._n2462) {
            _f2461.append(_m_TypeName_read(input));
        }
    } else {
        var _n2462 = input.count();
        if (input.merging) {
            input.error = "s.*.traits" + " written by place";
        }
        for (var _ in 0.._n2462) {
            var _tag2463 = input.unsigned();
            if (_tag2463 & 1 == 1) {
                if (!input.merging) {
                    _f2461.append(was.traits[_tag2463 >> 1]);
                }
            } else {
                var _read = _m_TypeName_read(input);
                if (!input.merging or true) {
                    _f2461.append(_read);
                }
            }
        }
    }
    var _f2477 = Array<ast.Attribute>();
    var _mode2480 = input.unsigned();
    if (_mode2480 == 2) {
        var _changed2469 = HashMap<ulong, ast.Attribute>();
        ulong _bi2481 = 0;
        var _n2478 = input.count();
        for (var _ in 0.._n2478) {
            var _at2482 = input.unsigned();
            while (_f2477.count < _at2482 or (input.merging and _bi2481 < was.attributes.count)) {
                var _c = _changed2469.try_get(_bi2481);
                _f2477.append(_c.is_value() ? _c.value() : was.attributes[_bi2481]);
                _bi2481 += 1;
            }
            _f2477.append(_a_Attribute_read(input));
        }
        while (_bi2481 < was.attributes.count) {
            var _c = _changed2469.try_get(_bi2481);
            _f2477.append(_c.is_value() ? _c.value() : was.attributes[_bi2481]);
            _bi2481 += 1;
        }
    } else if (_mode2480 == 3) {
        var _n2478 = input.count();
        for (var _ in 0.._n2478) {
            _f2477.append(_a_Attribute_read(input));
        }
    } else {
        var _n2478 = input.count();
        if (input.merging) {
            input.error = "s.*.attributes" + " written by place";
        }
        for (var _ in 0.._n2478) {
            var _tag2479 = input.unsigned();
            if (_tag2479 & 1 == 1) {
                if (!input.merging) {
                    _f2477.append(was.attributes[_tag2479 >> 1]);
                }
            } else {
                var _read = _a_Attribute_read(input);
                if (!input.merging or true) {
                    _f2477.append(_read);
                }
            }
        }
    }
    var _f2484 = input.loc();
    var _o2486 = Optional<Array<EnumCaseDef>>.Empty;
    if (input.unsigned() == 1) {
        var _v2487 = Array<EnumCaseDef>();
        var _n2488 = input.count();
        for (var _ in 0.._n2488) {
            _v2487.append(_m_EnumCaseDef_read(input));
        }
        _o2486 = Optional<Array<EnumCaseDef>>.Value(_v2487);
    }
    var _f2489 = _o2486;
    return StructDef(
        _f2367, _f2368, _f2378, _f2394, _f2410, _f2426, _f2442, _f2449, _f2450, _f2451, _f2461, _f2477, _f2484, _f2489
    );
}

_patch_s_index(value: StructDef, base: DeltaBase, slot: ulong) {
    if (base.verifying) {
        ulong _j2384 = 0;
        for (var _item2369 in value.generic_params) {
            var scratch = base.scratch();
            _m_GenericParam_write(scratch, _item2369);
            base.add($"s.{slot}.generic_params", scratch, _j2384);
            _j2384 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2400 = 0;
        for (var _item2385 in value.field_members) {
            var scratch = base.scratch();
            _m_VariableDef_write(scratch, _item2385);
            base.add($"s.{slot}.field_members", scratch, _j2400);
            _j2400 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2416 = 0;
        for (var _item2401 in value.method_members) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2401);
            base.add($"s.{slot}.method_members", scratch, _j2416);
            _j2416 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2432 = 0;
        for (var _item2417 in value.generic_methods) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2417);
            base.add($"s.{slot}.generic_methods", scratch, _j2432);
            _j2432 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2448 = 0;
        for (var _item2433 in value.constructors) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2433);
            base.add($"s.{slot}.constructors", scratch, _j2448);
            _j2448 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2467 = 0;
        for (var _item2452 in value.traits) {
            var scratch = base.scratch();
            _m_TypeName_write(scratch, _item2452);
            base.add($"s.{slot}.traits", scratch, _j2467);
            _j2467 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2483 = 0;
        for (var _item2468 in value.attributes) {
            var scratch = base.scratch();
            _a_Attribute_write(scratch, _item2468);
            base.add($"s.{slot}.attributes", scratch, _j2483);
            _j2483 += 1;
        }
    }
}

_patch_t_write(out: RecordOut, value: StructDef, base: DeltaBase, slot: ulong) {
    out.text(value.name);
    _m_TypeName_write(out, value.ty);
    var _seq2497 = base.ref_template_parts[slot].generic_params;
    ulong _bj2498 = 0;
    var _news2499 = Array<ulong>();
    for (var _i2500 in 0..value.generic_params.count) {
        if (_bj2498 < _seq2497.count and value.generic_params[_i2500] === _seq2497[_bj2498]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_GenericParam_write(scratch, value.generic_params[_i2500]);
                base.verify_same($"t.{slot}.generic_params", _bj2498, scratch);
            }
            _bj2498 += 1;
        } else if (_bj2498 < _seq2497.count
            and _same_m_GenericParam(value.generic_params[_i2500], _seq2497[_bj2498], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_GenericParam_write(scratch, value.generic_params[_i2500]);
                base.verify_same($"t.{slot}.generic_params", _bj2498, scratch);
            }
            _bj2498 += 1;
        } else {
            _news2499.append(_i2500);
        }
    }
    if (_bj2498 == _seq2497.count) {
        out.unsigned(2);
        out.unsigned(_news2499.count);
        for (var _i2500 in _news2499) {
            out.unsigned(_i2500);
            _m_GenericParam_write(out, value.generic_params[_i2500]);
        }
        base.count("t.*.generic_params" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.generic_params" + " whole", 0);
        out.unsigned(value.generic_params.count);
        for (var _i2500 in 0..value.generic_params.count) {
            _m_GenericParam_write(out, value.generic_params[_i2500]);
        }
    }
    var _seq2513 = base.ref_template_parts[slot].field_members;
    ulong _bj2514 = 0;
    var _news2515 = Array<ulong>();
    for (var _i2516 in 0..value.field_members.count) {
        if (_bj2514 < _seq2513.count and value.field_members[_i2516] === _seq2513[_bj2514]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_VariableDef_write(scratch, value.field_members[_i2516]);
                base.verify_same($"t.{slot}.field_members", _bj2514, scratch);
            }
            _bj2514 += 1;
        } else if (_bj2514 < _seq2513.count
            and _same_m_VariableDef(value.field_members[_i2516], _seq2513[_bj2514], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_VariableDef_write(scratch, value.field_members[_i2516]);
                base.verify_same($"t.{slot}.field_members", _bj2514, scratch);
            }
            _bj2514 += 1;
        } else {
            _news2515.append(_i2516);
        }
    }
    if (_bj2514 == _seq2513.count) {
        out.unsigned(2);
        out.unsigned(_news2515.count);
        for (var _i2516 in _news2515) {
            out.unsigned(_i2516);
            _m_VariableDef_write(out, value.field_members[_i2516]);
        }
        base.count("t.*.field_members" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.field_members" + " whole", 0);
        out.unsigned(value.field_members.count);
        for (var _i2516 in 0..value.field_members.count) {
            _m_VariableDef_write(out, value.field_members[_i2516]);
        }
    }
    var _seq2529 = base.ref_template_parts[slot].method_members;
    ulong _bj2530 = 0;
    var _news2531 = Array<ulong>();
    for (var _i2532 in 0..value.method_members.count) {
        if (_bj2530 < _seq2529.count and value.method_members[_i2532] === _seq2529[_bj2530]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.method_members[_i2532]);
                base.verify_same($"t.{slot}.method_members", _bj2530, scratch);
            }
            _bj2530 += 1;
        } else if (_bj2530 < _seq2529.count
            and _same_m_FunctionDef(value.method_members[_i2532], _seq2529[_bj2530], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.method_members[_i2532]);
                base.verify_same($"t.{slot}.method_members", _bj2530, scratch);
            }
            _bj2530 += 1;
        } else {
            _news2531.append(_i2532);
        }
    }
    if (_bj2530 == _seq2529.count) {
        out.unsigned(2);
        out.unsigned(_news2531.count);
        for (var _i2532 in _news2531) {
            out.unsigned(_i2532);
            _m_FunctionDef_write(out, value.method_members[_i2532]);
        }
        base.count("t.*.method_members" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.method_members" + " whole", 0);
        out.unsigned(value.method_members.count);
        for (var _i2532 in 0..value.method_members.count) {
            _m_FunctionDef_write(out, value.method_members[_i2532]);
        }
    }
    var _seq2545 = base.ref_template_parts[slot].generic_methods;
    ulong _bj2546 = 0;
    var _news2547 = Array<ulong>();
    for (var _i2548 in 0..value.generic_methods.count) {
        if (_bj2546 < _seq2545.count and value.generic_methods[_i2548] === _seq2545[_bj2546]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.generic_methods[_i2548]);
                base.verify_same($"t.{slot}.generic_methods", _bj2546, scratch);
            }
            _bj2546 += 1;
        } else if (_bj2546 < _seq2545.count
            and _same_m_FunctionDef(value.generic_methods[_i2548], _seq2545[_bj2546], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.generic_methods[_i2548]);
                base.verify_same($"t.{slot}.generic_methods", _bj2546, scratch);
            }
            _bj2546 += 1;
        } else {
            _news2547.append(_i2548);
        }
    }
    if (_bj2546 == _seq2545.count) {
        out.unsigned(2);
        out.unsigned(_news2547.count);
        for (var _i2548 in _news2547) {
            out.unsigned(_i2548);
            _m_FunctionDef_write(out, value.generic_methods[_i2548]);
        }
        base.count("t.*.generic_methods" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.generic_methods" + " whole", 0);
        out.unsigned(value.generic_methods.count);
        for (var _i2548 in 0..value.generic_methods.count) {
            _m_FunctionDef_write(out, value.generic_methods[_i2548]);
        }
    }
    var _seq2561 = base.ref_template_parts[slot].constructors;
    ulong _bj2562 = 0;
    var _news2563 = Array<ulong>();
    for (var _i2564 in 0..value.constructors.count) {
        if (_bj2562 < _seq2561.count and value.constructors[_i2564] === _seq2561[_bj2562]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.constructors[_i2564]);
                base.verify_same($"t.{slot}.constructors", _bj2562, scratch);
            }
            _bj2562 += 1;
        } else if (_bj2562 < _seq2561.count
            and _same_m_FunctionDef(value.constructors[_i2564], _seq2561[_bj2562], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.constructors[_i2564]);
                base.verify_same($"t.{slot}.constructors", _bj2562, scratch);
            }
            _bj2562 += 1;
        } else {
            _news2563.append(_i2564);
        }
    }
    if (_bj2562 == _seq2561.count) {
        out.unsigned(2);
        out.unsigned(_news2563.count);
        for (var _i2564 in _news2563) {
            out.unsigned(_i2564);
            _m_FunctionDef_write(out, value.constructors[_i2564]);
        }
        base.count("t.*.constructors" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.constructors" + " whole", 0);
        out.unsigned(value.constructors.count);
        for (var _i2564 in 0..value.constructors.count) {
            _m_FunctionDef_write(out, value.constructors[_i2564]);
        }
    }
    _m_FunctionDef_write(out, value.destructor);
    _m_FunctionDef_write(out, value.acquire);
    _m_FunctionDef_write(out, value.release);
    var _seq2580 = base.ref_template_parts[slot].traits;
    ulong _bj2581 = 0;
    var _news2582 = Array<ulong>();
    for (var _i2583 in 0..value.traits.count) {
        if (_bj2581 < _seq2580.count and value.traits[_i2583] === _seq2580[_bj2581]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_TypeName_write(scratch, value.traits[_i2583]);
                base.verify_same($"t.{slot}.traits", _bj2581, scratch);
            }
            _bj2581 += 1;
        } else if (_bj2581 < _seq2580.count and _same_m_TypeName(value.traits[_i2583], _seq2580[_bj2581], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_TypeName_write(scratch, value.traits[_i2583]);
                base.verify_same($"t.{slot}.traits", _bj2581, scratch);
            }
            _bj2581 += 1;
        } else {
            _news2582.append(_i2583);
        }
    }
    if (_bj2581 == _seq2580.count) {
        out.unsigned(2);
        out.unsigned(_news2582.count);
        for (var _i2583 in _news2582) {
            out.unsigned(_i2583);
            _m_TypeName_write(out, value.traits[_i2583]);
        }
        base.count("t.*.traits" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.traits" + " whole", 0);
        out.unsigned(value.traits.count);
        for (var _i2583 in 0..value.traits.count) {
            _m_TypeName_write(out, value.traits[_i2583]);
        }
    }
    var _seq2596 = base.ref_template_parts[slot].attributes;
    ulong _bj2597 = 0;
    var _news2598 = Array<ulong>();
    for (var _i2599 in 0..value.attributes.count) {
        if (_bj2597 < _seq2596.count and value.attributes[_i2599] === _seq2596[_bj2597]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _a_Attribute_write(scratch, value.attributes[_i2599]);
                base.verify_same($"t.{slot}.attributes", _bj2597, scratch);
            }
            _bj2597 += 1;
        } else if (_bj2597 < _seq2596.count and _same_a_Attribute(value.attributes[_i2599], _seq2596[_bj2597], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _a_Attribute_write(scratch, value.attributes[_i2599]);
                base.verify_same($"t.{slot}.attributes", _bj2597, scratch);
            }
            _bj2597 += 1;
        } else {
            _news2598.append(_i2599);
        }
    }
    if (_bj2597 == _seq2596.count) {
        out.unsigned(2);
        out.unsigned(_news2598.count);
        for (var _i2599 in _news2598) {
            out.unsigned(_i2599);
            _a_Attribute_write(out, value.attributes[_i2599]);
        }
        base.count("t.*.attributes" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.attributes" + " whole", 0);
        out.unsigned(value.attributes.count);
        for (var _i2599 in 0..value.attributes.count) {
            _a_Attribute_write(out, value.attributes[_i2599]);
        }
    }
    out.loc(value.loc);
    if (value.enum_cases.is_value()) {
        out.unsigned(1);
        out.unsigned(value.enum_cases.value().count);
        for (var _item2608 in value.enum_cases.value()) {
            _m_EnumCaseDef_write(out, _item2608);
        }
    } else {
        out.unsigned(0);
    }
}

_patch_t_read(input: RecordIn, was: StructDef): StructDef {
    var _f2490 = input.text();
    var _f2491 = _m_TypeName_read(input);
    var _f2501 = Array<GenericParam>();
    var _mode2504 = input.unsigned();
    if (_mode2504 == 2) {
        var _changed2493 = HashMap<ulong, GenericParam>();
        ulong _bi2505 = 0;
        var _n2502 = input.count();
        for (var _ in 0.._n2502) {
            var _at2506 = input.unsigned();
            while (_f2501.count < _at2506 or (input.merging and _bi2505 < was.generic_params.count)) {
                var _c = _changed2493.try_get(_bi2505);
                _f2501.append(_c.is_value() ? _c.value() : was.generic_params[_bi2505]);
                _bi2505 += 1;
            }
            _f2501.append(_m_GenericParam_read(input));
        }
        while (_bi2505 < was.generic_params.count) {
            var _c = _changed2493.try_get(_bi2505);
            _f2501.append(_c.is_value() ? _c.value() : was.generic_params[_bi2505]);
            _bi2505 += 1;
        }
    } else if (_mode2504 == 3) {
        var _n2502 = input.count();
        for (var _ in 0.._n2502) {
            _f2501.append(_m_GenericParam_read(input));
        }
    } else {
        var _n2502 = input.count();
        if (input.merging) {
            input.error = "t.*.generic_params" + " written by place";
        }
        for (var _ in 0.._n2502) {
            var _tag2503 = input.unsigned();
            if (_tag2503 & 1 == 1) {
                if (!input.merging) {
                    _f2501.append(was.generic_params[_tag2503 >> 1]);
                }
            } else {
                var _read = _m_GenericParam_read(input);
                if (!input.merging or true) {
                    _f2501.append(_read);
                }
            }
        }
    }
    var _f2517 = Array<VariableDef>();
    var _mode2520 = input.unsigned();
    if (_mode2520 == 2) {
        var _changed2509 = HashMap<ulong, VariableDef>();
        ulong _bi2521 = 0;
        var _n2518 = input.count();
        for (var _ in 0.._n2518) {
            var _at2522 = input.unsigned();
            while (_f2517.count < _at2522 or (input.merging and _bi2521 < was.field_members.count)) {
                var _c = _changed2509.try_get(_bi2521);
                _f2517.append(_c.is_value() ? _c.value() : was.field_members[_bi2521]);
                _bi2521 += 1;
            }
            _f2517.append(_m_VariableDef_read(input));
        }
        while (_bi2521 < was.field_members.count) {
            var _c = _changed2509.try_get(_bi2521);
            _f2517.append(_c.is_value() ? _c.value() : was.field_members[_bi2521]);
            _bi2521 += 1;
        }
    } else if (_mode2520 == 3) {
        var _n2518 = input.count();
        for (var _ in 0.._n2518) {
            _f2517.append(_m_VariableDef_read(input));
        }
    } else {
        var _n2518 = input.count();
        if (input.merging) {
            input.error = "t.*.field_members" + " written by place";
        }
        for (var _ in 0.._n2518) {
            var _tag2519 = input.unsigned();
            if (_tag2519 & 1 == 1) {
                if (!input.merging) {
                    _f2517.append(was.field_members[_tag2519 >> 1]);
                }
            } else {
                var _read = _m_VariableDef_read(input);
                if (!input.merging or true) {
                    _f2517.append(_read);
                }
            }
        }
    }
    var _f2533 = Array<FunctionDef>();
    var _mode2536 = input.unsigned();
    if (_mode2536 == 2) {
        var _changed2525 = HashMap<ulong, FunctionDef>();
        ulong _bi2537 = 0;
        var _n2534 = input.count();
        for (var _ in 0.._n2534) {
            var _at2538 = input.unsigned();
            while (_f2533.count < _at2538 or (input.merging and _bi2537 < was.method_members.count)) {
                var _c = _changed2525.try_get(_bi2537);
                _f2533.append(_c.is_value() ? _c.value() : was.method_members[_bi2537]);
                _bi2537 += 1;
            }
            _f2533.append(_m_FunctionDef_read(input));
        }
        while (_bi2537 < was.method_members.count) {
            var _c = _changed2525.try_get(_bi2537);
            _f2533.append(_c.is_value() ? _c.value() : was.method_members[_bi2537]);
            _bi2537 += 1;
        }
    } else if (_mode2536 == 3) {
        var _n2534 = input.count();
        for (var _ in 0.._n2534) {
            _f2533.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2534 = input.count();
        if (input.merging) {
            input.error = "t.*.method_members" + " written by place";
        }
        for (var _ in 0.._n2534) {
            var _tag2535 = input.unsigned();
            if (_tag2535 & 1 == 1) {
                if (!input.merging) {
                    _f2533.append(was.method_members[_tag2535 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2533.append(_read);
                }
            }
        }
    }
    var _f2549 = Array<FunctionDef>();
    var _mode2552 = input.unsigned();
    if (_mode2552 == 2) {
        var _changed2541 = HashMap<ulong, FunctionDef>();
        ulong _bi2553 = 0;
        var _n2550 = input.count();
        for (var _ in 0.._n2550) {
            var _at2554 = input.unsigned();
            while (_f2549.count < _at2554 or (input.merging and _bi2553 < was.generic_methods.count)) {
                var _c = _changed2541.try_get(_bi2553);
                _f2549.append(_c.is_value() ? _c.value() : was.generic_methods[_bi2553]);
                _bi2553 += 1;
            }
            _f2549.append(_m_FunctionDef_read(input));
        }
        while (_bi2553 < was.generic_methods.count) {
            var _c = _changed2541.try_get(_bi2553);
            _f2549.append(_c.is_value() ? _c.value() : was.generic_methods[_bi2553]);
            _bi2553 += 1;
        }
    } else if (_mode2552 == 3) {
        var _n2550 = input.count();
        for (var _ in 0.._n2550) {
            _f2549.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2550 = input.count();
        if (input.merging) {
            input.error = "t.*.generic_methods" + " written by place";
        }
        for (var _ in 0.._n2550) {
            var _tag2551 = input.unsigned();
            if (_tag2551 & 1 == 1) {
                if (!input.merging) {
                    _f2549.append(was.generic_methods[_tag2551 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2549.append(_read);
                }
            }
        }
    }
    var _f2565 = Array<FunctionDef>();
    var _mode2568 = input.unsigned();
    if (_mode2568 == 2) {
        var _changed2557 = HashMap<ulong, FunctionDef>();
        ulong _bi2569 = 0;
        var _n2566 = input.count();
        for (var _ in 0.._n2566) {
            var _at2570 = input.unsigned();
            while (_f2565.count < _at2570 or (input.merging and _bi2569 < was.constructors.count)) {
                var _c = _changed2557.try_get(_bi2569);
                _f2565.append(_c.is_value() ? _c.value() : was.constructors[_bi2569]);
                _bi2569 += 1;
            }
            _f2565.append(_m_FunctionDef_read(input));
        }
        while (_bi2569 < was.constructors.count) {
            var _c = _changed2557.try_get(_bi2569);
            _f2565.append(_c.is_value() ? _c.value() : was.constructors[_bi2569]);
            _bi2569 += 1;
        }
    } else if (_mode2568 == 3) {
        var _n2566 = input.count();
        for (var _ in 0.._n2566) {
            _f2565.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2566 = input.count();
        if (input.merging) {
            input.error = "t.*.constructors" + " written by place";
        }
        for (var _ in 0.._n2566) {
            var _tag2567 = input.unsigned();
            if (_tag2567 & 1 == 1) {
                if (!input.merging) {
                    _f2565.append(was.constructors[_tag2567 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2565.append(_read);
                }
            }
        }
    }
    var _f2572 = _m_FunctionDef_read(input);
    var _f2573 = _m_FunctionDef_read(input);
    var _f2574 = _m_FunctionDef_read(input);
    var _f2584 = Array<TypeName>();
    var _mode2587 = input.unsigned();
    if (_mode2587 == 2) {
        var _changed2576 = HashMap<ulong, TypeName>();
        ulong _bi2588 = 0;
        var _n2585 = input.count();
        for (var _ in 0.._n2585) {
            var _at2589 = input.unsigned();
            while (_f2584.count < _at2589 or (input.merging and _bi2588 < was.traits.count)) {
                var _c = _changed2576.try_get(_bi2588);
                _f2584.append(_c.is_value() ? _c.value() : was.traits[_bi2588]);
                _bi2588 += 1;
            }
            _f2584.append(_m_TypeName_read(input));
        }
        while (_bi2588 < was.traits.count) {
            var _c = _changed2576.try_get(_bi2588);
            _f2584.append(_c.is_value() ? _c.value() : was.traits[_bi2588]);
            _bi2588 += 1;
        }
    } else if (_mode2587 == 3) {
        var _n2585 = input.count();
        for (var _ in 0.._n2585) {
            _f2584.append(_m_TypeName_read(input));
        }
    } else {
        var _n2585 = input.count();
        if (input.merging) {
            input.error = "t.*.traits" + " written by place";
        }
        for (var _ in 0.._n2585) {
            var _tag2586 = input.unsigned();
            if (_tag2586 & 1 == 1) {
                if (!input.merging) {
                    _f2584.append(was.traits[_tag2586 >> 1]);
                }
            } else {
                var _read = _m_TypeName_read(input);
                if (!input.merging or true) {
                    _f2584.append(_read);
                }
            }
        }
    }
    var _f2600 = Array<ast.Attribute>();
    var _mode2603 = input.unsigned();
    if (_mode2603 == 2) {
        var _changed2592 = HashMap<ulong, ast.Attribute>();
        ulong _bi2604 = 0;
        var _n2601 = input.count();
        for (var _ in 0.._n2601) {
            var _at2605 = input.unsigned();
            while (_f2600.count < _at2605 or (input.merging and _bi2604 < was.attributes.count)) {
                var _c = _changed2592.try_get(_bi2604);
                _f2600.append(_c.is_value() ? _c.value() : was.attributes[_bi2604]);
                _bi2604 += 1;
            }
            _f2600.append(_a_Attribute_read(input));
        }
        while (_bi2604 < was.attributes.count) {
            var _c = _changed2592.try_get(_bi2604);
            _f2600.append(_c.is_value() ? _c.value() : was.attributes[_bi2604]);
            _bi2604 += 1;
        }
    } else if (_mode2603 == 3) {
        var _n2601 = input.count();
        for (var _ in 0.._n2601) {
            _f2600.append(_a_Attribute_read(input));
        }
    } else {
        var _n2601 = input.count();
        if (input.merging) {
            input.error = "t.*.attributes" + " written by place";
        }
        for (var _ in 0.._n2601) {
            var _tag2602 = input.unsigned();
            if (_tag2602 & 1 == 1) {
                if (!input.merging) {
                    _f2600.append(was.attributes[_tag2602 >> 1]);
                }
            } else {
                var _read = _a_Attribute_read(input);
                if (!input.merging or true) {
                    _f2600.append(_read);
                }
            }
        }
    }
    var _f2607 = input.loc();
    var _o2609 = Optional<Array<EnumCaseDef>>.Empty;
    if (input.unsigned() == 1) {
        var _v2610 = Array<EnumCaseDef>();
        var _n2611 = input.count();
        for (var _ in 0.._n2611) {
            _v2610.append(_m_EnumCaseDef_read(input));
        }
        _o2609 = Optional<Array<EnumCaseDef>>.Value(_v2610);
    }
    var _f2612 = _o2609;
    return StructDef(
        _f2490, _f2491, _f2501, _f2517, _f2533, _f2549, _f2565, _f2572, _f2573, _f2574, _f2584, _f2600, _f2607, _f2612
    );
}

_patch_t_index(value: StructDef, base: DeltaBase, slot: ulong) {
    if (base.verifying) {
        ulong _j2507 = 0;
        for (var _item2492 in value.generic_params) {
            var scratch = base.scratch();
            _m_GenericParam_write(scratch, _item2492);
            base.add($"t.{slot}.generic_params", scratch, _j2507);
            _j2507 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2523 = 0;
        for (var _item2508 in value.field_members) {
            var scratch = base.scratch();
            _m_VariableDef_write(scratch, _item2508);
            base.add($"t.{slot}.field_members", scratch, _j2523);
            _j2523 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2539 = 0;
        for (var _item2524 in value.method_members) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2524);
            base.add($"t.{slot}.method_members", scratch, _j2539);
            _j2539 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2555 = 0;
        for (var _item2540 in value.generic_methods) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2540);
            base.add($"t.{slot}.generic_methods", scratch, _j2555);
            _j2555 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2571 = 0;
        for (var _item2556 in value.constructors) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2556);
            base.add($"t.{slot}.constructors", scratch, _j2571);
            _j2571 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2590 = 0;
        for (var _item2575 in value.traits) {
            var scratch = base.scratch();
            _m_TypeName_write(scratch, _item2575);
            base.add($"t.{slot}.traits", scratch, _j2590);
            _j2590 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2606 = 0;
        for (var _item2591 in value.attributes) {
            var scratch = base.scratch();
            _a_Attribute_write(scratch, _item2591);
            base.add($"t.{slot}.attributes", scratch, _j2606);
            _j2606 += 1;
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
        for (var _item2613 in value.imports) {
            _a_Import_write(out, _item2613);
        }
        found.append(("imports", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.structs.count);
        for (var _item2614 in value.structs) {
            _m_StructDef_write(out, _item2614);
        }
        found.append(("structs", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.blank_bodies = false;
        out.unsigned(value.traits.count);
        for (var _item2615 in value.traits) {
            _m_TraitDef_write(out, _item2615);
        }
        found.append(("traits", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.extensions.count);
        for (var _item2616 in value.extensions) {
            _m_ExtensionDef_write(out, _item2616);
        }
        found.append(("extensions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.functions.count);
        for (var _item2617 in value.functions) {
            _m_FunctionDef_write(out, _item2617);
        }
        found.append(("functions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.externs.count);
        for (var _item2618 in value.externs) {
            _m_ExternDef_write(out, _item2618);
        }
        found.append(("externs", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.globals.count);
        for (var _item2619 in value.globals) {
            _m_VariableDef_write(out, _item2619);
        }
        found.append(("globals", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.static_blocks.count);
        for (var _item2620 in value.static_blocks) {
            _m_ModuleStaticBlock_write(out, _item2620);
        }
        found.append(("static_blocks", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.enums.count);
        for (var _item2621 in value.enums) {
            _m_EnumDef_write(out, _item2621);
        }
        found.append(("enums", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.struct_specs.count);
        for (var _item2622 in value.struct_specs) {
            _m_TypeName_write(out, _item2622);
        }
        found.append(("struct_specs", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.func_specs.count);
        for (var _item2623 in value.func_specs) {
            _m_TypeName_write(out, _item2623);
        }
        found.append(("func_specs", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.type_aliases.count);
        for (var _item2624 in value.type_aliases) {
            _m_TypeAliasDef_write(out, _item2624);
        }
        found.append(("type_aliases", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.withheld.count);
        for (var _item2625 in value.withheld) {
            _m_Withheld_write(out, _item2625);
        }
        found.append(("withheld", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.properties.count);
        for (var _item2626 in value.properties) {
            _m_PropertyDef_write(out, _item2626);
        }
        found.append(("properties", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.type_uses.count);
        for (var _item2627 in value.type_uses) {
            _m_TypeUse_write(out, _item2627);
        }
        found.append(("type_uses", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.use_contexts.count);
        for (var _item2628 in value.use_contexts) {
            _m_UseContext_write(out, _item2628);
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
            for (var _item2629 in value.literal_args) {
                var (_t2630, _t2631, _t2632) = _item2629;
                out.loc(_t2630);
                out.unsigned(_t2631);
                out.loc(_t2632);
            }
        }
        found.append(("literal_args", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.constrained_aliases.count);
        for (var _item2633 in value.constrained_aliases) {
            _m_TypeAliasDef_write(out, _item2633);
        }
        found.append(("constrained_aliases", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.trait_types.count);
        for (var _item2634 in value.trait_types) {
            _m_TraitType_write(out, _item2634);
        }
        found.append(("trait_types", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.conversions.count);
        for (var _item2635 in value.conversions) {
            _m_Conversion_write(out, _item2635);
        }
        found.append(("conversions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2637 = Array<(u8[], u8[], String)>();
        for (var (_key2636, _) in value.overload_sets) {
            var _scratch2638 = out.scratch();
            _scratch2638.text(_key2636);
            var _vscratch2640 = out.scratch();
            _vscratch2640.unsigned(value.overload_sets[_key2636].count);
            for (var _item2641 in value.overload_sets[_key2636]) {
                _vscratch2640.text(_item2641);
            }
            _keys2637.append((_scratch2638.finish(), _vscratch2640.finish(), _key2636));
        }
        _keys2637.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2637.count);
        for (var (_bytes2639, _, _key2636) in _keys2637) {
            out.text(_key2636);
            out.unsigned(value.overload_sets[_key2636].count);
            for (var _item2642 in value.overload_sets[_key2636]) {
                out.text(_item2642);
            }
        }
        found.append(("overload_sets", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2644 = Array<(u8[], u8[], String)>();
        for (var (_key2643, _) in value.overload_unions) {
            var _scratch2645 = out.scratch();
            _scratch2645.text(_key2643);
            var _vscratch2647 = out.scratch();
            _vscratch2647.unsigned(value.overload_unions[_key2643].count);
            for (var _item2648 in value.overload_unions[_key2643]) {
                _vscratch2647.unsigned(_item2648.count);
                for (var _item2649 in _item2648) {
                    _vscratch2647.text(_item2649);
                }
            }
            _keys2644.append((_scratch2645.finish(), _vscratch2647.finish(), _key2643));
        }
        _keys2644.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2644.count);
        for (var (_bytes2646, _, _key2643) in _keys2644) {
            out.text(_key2643);
            out.unsigned(value.overload_unions[_key2643].count);
            for (var _item2650 in value.overload_unions[_key2643]) {
                out.unsigned(_item2650.count);
                for (var _item2651 in _item2650) {
                    out.text(_item2651);
                }
            }
        }
        found.append(("overload_unions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2653 = Array<(u8[], u8[], String)>();
        for (var (_key2652, _) in value.method_overload_sets) {
            var _scratch2654 = out.scratch();
            _scratch2654.text(_key2652);
            var _vscratch2656 = out.scratch();
            var _keys2658 = Array<(u8[], u8[], String)>();
            for (var (_key2657, _) in value.method_overload_sets[_key2652]) {
                var _scratch2659 = _vscratch2656.scratch();
                _scratch2659.text(_key2657);
                var _vscratch2661 = _vscratch2656.scratch();
                _vscratch2661.unsigned(value.method_overload_sets[_key2652][_key2657].count);
                for (var _item2662 in value.method_overload_sets[_key2652][_key2657]) {
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
            _vscratch2656.unsigned(_keys2658.count);
            for (var (_bytes2660, _, _key2657) in _keys2658) {
                _vscratch2656.text(_key2657);
                _vscratch2656.unsigned(value.method_overload_sets[_key2652][_key2657].count);
                for (var _item2663 in value.method_overload_sets[_key2652][_key2657]) {
                    _vscratch2656.text(_item2663);
                }
            }
            _keys2653.append((_scratch2654.finish(), _vscratch2656.finish(), _key2652));
        }
        _keys2653.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2653.count);
        for (var (_bytes2655, _, _key2652) in _keys2653) {
            out.text(_key2652);
            var _keys2665 = Array<(u8[], u8[], String)>();
            for (var (_key2664, _) in value.method_overload_sets[_key2652]) {
                var _scratch2666 = out.scratch();
                _scratch2666.text(_key2664);
                var _vscratch2668 = out.scratch();
                _vscratch2668.unsigned(value.method_overload_sets[_key2652][_key2664].count);
                for (var _item2669 in value.method_overload_sets[_key2652][_key2664]) {
                    _vscratch2668.text(_item2669);
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
                out.unsigned(value.method_overload_sets[_key2652][_key2664].count);
                for (var _item2670 in value.method_overload_sets[_key2652][_key2664]) {
                    out.text(_item2670);
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
        var _keys2672 = Array<(u8[], u8[], Loc)>();
        for (var _key2671 in value.private_functions) {
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
        found.append(("private_functions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2677 = Array<(u8[], u8[], Loc)>();
        for (var _key2676 in value.file_private_functions) {
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
            for (var _item2681 in value.call_targets) {
                var (_t2682, _t2683) = _item2681;
                out.loc(_t2682);
                out.text(_t2683);
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
            for (var _item2684 in value.argument_names) {
                var (_t2685, _t2686) = _item2684;
                out.loc(_t2685);
                out.text(_t2686);
            }
        }
        found.append(("argument_names", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.namespaces.count);
        for (var _item2687 in value.namespaces) {
            out.text(_item2687);
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
            for (var _item2688 in value.cached_files) {
                out.flag(_item2688);
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
            var _keys2690 = Array<(u8[], u8[], Loc)>();
            for (var (_key2689, _) in value.recorded_summaries) {
                var _scratch2691 = out.scratch();
                _scratch2691.loc(_key2689);
                var _vscratch2693 = out.scratch();
                _vscratch2693.text(value.recorded_summaries[_key2689]);
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
                out.text(value.recorded_summaries[_key2689]);
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
            var _keys2695 = Array<(u8[], u8[], Loc)>();
            for (var _key2694 in value.stripped) {
                var _scratch2696 = out.scratch();
                _scratch2696.loc(_key2694);
                var _vscratch2698 = out.scratch();
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
        var _keys2700 = Array<(u8[], u8[], String)>();
        for (var (_key2699, _) in value.spec_requests) {
            var _scratch2701 = out.scratch();
            _scratch2701.text(_key2699);
            var _vscratch2703 = out.scratch();
            _m_SpecRequest_write(_vscratch2703, value.spec_requests[_key2699]);
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
            out.text(_key2699);
            _m_SpecRequest_write(out, value.spec_requests[_key2699]);
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
            for (var _item2704 in value.summaries_to_record) {
                var (_t2705, _t2706) = _item2704;
                out.loc(_t2705);
                out.text(_t2706);
            }
        }
        found.append(("summaries_to_record", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2708 = Array<(u8[], u8[], String)>();
        for (var (_key2707, _) in value.caller_copies) {
            var _scratch2709 = out.scratch();
            _scratch2709.text(_key2707);
            var _vscratch2711 = out.scratch();
            _vscratch2711.unsigned(value.caller_copies[_key2707].count);
            for (var _item2712 in value.caller_copies[_key2707]) {
                _vscratch2711.flag(_item2712);
            }
            _keys2708.append((_scratch2709.finish(), _vscratch2711.finish(), _key2707));
        }
        _keys2708.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2708.count);
        for (var (_bytes2710, _, _key2707) in _keys2708) {
            out.text(_key2707);
            out.unsigned(value.caller_copies[_key2707].count);
            for (var _item2713 in value.caller_copies[_key2707]) {
                out.flag(_item2713);
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
    for (var _item2714 in value.structs) {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        _m_StructDef_write(out, _item2714);
        found.append(("structs " + _item2714.name, interface_text(out)));
    }
    for (var _item2715 in value.functions) {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        _m_FunctionDef_write(out, _item2715);
        found.append(("functions " + _item2715.name, interface_text(out)));
    }
    return found;
}
