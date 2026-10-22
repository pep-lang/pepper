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
    return MethodCallExpression(_f1420, _f1421, _f1424, _f1425);
}

_m_FunctionRefExpression_write(out: RecordOut, value: FunctionRefExpression) {
    out.text(value.function);
    _m_TypeName_write(out, value.ty);
    out.loc(value.loc);
}

_m_FunctionRefExpression_read(input: RecordIn): FunctionRefExpression {
    var _f1426 = input.text();
    var _f1427 = _m_TypeName_read(input);
    var _f1428 = input.loc();
    return FunctionRefExpression(_f1426, _f1427, _f1428);
}

_m_InvokeExpression_write(out: RecordOut, value: InvokeExpression) {
    _m_Expression_write(out, value.callee);
    out.unsigned(value.args.count);
    for (var _item1429 in value.args) {
        _m_Expression_write(out, _item1429);
    }
}

_m_InvokeExpression_read(input: RecordIn): InvokeExpression {
    var _f1430 = _m_Expression_read(input);
    var _v1431 = Array<Expression>();
    var _n1432 = input.count();
    for (var _ in 0.._n1432) {
        _v1431.append(_m_Expression_read(input));
    }
    var _f1433 = _v1431;
    return InvokeExpression(_f1430, _f1433);
}

_m_MakeClosureExpression_write(out: RecordOut, value: MakeClosureExpression) {
    _m_Expression_write(out, value.value);
    out.text(value.closure);
    _m_TypeName_write(out, value.ty);
    out.loc(value.loc);
}

_m_MakeClosureExpression_read(input: RecordIn): MakeClosureExpression {
    var _f1435 = _m_Expression_read(input);
    var _f1436 = input.text();
    var _f1437 = _m_TypeName_read(input);
    var _f1438 = input.loc();
    return MakeClosureExpression(_f1435, _f1436, _f1437, _f1438);
}

_m_CallPointerExpression_write(out: RecordOut, value: CallPointerExpression) {
    _m_Expression_write(out, value.pointer);
    out.unsigned(value.args.count);
    for (var _item1440 in value.args) {
        _m_Expression_write(out, _item1440);
    }
}

_m_CallPointerExpression_read(input: RecordIn): CallPointerExpression {
    var _f1441 = _m_Expression_read(input);
    var _v1442 = Array<Expression>();
    var _n1443 = input.count();
    for (var _ in 0.._n1443) {
        _v1442.append(_m_Expression_read(input));
    }
    var _f1444 = _v1442;
    return CallPointerExpression(_f1441, _f1444);
}

_m_MoveExpression_write(out: RecordOut, value: MoveExpression) {
    _m_Expression_write(out, value.value);
    out.loc(value.loc);
}

_m_MoveExpression_read(input: RecordIn): MoveExpression {
    var _f1447 = _m_Expression_read(input);
    var _f1448 = input.loc();
    return MoveExpression(_f1447, _f1448);
}

_m_DestructureExpression_write(out: RecordOut, value: DestructureExpression) {
    _m_Expression_write(out, value.value);
    out.unsigned(value.count);
    out.loc(value.loc);
}

_m_DestructureExpression_read(input: RecordIn): DestructureExpression {
    var _f1449 = _m_Expression_read(input);
    var _f1450 = input.unsigned();
    var _f1451 = input.loc();
    return DestructureExpression(_f1449, _f1450, _f1451);
}

_m_StaticCaseExpression_write(out: RecordOut, value: StaticCaseExpression) {
    _m_TypeName_write(out, value.ty);
    out.signed(value.tag as long);
}

_m_StaticCaseExpression_read(input: RecordIn): StaticCaseExpression {
    var _f1454 = _m_TypeName_read(input);
    var _f1455 = input.signed();
    return StaticCaseExpression(_f1454, _f1455);
}

_m_StaticStringExpression_write(out: RecordOut, value: StaticStringExpression) {
    out.text(value.value);
    out.loc(value.loc);
}

_m_StaticStringExpression_read(input: RecordIn): StaticStringExpression {
    var _f1456 = input.text();
    var _f1457 = input.loc();
    return StaticStringExpression(_f1456, _f1457);
}

_m_SubjectExpression_write(out: RecordOut, value: SubjectExpression) {
    out.unsigned(value.id);
    _m_TypeName_write(out, value.ty);
    out.loc(value.loc);
}

_m_SubjectExpression_read(input: RecordIn): SubjectExpression {
    var _f1459 = input.unsigned();
    var _f1460 = _m_TypeName_read(input);
    var _f1461 = input.loc();
    return SubjectExpression(_f1459, _f1460, _f1461);
}

_m_ToTraitExpression_write(out: RecordOut, value: ToTraitExpression) {
    _m_Expression_write(out, value.value);
    _m_TypeName_write(out, value.from);
    _m_TypeName_write(out, value.to);
    out.loc(value.loc);
}

_m_ToTraitExpression_read(input: RecordIn): ToTraitExpression {
    var _f1462 = _m_Expression_read(input);
    var _f1463 = _m_TypeName_read(input);
    var _f1464 = _m_TypeName_read(input);
    var _f1465 = input.loc();
    return ToTraitExpression(_f1462, _f1463, _f1464, _f1465);
}

_m_FromTraitExpression_write(out: RecordOut, value: FromTraitExpression) {
    _m_Expression_write(out, value.value);
    _m_TypeName_write(out, value.from);
    _m_TypeName_write(out, value.to);
    out.unsigned(value.candidates.count);
    for (var _item1466 in value.candidates) {
        _m_TypeName_write(out, _item1466);
    }
    out.flag(value.test);
    out.loc(value.loc);
}

_m_FromTraitExpression_read(input: RecordIn): FromTraitExpression {
    var _f1467 = _m_Expression_read(input);
    var _f1468 = _m_TypeName_read(input);
    var _f1469 = _m_TypeName_read(input);
    var _v1470 = Array<TypeName>();
    var _n1471 = input.count();
    for (var _ in 0.._n1471) {
        _v1470.append(_m_TypeName_read(input));
    }
    var _f1472 = _v1470;
    var _f1473 = input.flag();
    var _f1474 = input.loc();
    return FromTraitExpression(_f1467, _f1468, _f1469, _f1472, _f1473, _f1474);
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
        var _f1434 = _m_ClosureLiteral_read(input);
        return Expression.ClosureLiteral(_f1434);
    }
    if (tag == 36) {
        return Expression.MakeClosure(_m_MakeClosureExpression_read(input));
    }
    if (tag == 37) {
        var _f1439 = input.text();
        return Expression.MethodAddress(_f1439);
    }
    if (tag == 38) {
        return Expression.CallPointer(_m_CallPointerExpression_read(input));
    }
    if (tag == 39) {
        var _f1445 = _m_Expression_read(input);
        return Expression.ForIterator(_f1445);
    }
    if (tag == 40) {
        var _f1446 = _m_Expression_read(input);
        return Expression.WithEntered(_f1446);
    }
    if (tag == 41) {
        return Expression.Move(_m_MoveExpression_read(input));
    }
    if (tag == 42) {
        return Expression.Destructure(_m_DestructureExpression_read(input));
    }
    if (tag == 43) {
        var _f1452 = _m_MatchArmTest_read(input);
        return Expression.MatchArm(_f1452);
    }
    if (tag == 44) {
        var _f1453 = _m_CaseValue_read(input);
        return Expression.CaseValue(_f1453);
    }
    if (tag == 45) {
        return Expression.StaticCase(_m_StaticCaseExpression_read(input));
    }
    if (tag == 46) {
        return Expression.StaticString(_m_StaticStringExpression_read(input));
    }
    if (tag == 47) {
        var _f1458 = _m_WithSubject_read(input);
        return Expression.WithSubject(_f1458);
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
        var _f1475 = _m_StaticValue_read(input);
        return Expression.StaticValue(_f1475);
    }
    if (tag == 53) {
        var _f1476 = _m_StaticMember_read(input);
        return Expression.StaticMember(_f1476);
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
        var _f1477 = _m_VariableDef_read(input);
        return Declaration.Variable(_f1477);
    }
    if (tag == 1) {
        var _f1478 = _m_FunctionDef_read(input);
        return Declaration.Function(_f1478);
    }
    if (tag == 2) {
        var _f1479 = _m_StructDef_read(input);
        return Declaration.Struct(_f1479);
    }
    if (tag == 3) {
        var _f1480 = _m_TraitDef_read(input);
        return Declaration.Trait(_f1480);
    }
    if (tag == 4) {
        var _f1481 = _m_ExtensionDef_read(input);
        return Declaration.Extension(_f1481);
    }
    if (tag == 5) {
        var _f1482 = _m_ExternDef_read(input);
        return Declaration.Extern(_f1482);
    }
    if (tag == 6) {
        var _f1483 = _m_TypeAliasDef_read(input);
        return Declaration.TypeAlias(_f1483);
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
    var _hs1489 = Array<String>();
    for (var _item1484 in value.imports) {
        var scratch = base.scratch();
        _a_Import_write(scratch, _item1484);
        _hs1489.append(base.hash_of(scratch));
    }
    var _seq1490 = base.sequence("imports");
    ulong _bj1491 = 0;
    var _news1492 = Array<ulong>();
    for (var _i1493 in 0.._hs1489.count) {
        if (_bj1491 < _seq1490.count and _hs1489[_i1493] == _seq1490[_bj1491]) {
            _bj1491 += 1;
        } else {
            _news1492.append(_i1493);
        }
    }
    if (_bj1491 == _seq1490.count) {
        out.unsigned(2);
        out.unsigned(_news1492.count);
        for (var _i1493 in _news1492) {
            out.unsigned(_i1493);
            _a_Import_write(out, value.imports[_i1493]);
            {
                var _own1494 = RecordOut();
                _own1494.blank_bodies = true;
                _own1494.blank_locs = true;
                _own1494.pending_as_bytes = true;
                _a_Import_write(_own1494, value.imports[_i1493]);
                base.own("imports", interface_text(_own1494));
            }
        }
        base.count("imports" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("imports" + " whole", 0);
        out.unsigned(value.imports.count);
        for (var _i1493 in 0..value.imports.count) {
            _a_Import_write(out, value.imports[_i1493]);
            {
                var _own1495 = RecordOut();
                _own1495.blank_bodies = true;
                _own1495.blank_locs = true;
                _own1495.pending_as_bytes = true;
                _a_Import_write(_own1495, value.imports[_i1493]);
                base.own("imports", interface_text(_own1495));
            }
        }
    }
    base.stat("imports", out.values.count - _mark);
    _mark = out.values.count;
    var _seq1505 = base.ref_structs;
    ulong _bj1506 = 0;
    var _news1508 = Array<ulong>();
    var _patches1509 = Array<(ulong, ulong)>();
    for (var _i1510 in 0..value.structs.count) {
        if (_bj1506 < _seq1505.count
            and value.structs[_i1510] === _seq1505[_bj1506]
            and !value.extended_checked.contains(value.structs[_i1510].name)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_StructDef_write(scratch, value.structs[_i1510]);
                base.verify_same("s", _bj1506, scratch, value.structs[_i1510].name);
            }
            _bj1506 += 1;
        } else if (_bj1506 < _seq1505.count
            and !(value.structs[_i1510] === _seq1505[_bj1506])
            and _same_m_StructDef(value.structs[_i1510], _seq1505[_bj1506], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_StructDef_write(scratch, value.structs[_i1510]);
                base.verify_same("s", _bj1506, scratch, value.structs[_i1510].name);
            }
            _bj1506 += 1;
        } else if (_bj1506 < _seq1505.count and value.structs[_i1510].name == _seq1505[_bj1506].name) {
            _patches1509.append((_i1510, _bj1506));
            _bj1506 += 1;
        } else {
            _news1508.append(_i1510);
        }
    }
    if (_bj1506 == _seq1505.count) {
        out.unsigned(2);
        out.unsigned(_patches1509.count);
        for (var (_i1510, _b) in _patches1509) {
            ulong _before = out.values.count;
            out.text(value.structs[_i1510].name);
            out.unsigned(_b);
            _patch_s_write(out, value.structs[_i1510], base, _b);
            base.count("s patched", out.values.count - _before);
            {
                var _own1511 = RecordOut();
                _own1511.blank_bodies = true;
                _own1511.blank_locs = true;
                _own1511.pending_as_bytes = true;
                var _s1512 = value.structs[_i1510];
                var _methods1513 = _s1512.method_members;
                _s1512.method_members = Array<FunctionDef>();
                var _fields1514 = _s1512.field_members;
                var split__fields1514 = splits_fields(_s1512);
                if (split__fields1514) {
                    _s1512.field_members = Array<VariableDef>();
                }
                _m_StructDef_write(_own1511, _s1512);
                _s1512.method_members = _methods1513;
                _s1512.field_members = _fields1514;
                base.own_named("structs", _s1512.name, interface_text(_own1511));
                for (var _m1515 in _methods1513) {
                    var _own1516 = RecordOut();
                    _own1516.blank_bodies = true;
                    _own1516.blank_locs = true;
                    _own1516.pending_as_bytes = true;
                    _m_FunctionDef_write(_own1516, _m1515);
                    base.own_method("structs", _s1512.name, _m1515.name, interface_text(_own1516));
                }
                if (split__fields1514) {
                    var _order1518 = StringBuilder();
                    for (var _f1517 in _fields1514) {
                        var _own1519 = RecordOut();
                        _own1519.blank_locs = true;
                        _m_VariableDef_write(_own1519, _f1517);
                        base.own_method("structs", _s1512.name, "." + _f1517.name, interface_text(_own1519));
                        _order1518.append(_f1517.name);
                        _order1518.append(",");
                    }
                    base.own_method("structs", _s1512.name, ".#order", _order1518.to_string());
                }
            }
        }
        out.unsigned(_news1508.count);
        for (var _i1510 in _news1508) {
            ulong _before = out.values.count;
            out.unsigned(_i1510);
            _m_StructDef_write(out, value.structs[_i1510]);
            base.count("s new", out.values.count - _before);
            {
                var _own1520 = RecordOut();
                _own1520.blank_bodies = true;
                _own1520.blank_locs = true;
                _own1520.pending_as_bytes = true;
                var _s1521 = value.structs[_i1510];
                var _methods1522 = _s1521.method_members;
                _s1521.method_members = Array<FunctionDef>();
                var _fields1523 = _s1521.field_members;
                var split__fields1523 = splits_fields(_s1521);
                if (split__fields1523) {
                    _s1521.field_members = Array<VariableDef>();
                }
                _m_StructDef_write(_own1520, _s1521);
                _s1521.method_members = _methods1522;
                _s1521.field_members = _fields1523;
                base.own_named("structs", _s1521.name, interface_text(_own1520));
                for (var _m1524 in _methods1522) {
                    var _own1525 = RecordOut();
                    _own1525.blank_bodies = true;
                    _own1525.blank_locs = true;
                    _own1525.pending_as_bytes = true;
                    _m_FunctionDef_write(_own1525, _m1524);
                    base.own_method("structs", _s1521.name, _m1524.name, interface_text(_own1525));
                }
                if (split__fields1523) {
                    var _order1527 = StringBuilder();
                    for (var _f1526 in _fields1523) {
                        var _own1528 = RecordOut();
                        _own1528.blank_locs = true;
                        _m_VariableDef_write(_own1528, _f1526);
                        base.own_method("structs", _s1521.name, "." + _f1526.name, interface_text(_own1528));
                        _order1527.append(_f1526.name);
                        _order1527.append(",");
                    }
                    base.own_method("structs", _s1521.name, ".#order", _order1527.to_string());
                }
            }
        }
        base.count("s merged", 0);
    } else {
        out.unsigned(1);
        base.count("s by place", 0);
        var _struct_hits1504 = HashSet<long>();
        var _slots1507 = HashMap<String, long>();
        for (var _i1510 in 0.._seq1505.count) {
            if (!_slots1507.contains(_seq1505[_i1510].name)) {
                _slots1507[_seq1505[_i1510].name] = _i1510 as long;
            }
        }
        out.unsigned(value.structs.count);
        for (var _i1510 in 0..value.structs.count) {
            var _item1503 = value.structs[_i1510];
            var _slot = _slots1507.try_get(_item1503.name);
            long named = _slot.is_value() ? _slot.value() : -1;
            long at = -1;
            if (named >= 0
                and _seq1505[named as ulong] === _item1503
                and !value.extended_checked.contains(_item1503.name)) {
                at = named;
            }
            ulong _before = out.values.count;
            if (at >= 0) {
                _struct_hits1504.insert(at);
                out.unsigned((at as ulong) * 2 + 1);
            } else if (named >= 0) {
                _struct_hits1504.insert(named);
                out.unsigned(2);
                out.unsigned(named as ulong);
                _patch_s_write(out, _item1503, base, named as ulong);
                base.count("s patched", out.values.count - _before);
            } else {
                out.unsigned(0);
                _m_StructDef_write(out, _item1503);
                base.count("s new", out.values.count - _before);
            }
        }
        base.missed("s", "s", _struct_hits1504.count);
    }
    base.stat("structs", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1542 = Array<String>();
    for (var _item1537 in value.traits) {
        var scratch = base.scratch();
        _m_TraitDef_write(scratch, _item1537);
        _hs1542.append(base.hash_of(scratch));
    }
    var _seq1543 = base.sequence("traits");
    ulong _bj1544 = 0;
    var _news1545 = Array<ulong>();
    for (var _i1546 in 0.._hs1542.count) {
        if (_bj1544 < _seq1543.count and _hs1542[_i1546] == _seq1543[_bj1544]) {
            _bj1544 += 1;
        } else {
            _news1545.append(_i1546);
        }
    }
    if (_bj1544 == _seq1543.count) {
        out.unsigned(2);
        out.unsigned(_news1545.count);
        for (var _i1546 in _news1545) {
            out.unsigned(_i1546);
            _m_TraitDef_write(out, value.traits[_i1546]);
            {
                var _own1547 = RecordOut();
                _own1547.blank_bodies = false;
                _own1547.blank_locs = true;
                _own1547.pending_as_bytes = true;
                _m_TraitDef_write(_own1547, value.traits[_i1546]);
                base.own("traits", interface_text(_own1547));
            }
        }
        base.count("traits" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("traits" + " whole", 0);
        out.unsigned(value.traits.count);
        for (var _i1546 in 0..value.traits.count) {
            _m_TraitDef_write(out, value.traits[_i1546]);
            {
                var _own1548 = RecordOut();
                _own1548.blank_bodies = false;
                _own1548.blank_locs = true;
                _own1548.pending_as_bytes = true;
                _m_TraitDef_write(_own1548, value.traits[_i1546]);
                base.own("traits", interface_text(_own1548));
            }
        }
    }
    base.stat("traits", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1561 = Array<String>();
    for (var _item1556 in value.extensions) {
        var scratch = base.scratch();
        _m_ExtensionDef_write(scratch, _item1556);
        _hs1561.append(base.hash_of(scratch));
    }
    var _seq1562 = base.sequence("extensions");
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
            _m_ExtensionDef_write(out, value.extensions[_i1565]);
            {
                var _own1566 = RecordOut();
                _own1566.blank_bodies = true;
                _own1566.blank_locs = true;
                _own1566.pending_as_bytes = true;
                _m_ExtensionDef_write(_own1566, value.extensions[_i1565]);
                base.own("extensions", interface_text(_own1566));
            }
        }
        base.count("extensions" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("extensions" + " whole", 0);
        out.unsigned(value.extensions.count);
        for (var _i1565 in 0..value.extensions.count) {
            _m_ExtensionDef_write(out, value.extensions[_i1565]);
            {
                var _own1567 = RecordOut();
                _own1567.blank_bodies = true;
                _own1567.blank_locs = true;
                _own1567.pending_as_bytes = true;
                _m_ExtensionDef_write(_own1567, value.extensions[_i1565]);
                base.own("extensions", interface_text(_own1567));
            }
        }
    }
    base.stat("extensions", out.values.count - _mark);
    _mark = out.values.count;
    var _seq1580 = base.ref_functions;
    ulong _bj1581 = 0;
    var _news1582 = Array<ulong>();
    var _changed1576 = Array<(ulong, ulong)>();
    for (var _i1583 in 0..value.functions.count) {
        if (_bj1581 < _seq1580.count and value.functions[_i1583] === _seq1580[_bj1581]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.functions[_i1583]);
                base.verify_same("functions", _bj1581, scratch);
            }
            _bj1581 += 1;
        } else if (_bj1581 < _seq1580.count and _same_m_FunctionDef(value.functions[_i1583], _seq1580[_bj1581], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.functions[_i1583]);
                base.verify_same("functions", _bj1581, scratch);
            }
            _bj1581 += 1;
        } else if (_bj1581 < _seq1580.count and value.functions[_i1583].name == _seq1580[_bj1581].name) {
            _changed1576.append((_i1583, _bj1581));
            _bj1581 += 1;
        } else {
            _news1582.append(_i1583);
        }
    }
    if (_bj1581 == _seq1580.count) {
        out.unsigned(2);
        out.unsigned(_changed1576.count);
        for (var (_i1583, _b) in _changed1576) {
            out.text(value.functions[_i1583].name);
            out.unsigned(_b);
            _m_FunctionDef_write(out, value.functions[_i1583]);
            {
                var _own1584 = RecordOut();
                _own1584.blank_bodies = true;
                _own1584.blank_locs = true;
                _own1584.pending_as_bytes = true;
                _m_FunctionDef_write(_own1584, value.functions[_i1583]);
                base.own_function("functions", value.functions[_i1583], interface_text(_own1584));
            }
        }
        base.count("functions" + " changed", _changed1576.count);
        out.unsigned(_news1582.count);
        for (var _i1583 in _news1582) {
            out.unsigned(_i1583);
            _m_FunctionDef_write(out, value.functions[_i1583]);
            {
                var _own1585 = RecordOut();
                _own1585.blank_bodies = true;
                _own1585.blank_locs = true;
                _own1585.pending_as_bytes = true;
                _m_FunctionDef_write(_own1585, value.functions[_i1583]);
                base.own_function("functions", value.functions[_i1583], interface_text(_own1585));
            }
        }
        base.count("functions" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("functions" + " whole", 0);
        out.unsigned(value.functions.count);
        for (var _i1583 in 0..value.functions.count) {
            _m_FunctionDef_write(out, value.functions[_i1583]);
            {
                var _own1586 = RecordOut();
                _own1586.blank_bodies = true;
                _own1586.blank_locs = true;
                _own1586.pending_as_bytes = true;
                _m_FunctionDef_write(_own1586, value.functions[_i1583]);
                base.own_function("functions", value.functions[_i1583], interface_text(_own1586));
            }
        }
    }
    base.stat("functions", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1599 = Array<String>();
    for (var _item1594 in value.externs) {
        var scratch = base.scratch();
        _m_ExternDef_write(scratch, _item1594);
        _hs1599.append(base.hash_of(scratch));
    }
    var _seq1600 = base.sequence("externs");
    ulong _bj1601 = 0;
    var _news1602 = Array<ulong>();
    for (var _i1603 in 0.._hs1599.count) {
        if (_bj1601 < _seq1600.count and _hs1599[_i1603] == _seq1600[_bj1601]) {
            _bj1601 += 1;
        } else {
            _news1602.append(_i1603);
        }
    }
    if (_bj1601 == _seq1600.count) {
        out.unsigned(2);
        out.unsigned(_news1602.count);
        for (var _i1603 in _news1602) {
            out.unsigned(_i1603);
            _m_ExternDef_write(out, value.externs[_i1603]);
            {
                var _own1604 = RecordOut();
                _own1604.blank_bodies = true;
                _own1604.blank_locs = true;
                _own1604.pending_as_bytes = true;
                _m_ExternDef_write(_own1604, value.externs[_i1603]);
                base.own("externs", interface_text(_own1604));
            }
        }
        base.count("externs" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("externs" + " whole", 0);
        out.unsigned(value.externs.count);
        for (var _i1603 in 0..value.externs.count) {
            _m_ExternDef_write(out, value.externs[_i1603]);
            {
                var _own1605 = RecordOut();
                _own1605.blank_bodies = true;
                _own1605.blank_locs = true;
                _own1605.pending_as_bytes = true;
                _m_ExternDef_write(_own1605, value.externs[_i1603]);
                base.own("externs", interface_text(_own1605));
            }
        }
    }
    base.stat("externs", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1618 = Array<String>();
    for (var _item1613 in value.globals) {
        var scratch = base.scratch();
        _m_VariableDef_write(scratch, _item1613);
        _hs1618.append(base.hash_of(scratch));
    }
    var _seq1619 = base.sequence("globals");
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
            _m_VariableDef_write(out, value.globals[_i1622]);
            {
                var _own1623 = RecordOut();
                _own1623.blank_bodies = true;
                _own1623.blank_locs = true;
                _own1623.pending_as_bytes = true;
                _m_VariableDef_write(_own1623, value.globals[_i1622]);
                base.own("globals", interface_text(_own1623));
            }
        }
        base.count("globals" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("globals" + " whole", 0);
        out.unsigned(value.globals.count);
        for (var _i1622 in 0..value.globals.count) {
            _m_VariableDef_write(out, value.globals[_i1622]);
            {
                var _own1624 = RecordOut();
                _own1624.blank_bodies = true;
                _own1624.blank_locs = true;
                _own1624.pending_as_bytes = true;
                _m_VariableDef_write(_own1624, value.globals[_i1622]);
                base.own("globals", interface_text(_own1624));
            }
        }
    }
    base.stat("globals", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1637 = Array<String>();
    for (var _item1632 in value.static_blocks) {
        var scratch = base.scratch();
        _m_ModuleStaticBlock_write(scratch, _item1632);
        _hs1637.append(base.hash_of(scratch));
    }
    var _seq1638 = base.sequence("static_blocks");
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
            _m_ModuleStaticBlock_write(out, value.static_blocks[_i1641]);
            {
                var _own1642 = RecordOut();
                _own1642.blank_bodies = true;
                _own1642.blank_locs = true;
                _own1642.pending_as_bytes = true;
                _m_ModuleStaticBlock_write(_own1642, value.static_blocks[_i1641]);
                base.own("static_blocks", interface_text(_own1642));
            }
        }
        base.count("static_blocks" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("static_blocks" + " whole", 0);
        out.unsigned(value.static_blocks.count);
        for (var _i1641 in 0..value.static_blocks.count) {
            _m_ModuleStaticBlock_write(out, value.static_blocks[_i1641]);
            {
                var _own1643 = RecordOut();
                _own1643.blank_bodies = true;
                _own1643.blank_locs = true;
                _own1643.pending_as_bytes = true;
                _m_ModuleStaticBlock_write(_own1643, value.static_blocks[_i1641]);
                base.own("static_blocks", interface_text(_own1643));
            }
        }
    }
    base.stat("static_blocks", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1656 = Array<String>();
    for (var _item1651 in value.enums) {
        var scratch = base.scratch();
        _m_EnumDef_write(scratch, _item1651);
        _hs1656.append(base.hash_of(scratch));
    }
    var _seq1657 = base.sequence("enums");
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
            _m_EnumDef_write(out, value.enums[_i1660]);
            {
                var _own1661 = RecordOut();
                _own1661.blank_bodies = true;
                _own1661.blank_locs = true;
                _own1661.pending_as_bytes = true;
                _m_EnumDef_write(_own1661, value.enums[_i1660]);
                base.own_named("enums", value.enums[_i1660].name, interface_text(_own1661));
            }
        }
        base.count("enums" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("enums" + " whole", 0);
        out.unsigned(value.enums.count);
        for (var _i1660 in 0..value.enums.count) {
            _m_EnumDef_write(out, value.enums[_i1660]);
            {
                var _own1662 = RecordOut();
                _own1662.blank_bodies = true;
                _own1662.blank_locs = true;
                _own1662.pending_as_bytes = true;
                _m_EnumDef_write(_own1662, value.enums[_i1660]);
                base.own_named("enums", value.enums[_i1660].name, interface_text(_own1662));
            }
        }
    }
    base.stat("enums", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1675 = Array<String>();
    for (var _item1670 in value.struct_specs) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item1670);
        _hs1675.append(base.hash_of(scratch));
    }
    var _seq1676 = base.sequence("struct_specs");
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
            _m_TypeName_write(out, value.struct_specs[_i1679]);
            {
                var _own1680 = RecordOut();
                _own1680.blank_bodies = true;
                _own1680.blank_locs = true;
                _own1680.pending_as_bytes = true;
                _m_TypeName_write(_own1680, value.struct_specs[_i1679]);
                base.own("struct_specs", interface_text(_own1680));
            }
        }
        base.count("struct_specs" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("struct_specs" + " whole", 0);
        out.unsigned(value.struct_specs.count);
        for (var _i1679 in 0..value.struct_specs.count) {
            _m_TypeName_write(out, value.struct_specs[_i1679]);
            {
                var _own1681 = RecordOut();
                _own1681.blank_bodies = true;
                _own1681.blank_locs = true;
                _own1681.pending_as_bytes = true;
                _m_TypeName_write(_own1681, value.struct_specs[_i1679]);
                base.own("struct_specs", interface_text(_own1681));
            }
        }
    }
    base.stat("struct_specs", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1694 = Array<String>();
    for (var _item1689 in value.func_specs) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item1689);
        _hs1694.append(base.hash_of(scratch));
    }
    var _seq1695 = base.sequence("func_specs");
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
            _m_TypeName_write(out, value.func_specs[_i1698]);
            {
                var _own1699 = RecordOut();
                _own1699.blank_bodies = true;
                _own1699.blank_locs = true;
                _own1699.pending_as_bytes = true;
                _m_TypeName_write(_own1699, value.func_specs[_i1698]);
                base.own("func_specs", interface_text(_own1699));
            }
        }
        base.count("func_specs" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("func_specs" + " whole", 0);
        out.unsigned(value.func_specs.count);
        for (var _i1698 in 0..value.func_specs.count) {
            _m_TypeName_write(out, value.func_specs[_i1698]);
            {
                var _own1700 = RecordOut();
                _own1700.blank_bodies = true;
                _own1700.blank_locs = true;
                _own1700.pending_as_bytes = true;
                _m_TypeName_write(_own1700, value.func_specs[_i1698]);
                base.own("func_specs", interface_text(_own1700));
            }
        }
    }
    base.stat("func_specs", out.values.count - _mark);
    _mark = out.values.count;
    var _hits1712 = HashSet<long>();
    out.unsigned(value.type_aliases.count);
    for (var _item1708 in value.type_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1708);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed("type_aliases", hash);
        if (at >= 0) {
            _hits1712.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_TypeAliasDef_write(out, _item1708);
        }
    }
    base.missed("type_aliases", "type_aliases", _hits1712.count);
    base.stat("type_aliases", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1722 = Array<String>();
    for (var _item1717 in value.withheld) {
        var scratch = base.scratch();
        _m_Withheld_write(scratch, _item1717);
        _hs1722.append(base.hash_of(scratch));
    }
    var _seq1723 = base.sequence("withheld");
    ulong _bj1724 = 0;
    var _news1725 = Array<ulong>();
    for (var _i1726 in 0.._hs1722.count) {
        if (_bj1724 < _seq1723.count and _hs1722[_i1726] == _seq1723[_bj1724]) {
            _bj1724 += 1;
        } else {
            _news1725.append(_i1726);
        }
    }
    if (_bj1724 == _seq1723.count) {
        out.unsigned(2);
        out.unsigned(_news1725.count);
        for (var _i1726 in _news1725) {
            out.unsigned(_i1726);
            _m_Withheld_write(out, value.withheld[_i1726]);
            {
                var _own1727 = RecordOut();
                _own1727.blank_bodies = true;
                _own1727.blank_locs = true;
                _own1727.pending_as_bytes = true;
                _m_Withheld_write(_own1727, value.withheld[_i1726]);
                base.own("withheld", interface_text(_own1727));
            }
        }
        base.count("withheld" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("withheld" + " whole", 0);
        out.unsigned(value.withheld.count);
        for (var _i1726 in 0..value.withheld.count) {
            _m_Withheld_write(out, value.withheld[_i1726]);
            {
                var _own1728 = RecordOut();
                _own1728.blank_bodies = true;
                _own1728.blank_locs = true;
                _own1728.pending_as_bytes = true;
                _m_Withheld_write(_own1728, value.withheld[_i1726]);
                base.own("withheld", interface_text(_own1728));
            }
        }
    }
    base.stat("withheld", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1741 = Array<String>();
    for (var _item1736 in value.properties) {
        var scratch = base.scratch();
        _m_PropertyDef_write(scratch, _item1736);
        _hs1741.append(base.hash_of(scratch));
    }
    var _seq1742 = base.sequence("properties");
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
            _m_PropertyDef_write(out, value.properties[_i1745]);
            {
                var _own1746 = RecordOut();
                _own1746.blank_bodies = true;
                _own1746.blank_locs = true;
                _own1746.pending_as_bytes = true;
                _m_PropertyDef_write(_own1746, value.properties[_i1745]);
                base.own("properties", interface_text(_own1746));
            }
        }
        base.count("properties" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("properties" + " whole", 0);
        out.unsigned(value.properties.count);
        for (var _i1745 in 0..value.properties.count) {
            _m_PropertyDef_write(out, value.properties[_i1745]);
            {
                var _own1747 = RecordOut();
                _own1747.blank_bodies = true;
                _own1747.blank_locs = true;
                _own1747.pending_as_bytes = true;
                _m_PropertyDef_write(_own1747, value.properties[_i1745]);
                base.own("properties", interface_text(_own1747));
            }
        }
    }
    base.stat("properties", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1760 = Array<String>();
    for (var _item1755 in value.type_uses) {
        var scratch = base.scratch();
        _m_TypeUse_write(scratch, _item1755);
        _hs1760.append(base.hash_of(scratch));
    }
    var _seq1761 = base.sequence("type_uses");
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
            _m_TypeUse_write(out, value.type_uses[_i1764]);
            {
                var _own1765 = RecordOut();
                _own1765.blank_bodies = true;
                _own1765.blank_locs = true;
                _own1765.pending_as_bytes = true;
                _m_TypeUse_write(_own1765, value.type_uses[_i1764]);
                base.own("type_uses", interface_text(_own1765));
            }
        }
        base.count("type_uses" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("type_uses" + " whole", 0);
        out.unsigned(value.type_uses.count);
        for (var _i1764 in 0..value.type_uses.count) {
            _m_TypeUse_write(out, value.type_uses[_i1764]);
            {
                var _own1766 = RecordOut();
                _own1766.blank_bodies = true;
                _own1766.blank_locs = true;
                _own1766.pending_as_bytes = true;
                _m_TypeUse_write(_own1766, value.type_uses[_i1764]);
                base.own("type_uses", interface_text(_own1766));
            }
        }
    }
    base.stat("type_uses", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1779 = Array<String>();
    for (var _item1774 in value.use_contexts) {
        var scratch = base.scratch();
        _m_UseContext_write(scratch, _item1774);
        _hs1779.append(base.hash_of(scratch));
    }
    var _seq1780 = base.sequence("use_contexts");
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
            _m_UseContext_write(out, value.use_contexts[_i1783]);
            {
                var _own1784 = RecordOut();
                _own1784.blank_bodies = true;
                _own1784.blank_locs = true;
                _own1784.pending_as_bytes = true;
                _m_UseContext_write(_own1784, value.use_contexts[_i1783]);
                base.own("use_contexts", interface_text(_own1784));
            }
        }
        base.count("use_contexts" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("use_contexts" + " whole", 0);
        out.unsigned(value.use_contexts.count);
        for (var _i1783 in 0..value.use_contexts.count) {
            _m_UseContext_write(out, value.use_contexts[_i1783]);
            {
                var _own1785 = RecordOut();
                _own1785.blank_bodies = true;
                _own1785.blank_locs = true;
                _own1785.pending_as_bytes = true;
                _m_UseContext_write(_own1785, value.use_contexts[_i1783]);
                base.own("use_contexts", interface_text(_own1785));
            }
        }
    }
    base.stat("use_contexts", out.values.count - _mark);
    _mark = out.values.count;
    var _n1795 = base.size("literal_args");
    var _scratch1794 = base.scratch();
    if (value.literal_args.count >= _n1795) {
        for (var _i1796 in 0.._n1795) {
            var (_t1797, _t1798, _t1799) = value.literal_args[_i1796];
            _scratch1794.loc(_t1797);
            _scratch1794.unsigned(_t1798);
            _scratch1794.loc(_t1799);
        }
    }
    if (value.literal_args.count >= _n1795 and base.same_list("literal_args", _scratch1794)) {
        out.unsigned(1);
        out.unsigned(_n1795);
        out.unsigned(value.literal_args.count - _n1795);
        for (var _i1796 in _n1795..value.literal_args.count) {
            var (_t1800, _t1801, _t1802) = value.literal_args[_i1796];
            out.loc(_t1800);
            out.unsigned(_t1801);
            out.loc(_t1802);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.literal_args.count);
        for (var _item1803 in value.literal_args) {
            var (_t1804, _t1805, _t1806) = _item1803;
            out.loc(_t1804);
            out.unsigned(_t1805);
            out.loc(_t1806);
        }
        base.count("literal_args whole", 0);
    }
    base.stat("literal_args", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1829 = Array<String>();
    for (var _item1824 in value.constrained_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1824);
        _hs1829.append(base.hash_of(scratch));
    }
    var _seq1830 = base.sequence("constrained_aliases");
    ulong _bj1831 = 0;
    var _news1832 = Array<ulong>();
    for (var _i1833 in 0.._hs1829.count) {
        if (_bj1831 < _seq1830.count and _hs1829[_i1833] == _seq1830[_bj1831]) {
            _bj1831 += 1;
        } else {
            _news1832.append(_i1833);
        }
    }
    if (_bj1831 == _seq1830.count) {
        out.unsigned(2);
        out.unsigned(_news1832.count);
        for (var _i1833 in _news1832) {
            out.unsigned(_i1833);
            _m_TypeAliasDef_write(out, value.constrained_aliases[_i1833]);
            {
                var _own1834 = RecordOut();
                _own1834.blank_bodies = true;
                _own1834.blank_locs = true;
                _own1834.pending_as_bytes = true;
                _m_TypeAliasDef_write(_own1834, value.constrained_aliases[_i1833]);
                base.own("constrained_aliases", interface_text(_own1834));
            }
        }
        base.count("constrained_aliases" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("constrained_aliases" + " whole", 0);
        out.unsigned(value.constrained_aliases.count);
        for (var _i1833 in 0..value.constrained_aliases.count) {
            _m_TypeAliasDef_write(out, value.constrained_aliases[_i1833]);
            {
                var _own1835 = RecordOut();
                _own1835.blank_bodies = true;
                _own1835.blank_locs = true;
                _own1835.pending_as_bytes = true;
                _m_TypeAliasDef_write(_own1835, value.constrained_aliases[_i1833]);
                base.own("constrained_aliases", interface_text(_own1835));
            }
        }
    }
    base.stat("constrained_aliases", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1848 = Array<String>();
    for (var _item1843 in value.trait_types) {
        var scratch = base.scratch();
        _m_TraitType_write(scratch, _item1843);
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
            base.own_at("private_functions", _okey2066, interface_text(_own2067));
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
            base.own_at("private_functions", _okey2073, interface_text(_own2074));
        }
        base.count("private_functions whole", 0);
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
            base.own_at("file_private_functions", _okey2092, interface_text(_own2093));
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
            base.own_at("file_private_functions", _okey2099, interface_text(_own2100));
        }
        base.count("file_private_functions whole", 0);
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
    base.stat("stripped", out.values.count - _mark);
    _mark = out.values.count;
    out.flag(value.templates.frozen);
    var _seq2233 = base.ref_templates;
    ulong _bj2234 = 0;
    var _news2236 = Array<ulong>();
    var _patches2237 = Array<(ulong, ulong)>();
    for (var _i2238 in 0..value.templates.structs.count) {
        if (_bj2234 < _seq2233.count
            and value.templates.structs[_i2238] === _seq2233[_bj2234]
            and !value.extended_checked.contains(value.templates.structs[_i2238].name)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_StructDef_write(scratch, value.templates.structs[_i2238]);
                base.verify_same("t", _bj2234, scratch, value.templates.structs[_i2238].name);
            }
            _bj2234 += 1;
        } else if (_bj2234 < _seq2233.count
            and !(value.templates.structs[_i2238] === _seq2233[_bj2234])
            and _same_m_StructDef(value.templates.structs[_i2238], _seq2233[_bj2234], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_StructDef_write(scratch, value.templates.structs[_i2238]);
                base.verify_same("t", _bj2234, scratch, value.templates.structs[_i2238].name);
            }
            _bj2234 += 1;
        } else if (_bj2234 < _seq2233.count and value.templates.structs[_i2238].name == _seq2233[_bj2234].name) {
            _patches2237.append((_i2238, _bj2234));
            _bj2234 += 1;
        } else {
            _news2236.append(_i2238);
        }
    }
    if (_bj2234 == _seq2233.count) {
        out.unsigned(2);
        out.unsigned(_patches2237.count);
        for (var (_i2238, _b) in _patches2237) {
            ulong _before = out.values.count;
            out.text(value.templates.structs[_i2238].name);
            out.unsigned(_b);
            _patch_t_write(out, value.templates.structs[_i2238], base, _b);
            base.count("t patched", out.values.count - _before);
            {
                var _own2239 = RecordOut();
                _own2239.blank_bodies = false;
                _own2239.blank_locs = true;
                _own2239.pending_as_bytes = true;
                _m_StructDef_write(_own2239, value.templates.structs[_i2238]);
                base.own("templates structs", interface_text(_own2239));
            }
        }
        out.unsigned(_news2236.count);
        for (var _i2238 in _news2236) {
            ulong _before = out.values.count;
            out.unsigned(_i2238);
            _m_StructDef_write(out, value.templates.structs[_i2238]);
            base.count("t new", out.values.count - _before);
            {
                var _own2240 = RecordOut();
                _own2240.blank_bodies = false;
                _own2240.blank_locs = true;
                _own2240.pending_as_bytes = true;
                _m_StructDef_write(_own2240, value.templates.structs[_i2238]);
                base.own("templates structs", interface_text(_own2240));
            }
        }
        base.count("t merged", 0);
    } else {
        out.unsigned(1);
        base.count("t by place", 0);
        var _struct_hits2232 = HashSet<long>();
        var _slots2235 = HashMap<String, long>();
        for (var _i2238 in 0.._seq2233.count) {
            if (!_slots2235.contains(_seq2233[_i2238].name)) {
                _slots2235[_seq2233[_i2238].name] = _i2238 as long;
            }
        }
        out.unsigned(value.templates.structs.count);
        for (var _i2238 in 0..value.templates.structs.count) {
            var _item2231 = value.templates.structs[_i2238];
            var _slot = _slots2235.try_get(_item2231.name);
            long named = _slot.is_value() ? _slot.value() : -1;
            long at = -1;
            if (named >= 0
                and _seq2233[named as ulong] === _item2231
                and !value.extended_checked.contains(_item2231.name)) {
                at = named;
            }
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
    var _seq2254 = base.ref_template_functions;
    ulong _bj2255 = 0;
    var _news2256 = Array<ulong>();
    var _changed2250 = Array<(ulong, ulong)>();
    for (var _i2257 in 0..value.templates.functions.count) {
        if (_bj2255 < _seq2254.count and value.templates.functions[_i2257] === _seq2254[_bj2255]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.templates.functions[_i2257]);
                base.verify_same("tf", _bj2255, scratch);
            }
            _bj2255 += 1;
        } else if (_bj2255 < _seq2254.count
            and _same_m_FunctionDef(value.templates.functions[_i2257], _seq2254[_bj2255], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.templates.functions[_i2257]);
                base.verify_same("tf", _bj2255, scratch);
            }
            _bj2255 += 1;
        } else if (_bj2255 < _seq2254.count and value.templates.functions[_i2257].name == _seq2254[_bj2255].name) {
            _changed2250.append((_i2257, _bj2255));
            _bj2255 += 1;
        } else {
            _news2256.append(_i2257);
        }
    }
    if (_bj2255 == _seq2254.count) {
        out.unsigned(2);
        out.unsigned(_changed2250.count);
        for (var (_i2257, _b) in _changed2250) {
            out.text(value.templates.functions[_i2257].name);
            out.unsigned(_b);
            _m_FunctionDef_write(out, value.templates.functions[_i2257]);
            {
                var _own2258 = RecordOut();
                _own2258.blank_bodies = false;
                _own2258.blank_locs = true;
                _own2258.pending_as_bytes = true;
                _m_FunctionDef_write(_own2258, value.templates.functions[_i2257]);
                base.own("templates functions", interface_text(_own2258));
            }
        }
        base.count("tf" + " changed", _changed2250.count);
        out.unsigned(_news2256.count);
        for (var _i2257 in _news2256) {
            out.unsigned(_i2257);
            _m_FunctionDef_write(out, value.templates.functions[_i2257]);
            {
                var _own2259 = RecordOut();
                _own2259.blank_bodies = false;
                _own2259.blank_locs = true;
                _own2259.pending_as_bytes = true;
                _m_FunctionDef_write(_own2259, value.templates.functions[_i2257]);
                base.own("templates functions", interface_text(_own2259));
            }
        }
        base.count("tf" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("tf" + " whole", 0);
        out.unsigned(value.templates.functions.count);
        for (var _i2257 in 0..value.templates.functions.count) {
            _m_FunctionDef_write(out, value.templates.functions[_i2257]);
            {
                var _own2260 = RecordOut();
                _own2260.blank_bodies = false;
                _own2260.blank_locs = true;
                _own2260.pending_as_bytes = true;
                _m_FunctionDef_write(_own2260, value.templates.functions[_i2257]);
                base.own("templates functions", interface_text(_own2260));
            }
        }
    }
    base.stat("templates", out.values.count - _mark);
    _mark = out.values.count;
    base.write_checked(out, value.checked);
    base.stat("checked", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2273 = 0;
    var _news2274 = HashMap<String, SpecRequest>();
    for (var (_key2270, _) in value.spec_requests) {
        var _kscratch2271 = base.scratch();
        _kscratch2271.text(_key2270);
        var _vscratch2272 = base.scratch();
        _m_SpecRequest_write(_vscratch2272, value.spec_requests[_key2270]);
        var _had = base.entry("spec_requests", _kscratch2271, _vscratch2272);
        if (_had >= 0) {
            _kept2273 += 1;
        }
        if (_had != 1) {
            _news2274[_key2270] = value.spec_requests[_key2270];
        }
    }
    if (_kept2273 == base.size("spec_requests")) {
        out.unsigned(1);
        var _keys2276 = Array<(u8[], u8[], String)>();
        for (var (_key2275, _) in _news2274) {
            var _scratch2277 = out.scratch();
            _scratch2277.text(_key2275);
            var _vscratch2279 = out.scratch();
            _m_SpecRequest_write(_vscratch2279, _news2274[_key2275]);
            _keys2276.append((_scratch2277.finish(), _vscratch2279.finish(), _key2275));
        }
        _keys2276.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2276.count);
        for (var (_bytes2278, _, _key2275) in _keys2276) {
            out.text(_key2275);
            _m_SpecRequest_write(out, _news2274[_key2275]);
        }
        for (var (_okey2280, _) in _news2274) {
            var _own2281 = RecordOut();
            _own2281.blank_bodies = true;
            _own2281.blank_locs = true;
            _own2281.pending_as_bytes = true;
            _own2281.text(_okey2280);
            _m_SpecRequest_write(_own2281, _news2274[_okey2280]);
            base.own("spec_requests", interface_text(_own2281));
        }
    } else {
        out.unsigned(0);
        var _keys2283 = Array<(u8[], u8[], String)>();
        for (var (_key2282, _) in value.spec_requests) {
            var _scratch2284 = out.scratch();
            _scratch2284.text(_key2282);
            var _vscratch2286 = out.scratch();
            _m_SpecRequest_write(_vscratch2286, value.spec_requests[_key2282]);
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
            _m_SpecRequest_write(out, value.spec_requests[_key2282]);
        }
        for (var (_okey2287, _) in value.spec_requests) {
            var _own2288 = RecordOut();
            _own2288.blank_bodies = true;
            _own2288.blank_locs = true;
            _own2288.pending_as_bytes = true;
            _own2288.text(_okey2287);
            _m_SpecRequest_write(_own2288, value.spec_requests[_okey2287]);
            base.own("spec_requests", interface_text(_own2288));
        }
        base.count("spec_requests whole", 0);
    }
    base.stat("spec_requests", out.values.count - _mark);
    _mark = out.values.count;
    out.flag(value.record_summaries);
    base.stat("record_summaries", out.values.count - _mark);
    _mark = out.values.count;
    var _n2301 = base.size("summaries_to_record");
    var _scratch2300 = base.scratch();
    if (value.summaries_to_record.count >= _n2301) {
        for (var _i2302 in 0.._n2301) {
            var (_t2303, _t2304) = value.summaries_to_record[_i2302];
            _scratch2300.loc(_t2303);
            _scratch2300.text(_t2304);
        }
    }
    if (value.summaries_to_record.count >= _n2301 and base.same_list("summaries_to_record", _scratch2300)) {
        out.unsigned(1);
        out.unsigned(_n2301);
        out.unsigned(value.summaries_to_record.count - _n2301);
        for (var _i2302 in _n2301..value.summaries_to_record.count) {
            var (_t2305, _t2306) = value.summaries_to_record[_i2302];
            out.loc(_t2305);
            out.text(_t2306);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.summaries_to_record.count);
        for (var _item2307 in value.summaries_to_record) {
            var (_t2308, _t2309) = _item2307;
            out.loc(_t2308);
            out.text(_t2309);
        }
        base.count("summaries_to_record whole", 0);
    }
    base.stat("summaries_to_record", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2327 = 0;
    var _news2328 = HashMap<String, Array<bool>>();
    for (var (_key2324, _) in value.caller_copies) {
        var _kscratch2325 = base.scratch();
        _kscratch2325.text(_key2324);
        var _vscratch2326 = base.scratch();
        _vscratch2326.unsigned(value.caller_copies[_key2324].count);
        for (var _item2329 in value.caller_copies[_key2324]) {
            _vscratch2326.flag(_item2329);
        }
        var _had = base.entry("caller_copies", _kscratch2325, _vscratch2326);
        if (_had >= 0) {
            _kept2327 += 1;
        }
        if (_had != 1) {
            _news2328[_key2324] = value.caller_copies[_key2324];
        }
    }
    if (_kept2327 == base.size("caller_copies")) {
        out.unsigned(1);
        var _keys2331 = Array<(u8[], u8[], String)>();
        for (var (_key2330, _) in _news2328) {
            var _scratch2332 = out.scratch();
            _scratch2332.text(_key2330);
            var _vscratch2334 = out.scratch();
            _vscratch2334.unsigned(_news2328[_key2330].count);
            for (var _item2335 in _news2328[_key2330]) {
                _vscratch2334.flag(_item2335);
            }
            _keys2331.append((_scratch2332.finish(), _vscratch2334.finish(), _key2330));
        }
        _keys2331.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2331.count);
        for (var (_bytes2333, _, _key2330) in _keys2331) {
            out.text(_key2330);
            out.unsigned(_news2328[_key2330].count);
            for (var _item2336 in _news2328[_key2330]) {
                out.flag(_item2336);
            }
        }
        for (var (_okey2337, _) in _news2328) {
            var _own2338 = RecordOut();
            _own2338.blank_bodies = true;
            _own2338.blank_locs = true;
            _own2338.pending_as_bytes = true;
            _own2338.text(_okey2337);
            _own2338.unsigned(_news2328[_okey2337].count);
            for (var _item2339 in _news2328[_okey2337]) {
                _own2338.flag(_item2339);
            }
            base.own("caller_copies", interface_text(_own2338));
        }
    } else {
        out.unsigned(0);
        var _keys2341 = Array<(u8[], u8[], String)>();
        for (var (_key2340, _) in value.caller_copies) {
            var _scratch2342 = out.scratch();
            _scratch2342.text(_key2340);
            var _vscratch2344 = out.scratch();
            _vscratch2344.unsigned(value.caller_copies[_key2340].count);
            for (var _item2345 in value.caller_copies[_key2340]) {
                _vscratch2344.flag(_item2345);
            }
            _keys2341.append((_scratch2342.finish(), _vscratch2344.finish(), _key2340));
        }
        _keys2341.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2341.count);
        for (var (_bytes2343, _, _key2340) in _keys2341) {
            out.text(_key2340);
            out.unsigned(value.caller_copies[_key2340].count);
            for (var _item2346 in value.caller_copies[_key2340]) {
                out.flag(_item2346);
            }
        }
        for (var (_okey2347, _) in value.caller_copies) {
            var _own2348 = RecordOut();
            _own2348.blank_bodies = true;
            _own2348.blank_locs = true;
            _own2348.pending_as_bytes = true;
            _own2348.text(_okey2347);
            _own2348.unsigned(value.caller_copies[_okey2347].count);
            for (var _item2349 in value.caller_copies[_okey2347]) {
                _own2348.flag(_item2349);
            }
            base.own("caller_copies", interface_text(_own2348));
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
    var _f1496 = Array<ast.Import>();
    var _mode1499 = input.unsigned();
    if (_mode1499 == 2) {
        var _changed1485 = HashMap<ulong, ast.Import>();
        ulong _bi1500 = 0;
        var _n1497 = input.count();
        for (var _ in 0.._n1497) {
            var _at1501 = input.unsigned();
            while (_f1496.count < _at1501 or (input.merging and _bi1500 < base.imports.count)) {
                var _c = _changed1485.try_get(_bi1500);
                _f1496.append(_c.is_value() ? _c.value() : base.imports[_bi1500]);
                _bi1500 += 1;
            }
            _f1496.append(_a_Import_read(input));
        }
        while (_bi1500 < base.imports.count) {
            var _c = _changed1485.try_get(_bi1500);
            _f1496.append(_c.is_value() ? _c.value() : base.imports[_bi1500]);
            _bi1500 += 1;
        }
    } else if (_mode1499 == 3) {
        var _n1497 = input.count();
        for (var _ in 0.._n1497) {
            _f1496.append(_a_Import_read(input));
        }
    } else {
        var _n1497 = input.count();
        if (input.merging) {
            input.error = "imports" + " written by place";
        }
        for (var _ in 0.._n1497) {
            var _tag1498 = input.unsigned();
            if (_tag1498 & 1 == 1) {
                if (!input.merging) {
                    _f1496.append(base.imports[_tag1498 >> 1]);
                }
            } else {
                var _read = _a_Import_read(input);
                if (!input.merging or true) {
                    _f1496.append(_read);
                }
            }
        }
    }
    var _f1529 = Array<StructDef>();
    var _mode1532 = input.unsigned();
    if (_mode1532 == 2) {
        var _patched1535 = HashMap<ulong, StructDef>();
        var _n1530 = input.count();
        for (var _ in 0.._n1530) {
            var _name = input.text();
            var _slot = input.unsigned();
            if (input.merging) {
                _slot = struct_named(base.structs, _name);
            }
            if (_slot >= base.structs.count) {
                input.error = $"no struct {_name} to patch";
                break;
            }
            _patched1535[_slot] = _patch_s_read(input, base.structs[_slot]);
        }
        ulong _bi1533 = 0;
        var _added = input.count();
        for (var _ in 0.._added) {
            var _at1534 = input.unsigned();
            while (_f1529.count < _at1534 or (input.merging and _bi1533 < base.structs.count)) {
                var _p = _patched1535.try_get(_bi1533);
                _f1529.append(_p.is_value() ? _p.value() : base.structs[_bi1533]);
                _bi1533 += 1;
            }
            _f1529.append(_m_StructDef_read_lazy(input));
        }
        while (_bi1533 < base.structs.count) {
            var _p = _patched1535.try_get(_bi1533);
            _f1529.append(_p.is_value() ? _p.value() : base.structs[_bi1533]);
            _bi1533 += 1;
        }
    } else {
        if (input.merging) {
            input.error = "structs written by place";
        }
        var _n1530 = input.count();
        for (var _ in 0.._n1530) {
            var _tag1531 = input.unsigned();
            if (_tag1531 & 1 == 1) {
                _f1529.append(base.structs[(_tag1531 >> 1) < base.structs.count ? _tag1531 >> 1 : 0]);
            } else if (_tag1531 == 2) {
                var _was = base.structs[input.unsigned()];
                _f1529.append(_patch_s_read(input, _was));
            } else {
                _f1529.append(_m_StructDef_read_lazy(input));
            }
        }
    }
    var _f1549 = Array<TraitDef>();
    var _mode1552 = input.unsigned();
    if (_mode1552 == 2) {
        var _changed1538 = HashMap<ulong, TraitDef>();
        ulong _bi1553 = 0;
        var _n1550 = input.count();
        for (var _ in 0.._n1550) {
            var _at1554 = input.unsigned();
            while (_f1549.count < _at1554 or (input.merging and _bi1553 < base.traits.count)) {
                var _c = _changed1538.try_get(_bi1553);
                _f1549.append(_c.is_value() ? _c.value() : base.traits[_bi1553]);
                _bi1553 += 1;
            }
            _f1549.append(_m_TraitDef_read(input));
        }
        while (_bi1553 < base.traits.count) {
            var _c = _changed1538.try_get(_bi1553);
            _f1549.append(_c.is_value() ? _c.value() : base.traits[_bi1553]);
            _bi1553 += 1;
        }
    } else if (_mode1552 == 3) {
        var _n1550 = input.count();
        for (var _ in 0.._n1550) {
            _f1549.append(_m_TraitDef_read(input));
        }
    } else {
        var _n1550 = input.count();
        if (input.merging) {
            input.error = "traits" + " written by place";
        }
        for (var _ in 0.._n1550) {
            var _tag1551 = input.unsigned();
            if (_tag1551 & 1 == 1) {
                if (!input.merging) {
                    _f1549.append(base.traits[_tag1551 >> 1]);
                }
            } else {
                var _read = _m_TraitDef_read(input);
                if (!input.merging or true) {
                    _f1549.append(_read);
                }
            }
        }
    }
    var _f1568 = Array<ExtensionDef>();
    var _mode1571 = input.unsigned();
    if (_mode1571 == 2) {
        var _changed1557 = HashMap<ulong, ExtensionDef>();
        ulong _bi1572 = 0;
        var _n1569 = input.count();
        for (var _ in 0.._n1569) {
            var _at1573 = input.unsigned();
            while (_f1568.count < _at1573 or (input.merging and _bi1572 < base.extensions.count)) {
                var _c = _changed1557.try_get(_bi1572);
                _f1568.append(_c.is_value() ? _c.value() : base.extensions[_bi1572]);
                _bi1572 += 1;
            }
            _f1568.append(_m_ExtensionDef_read(input));
        }
        while (_bi1572 < base.extensions.count) {
            var _c = _changed1557.try_get(_bi1572);
            _f1568.append(_c.is_value() ? _c.value() : base.extensions[_bi1572]);
            _bi1572 += 1;
        }
    } else if (_mode1571 == 3) {
        var _n1569 = input.count();
        for (var _ in 0.._n1569) {
            _f1568.append(_m_ExtensionDef_read(input));
        }
    } else {
        var _n1569 = input.count();
        if (input.merging) {
            input.error = "extensions" + " written by place";
        }
        for (var _ in 0.._n1569) {
            var _tag1570 = input.unsigned();
            if (_tag1570 & 1 == 1) {
                if (!input.merging) {
                    _f1568.append(base.extensions[_tag1570 >> 1]);
                }
            } else {
                var _read = _m_ExtensionDef_read(input);
                if (!input.merging or true) {
                    _f1568.append(_read);
                }
            }
        }
    }
    var _f1587 = Array<FunctionDef>();
    var _mode1590 = input.unsigned();
    if (_mode1590 == 2) {
        var _changed1576 = HashMap<ulong, FunctionDef>();
        var _nc1578 = input.count();
        for (var _ in 0.._nc1578) {
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
                _changed1576[_slot] = _el;
            } else {
                input.error = $"no {_name} to change";
            }
        }
        ulong _bi1591 = 0;
        var _n1588 = input.count();
        for (var _ in 0.._n1588) {
            var _at1592 = input.unsigned();
            while (_f1587.count < _at1592 or (input.merging and _bi1591 < base.functions.count)) {
                var _c = _changed1576.try_get(_bi1591);
                _f1587.append(_c.is_value() ? _c.value() : base.functions[_bi1591]);
                _bi1591 += 1;
            }
            _f1587.append(_m_FunctionDef_read_lazy(input));
        }
        while (_bi1591 < base.functions.count) {
            var _c = _changed1576.try_get(_bi1591);
            _f1587.append(_c.is_value() ? _c.value() : base.functions[_bi1591]);
            _bi1591 += 1;
        }
    } else if (_mode1590 == 3) {
        var _n1588 = input.count();
        for (var _ in 0.._n1588) {
            _f1587.append(_m_FunctionDef_read_lazy(input));
        }
    } else {
        var _n1588 = input.count();
        if (input.merging) {
            input.error = "functions" + " written by place";
        }
        for (var _ in 0.._n1588) {
            var _tag1589 = input.unsigned();
            if (_tag1589 & 1 == 1) {
                if (!input.merging) {
                    _f1587.append(base.functions[_tag1589 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read_lazy(input);
                if (!input.merging or true) {
                    _f1587.append(_read);
                }
            }
        }
    }
    var _f1606 = Array<ExternDef>();
    var _mode1609 = input.unsigned();
    if (_mode1609 == 2) {
        var _changed1595 = HashMap<ulong, ExternDef>();
        ulong _bi1610 = 0;
        var _n1607 = input.count();
        for (var _ in 0.._n1607) {
            var _at1611 = input.unsigned();
            while (_f1606.count < _at1611 or (input.merging and _bi1610 < base.externs.count)) {
                var _c = _changed1595.try_get(_bi1610);
                _f1606.append(_c.is_value() ? _c.value() : base.externs[_bi1610]);
                _bi1610 += 1;
            }
            _f1606.append(_m_ExternDef_read(input));
        }
        while (_bi1610 < base.externs.count) {
            var _c = _changed1595.try_get(_bi1610);
            _f1606.append(_c.is_value() ? _c.value() : base.externs[_bi1610]);
            _bi1610 += 1;
        }
    } else if (_mode1609 == 3) {
        var _n1607 = input.count();
        for (var _ in 0.._n1607) {
            _f1606.append(_m_ExternDef_read(input));
        }
    } else {
        var _n1607 = input.count();
        if (input.merging) {
            input.error = "externs" + " written by place";
        }
        for (var _ in 0.._n1607) {
            var _tag1608 = input.unsigned();
            if (_tag1608 & 1 == 1) {
                if (!input.merging) {
                    _f1606.append(base.externs[_tag1608 >> 1]);
                }
            } else {
                var _read = _m_ExternDef_read(input);
                if (!input.merging or true) {
                    _f1606.append(_read);
                }
            }
        }
    }
    var _f1625 = Array<VariableDef>();
    var _mode1628 = input.unsigned();
    if (_mode1628 == 2) {
        var _changed1614 = HashMap<ulong, VariableDef>();
        ulong _bi1629 = 0;
        var _n1626 = input.count();
        for (var _ in 0.._n1626) {
            var _at1630 = input.unsigned();
            while (_f1625.count < _at1630 or (input.merging and _bi1629 < base.globals.count)) {
                var _c = _changed1614.try_get(_bi1629);
                _f1625.append(_c.is_value() ? _c.value() : base.globals[_bi1629]);
                _bi1629 += 1;
            }
            _f1625.append(_m_VariableDef_read(input));
        }
        while (_bi1629 < base.globals.count) {
            var _c = _changed1614.try_get(_bi1629);
            _f1625.append(_c.is_value() ? _c.value() : base.globals[_bi1629]);
            _bi1629 += 1;
        }
    } else if (_mode1628 == 3) {
        var _n1626 = input.count();
        for (var _ in 0.._n1626) {
            _f1625.append(_m_VariableDef_read(input));
        }
    } else {
        var _n1626 = input.count();
        if (input.merging) {
            input.error = "globals" + " written by place";
        }
        for (var _ in 0.._n1626) {
            var _tag1627 = input.unsigned();
            if (_tag1627 & 1 == 1) {
                if (!input.merging) {
                    _f1625.append(base.globals[_tag1627 >> 1]);
                }
            } else {
                var _read = _m_VariableDef_read(input);
                if (!input.merging or true) {
                    _f1625.append(_read);
                }
            }
        }
    }
    var _f1644 = Array<ModuleStaticBlock>();
    var _mode1647 = input.unsigned();
    if (_mode1647 == 2) {
        var _changed1633 = HashMap<ulong, ModuleStaticBlock>();
        ulong _bi1648 = 0;
        var _n1645 = input.count();
        for (var _ in 0.._n1645) {
            var _at1649 = input.unsigned();
            while (_f1644.count < _at1649 or (input.merging and _bi1648 < base.static_blocks.count)) {
                var _c = _changed1633.try_get(_bi1648);
                _f1644.append(_c.is_value() ? _c.value() : base.static_blocks[_bi1648]);
                _bi1648 += 1;
            }
            _f1644.append(_m_ModuleStaticBlock_read(input));
        }
        while (_bi1648 < base.static_blocks.count) {
            var _c = _changed1633.try_get(_bi1648);
            _f1644.append(_c.is_value() ? _c.value() : base.static_blocks[_bi1648]);
            _bi1648 += 1;
        }
    } else if (_mode1647 == 3) {
        var _n1645 = input.count();
        for (var _ in 0.._n1645) {
            _f1644.append(_m_ModuleStaticBlock_read(input));
        }
    } else {
        var _n1645 = input.count();
        if (input.merging) {
            input.error = "static_blocks" + " written by place";
        }
        for (var _ in 0.._n1645) {
            var _tag1646 = input.unsigned();
            if (_tag1646 & 1 == 1) {
                if (!input.merging) {
                    _f1644.append(base.static_blocks[_tag1646 >> 1]);
                }
            } else {
                var _read = _m_ModuleStaticBlock_read(input);
                if (!input.merging or true) {
                    _f1644.append(_read);
                }
            }
        }
    }
    var _f1663 = Array<EnumDef>();
    var _mode1666 = input.unsigned();
    if (_mode1666 == 2) {
        var _changed1652 = HashMap<ulong, EnumDef>();
        ulong _bi1667 = 0;
        var _n1664 = input.count();
        for (var _ in 0.._n1664) {
            var _at1668 = input.unsigned();
            while (_f1663.count < _at1668 or (input.merging and _bi1667 < base.enums.count)) {
                var _c = _changed1652.try_get(_bi1667);
                _f1663.append(_c.is_value() ? _c.value() : base.enums[_bi1667]);
                _bi1667 += 1;
            }
            _f1663.append(_m_EnumDef_read(input));
        }
        while (_bi1667 < base.enums.count) {
            var _c = _changed1652.try_get(_bi1667);
            _f1663.append(_c.is_value() ? _c.value() : base.enums[_bi1667]);
            _bi1667 += 1;
        }
    } else if (_mode1666 == 3) {
        var _n1664 = input.count();
        for (var _ in 0.._n1664) {
            _f1663.append(_m_EnumDef_read(input));
        }
    } else {
        var _n1664 = input.count();
        if (input.merging) {
            input.error = "enums" + " written by place";
        }
        for (var _ in 0.._n1664) {
            var _tag1665 = input.unsigned();
            if (_tag1665 & 1 == 1) {
                if (!input.merging) {
                    _f1663.append(base.enums[_tag1665 >> 1]);
                }
            } else {
                var _read = _m_EnumDef_read(input);
                if (!input.merging or true) {
                    _f1663.append(_read);
                }
            }
        }
    }
    var _f1682 = Array<TypeName>();
    var _mode1685 = input.unsigned();
    if (_mode1685 == 2) {
        var _changed1671 = HashMap<ulong, TypeName>();
        ulong _bi1686 = 0;
        var _n1683 = input.count();
        for (var _ in 0.._n1683) {
            var _at1687 = input.unsigned();
            while (_f1682.count < _at1687 or (input.merging and _bi1686 < base.struct_specs.count)) {
                var _c = _changed1671.try_get(_bi1686);
                _f1682.append(_c.is_value() ? _c.value() : base.struct_specs[_bi1686]);
                _bi1686 += 1;
            }
            _f1682.append(_m_TypeName_read(input));
        }
        while (_bi1686 < base.struct_specs.count) {
            var _c = _changed1671.try_get(_bi1686);
            _f1682.append(_c.is_value() ? _c.value() : base.struct_specs[_bi1686]);
            _bi1686 += 1;
        }
    } else if (_mode1685 == 3) {
        var _n1683 = input.count();
        for (var _ in 0.._n1683) {
            _f1682.append(_m_TypeName_read(input));
        }
    } else {
        var _n1683 = input.count();
        if (input.merging) {
            input.error = "struct_specs" + " written by place";
        }
        for (var _ in 0.._n1683) {
            var _tag1684 = input.unsigned();
            if (_tag1684 & 1 == 1) {
                if (!input.merging) {
                    _f1682.append(base.struct_specs[_tag1684 >> 1]);
                }
            } else {
                var _read = _m_TypeName_read(input);
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
            while (_f1701.count < _at1706 or (input.merging and _bi1705 < base.func_specs.count)) {
                var _c = _changed1690.try_get(_bi1705);
                _f1701.append(_c.is_value() ? _c.value() : base.func_specs[_bi1705]);
                _bi1705 += 1;
            }
            _f1701.append(_m_TypeName_read(input));
        }
        while (_bi1705 < base.func_specs.count) {
            var _c = _changed1690.try_get(_bi1705);
            _f1701.append(_c.is_value() ? _c.value() : base.func_specs[_bi1705]);
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
            input.error = "func_specs" + " written by place";
        }
        for (var _ in 0.._n1702) {
            var _tag1703 = input.unsigned();
            if (_tag1703 & 1 == 1) {
                if (!input.merging) {
                    _f1701.append(base.func_specs[_tag1703 >> 1]);
                }
            } else {
                var _read = _m_TypeName_read(input);
                if (!input.merging or true) {
                    _f1701.append(_read);
                }
            }
        }
    }
    var _f1713 = Array<TypeAliasDef>();
    var _n1714 = input.count();
    if (input.merging) {
        for (var _b in base.type_aliases) {
            _f1713.append(_b);
        }
    }
    for (var _ in 0.._n1714) {
        var _tag1715 = input.unsigned();
        if (_tag1715 & 1 == 1) {
            if (!input.merging) {
                _f1713.append(base.type_aliases[_tag1715 >> 1]);
            }
        } else {
            var _read = _m_TypeAliasDef_read(input);
            if (!input.merging or false) {
                _f1713.append(_read);
            }
        }
    }
    var _f1729 = Array<Withheld>();
    var _mode1732 = input.unsigned();
    if (_mode1732 == 2) {
        var _changed1718 = HashMap<ulong, Withheld>();
        ulong _bi1733 = 0;
        var _n1730 = input.count();
        for (var _ in 0.._n1730) {
            var _at1734 = input.unsigned();
            while (_f1729.count < _at1734 or (input.merging and _bi1733 < base.withheld.count)) {
                var _c = _changed1718.try_get(_bi1733);
                _f1729.append(_c.is_value() ? _c.value() : base.withheld[_bi1733]);
                _bi1733 += 1;
            }
            _f1729.append(_m_Withheld_read(input));
        }
        while (_bi1733 < base.withheld.count) {
            var _c = _changed1718.try_get(_bi1733);
            _f1729.append(_c.is_value() ? _c.value() : base.withheld[_bi1733]);
            _bi1733 += 1;
        }
    } else if (_mode1732 == 3) {
        var _n1730 = input.count();
        for (var _ in 0.._n1730) {
            _f1729.append(_m_Withheld_read(input));
        }
    } else {
        var _n1730 = input.count();
        if (input.merging) {
            input.error = "withheld" + " written by place";
        }
        for (var _ in 0.._n1730) {
            var _tag1731 = input.unsigned();
            if (_tag1731 & 1 == 1) {
                if (!input.merging) {
                    _f1729.append(base.withheld[_tag1731 >> 1]);
                }
            } else {
                var _read = _m_Withheld_read(input);
                if (!input.merging or true) {
                    _f1729.append(_read);
                }
            }
        }
    }
    var _f1748 = Array<PropertyDef>();
    var _mode1751 = input.unsigned();
    if (_mode1751 == 2) {
        var _changed1737 = HashMap<ulong, PropertyDef>();
        ulong _bi1752 = 0;
        var _n1749 = input.count();
        for (var _ in 0.._n1749) {
            var _at1753 = input.unsigned();
            while (_f1748.count < _at1753 or (input.merging and _bi1752 < base.properties.count)) {
                var _c = _changed1737.try_get(_bi1752);
                _f1748.append(_c.is_value() ? _c.value() : base.properties[_bi1752]);
                _bi1752 += 1;
            }
            _f1748.append(_m_PropertyDef_read(input));
        }
        while (_bi1752 < base.properties.count) {
            var _c = _changed1737.try_get(_bi1752);
            _f1748.append(_c.is_value() ? _c.value() : base.properties[_bi1752]);
            _bi1752 += 1;
        }
    } else if (_mode1751 == 3) {
        var _n1749 = input.count();
        for (var _ in 0.._n1749) {
            _f1748.append(_m_PropertyDef_read(input));
        }
    } else {
        var _n1749 = input.count();
        if (input.merging) {
            input.error = "properties" + " written by place";
        }
        for (var _ in 0.._n1749) {
            var _tag1750 = input.unsigned();
            if (_tag1750 & 1 == 1) {
                if (!input.merging) {
                    _f1748.append(base.properties[_tag1750 >> 1]);
                }
            } else {
                var _read = _m_PropertyDef_read(input);
                if (!input.merging or true) {
                    _f1748.append(_read);
                }
            }
        }
    }
    var _f1767 = Array<TypeUse>();
    var _mode1770 = input.unsigned();
    if (_mode1770 == 2) {
        var _changed1756 = HashMap<ulong, TypeUse>();
        ulong _bi1771 = 0;
        var _n1768 = input.count();
        for (var _ in 0.._n1768) {
            var _at1772 = input.unsigned();
            while (_f1767.count < _at1772 or (input.merging and _bi1771 < base.type_uses.count)) {
                var _c = _changed1756.try_get(_bi1771);
                _f1767.append(_c.is_value() ? _c.value() : base.type_uses[_bi1771]);
                _bi1771 += 1;
            }
            _f1767.append(_m_TypeUse_read(input));
        }
        while (_bi1771 < base.type_uses.count) {
            var _c = _changed1756.try_get(_bi1771);
            _f1767.append(_c.is_value() ? _c.value() : base.type_uses[_bi1771]);
            _bi1771 += 1;
        }
    } else if (_mode1770 == 3) {
        var _n1768 = input.count();
        for (var _ in 0.._n1768) {
            _f1767.append(_m_TypeUse_read(input));
        }
    } else {
        var _n1768 = input.count();
        if (input.merging) {
            input.error = "type_uses" + " written by place";
        }
        for (var _ in 0.._n1768) {
            var _tag1769 = input.unsigned();
            if (_tag1769 & 1 == 1) {
                if (!input.merging) {
                    _f1767.append(base.type_uses[_tag1769 >> 1]);
                }
            } else {
                var _read = _m_TypeUse_read(input);
                if (!input.merging or true) {
                    _f1767.append(_read);
                }
            }
        }
    }
    var _f1786 = Array<UseContext>();
    var _mode1789 = input.unsigned();
    if (_mode1789 == 2) {
        var _changed1775 = HashMap<ulong, UseContext>();
        ulong _bi1790 = 0;
        var _n1787 = input.count();
        for (var _ in 0.._n1787) {
            var _at1791 = input.unsigned();
            while (_f1786.count < _at1791 or (input.merging and _bi1790 < base.use_contexts.count)) {
                var _c = _changed1775.try_get(_bi1790);
                _f1786.append(_c.is_value() ? _c.value() : base.use_contexts[_bi1790]);
                _bi1790 += 1;
            }
            _f1786.append(_m_UseContext_read(input));
        }
        while (_bi1790 < base.use_contexts.count) {
            var _c = _changed1775.try_get(_bi1790);
            _f1786.append(_c.is_value() ? _c.value() : base.use_contexts[_bi1790]);
            _bi1790 += 1;
        }
    } else if (_mode1789 == 3) {
        var _n1787 = input.count();
        for (var _ in 0.._n1787) {
            _f1786.append(_m_UseContext_read(input));
        }
    } else {
        var _n1787 = input.count();
        if (input.merging) {
            input.error = "use_contexts" + " written by place";
        }
        for (var _ in 0.._n1787) {
            var _tag1788 = input.unsigned();
            if (_tag1788 & 1 == 1) {
                if (!input.merging) {
                    _f1786.append(base.use_contexts[_tag1788 >> 1]);
                }
            } else {
                var _read = _m_UseContext_read(input);
                if (!input.merging or true) {
                    _f1786.append(_read);
                }
            }
        }
    }
    var _f1807 = Array<(Loc, ulong, Loc)>();
    var _tag1808 = input.unsigned();
    if (_tag1808 == 1) {
        input.unsigned();
        for (var _i1796 in 0..base.literal_args.count) {
            _f1807.append(base.literal_args[_i1796]);
        }
        var _more1810 = input.count();
        for (var _ in 0.._more1810) {
            var _t1811 = input.loc();
            var _t1812 = input.unsigned();
            var _t1813 = input.loc();
            _f1807.append((_t1811, _t1812, _t1813));
        }
    } else {
        var _v1814 = Array<(Loc, ulong, Loc)>();
        var _n1815 = input.count();
        for (var _ in 0.._n1815) {
            var _t1816 = input.loc();
            var _t1817 = input.unsigned();
            var _t1818 = input.loc();
            _v1814.append((_t1816, _t1817, _t1818));
        }
        _f1807 = _v1814;
    }
    var _f1836 = Array<TypeAliasDef>();
    var _mode1839 = input.unsigned();
    if (_mode1839 == 2) {
        var _changed1825 = HashMap<ulong, TypeAliasDef>();
        ulong _bi1840 = 0;
        var _n1837 = input.count();
        for (var _ in 0.._n1837) {
            var _at1841 = input.unsigned();
            while (_f1836.count < _at1841 or (input.merging and _bi1840 < base.constrained_aliases.count)) {
                var _c = _changed1825.try_get(_bi1840);
                _f1836.append(_c.is_value() ? _c.value() : base.constrained_aliases[_bi1840]);
                _bi1840 += 1;
            }
            _f1836.append(_m_TypeAliasDef_read(input));
        }
        while (_bi1840 < base.constrained_aliases.count) {
            var _c = _changed1825.try_get(_bi1840);
            _f1836.append(_c.is_value() ? _c.value() : base.constrained_aliases[_bi1840]);
            _bi1840 += 1;
        }
    } else if (_mode1839 == 3) {
        var _n1837 = input.count();
        for (var _ in 0.._n1837) {
            _f1836.append(_m_TypeAliasDef_read(input));
        }
    } else {
        var _n1837 = input.count();
        if (input.merging) {
            input.error = "constrained_aliases" + " written by place";
        }
        for (var _ in 0.._n1837) {
            var _tag1838 = input.unsigned();
            if (_tag1838 & 1 == 1) {
                if (!input.merging) {
                    _f1836.append(base.constrained_aliases[_tag1838 >> 1]);
                }
            } else {
                var _read = _m_TypeAliasDef_read(input);
                if (!input.merging or true) {
                    _f1836.append(_read);
                }
            }
        }
    }
    var _f1855 = Array<TraitType>();
    var _mode1858 = input.unsigned();
    if (_mode1858 == 2) {
        var _changed1844 = HashMap<ulong, TraitType>();
        ulong _bi1859 = 0;
        var _n1856 = input.count();
        for (var _ in 0.._n1856) {
            var _at1860 = input.unsigned();
            while (_f1855.count < _at1860 or (input.merging and _bi1859 < base.trait_types.count)) {
                var _c = _changed1844.try_get(_bi1859);
                _f1855.append(_c.is_value() ? _c.value() : base.trait_types[_bi1859]);
                _bi1859 += 1;
            }
            _f1855.append(_m_TraitType_read(input));
        }
        while (_bi1859 < base.trait_types.count) {
            var _c = _changed1844.try_get(_bi1859);
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
    var _f2241 = Array<StructDef>();
    var _mode2244 = input.unsigned();
    if (_mode2244 == 2) {
        var _patched2247 = HashMap<ulong, StructDef>();
        var _n2242 = input.count();
        for (var _ in 0.._n2242) {
            var _name = input.text();
            var _slot = input.unsigned();
            if (input.merging) {
                _slot = struct_named(base.templates.structs, _name);
            }
            if (_slot >= base.templates.structs.count) {
                input.error = $"no struct {_name} to patch";
                break;
            }
            _patched2247[_slot] = _patch_t_read(input, base.templates.structs[_slot]);
        }
        ulong _bi2245 = 0;
        var _added = input.count();
        for (var _ in 0.._added) {
            var _at2246 = input.unsigned();
            while (_f2241.count < _at2246 or (input.merging and _bi2245 < base.templates.structs.count)) {
                var _p = _patched2247.try_get(_bi2245);
                _f2241.append(_p.is_value() ? _p.value() : base.templates.structs[_bi2245]);
                _bi2245 += 1;
            }
            _f2241.append(_m_StructDef_read(input));
        }
        while (_bi2245 < base.templates.structs.count) {
            var _p = _patched2247.try_get(_bi2245);
            _f2241.append(_p.is_value() ? _p.value() : base.templates.structs[_bi2245]);
            _bi2245 += 1;
        }
    } else {
        if (input.merging) {
            input.error = "structs written by place";
        }
        var _n2242 = input.count();
        for (var _ in 0.._n2242) {
            var _tag2243 = input.unsigned();
            if (_tag2243 & 1 == 1) {
                _f2241.append(
                    base.templates.structs[(_tag2243 >> 1) < base.templates.structs.count ? _tag2243 >> 1 : 0]
                );
            } else if (_tag2243 == 2) {
                var _was = base.templates.structs[input.unsigned()];
                _f2241.append(_patch_t_read(input, _was));
            } else {
                _f2241.append(_m_StructDef_read(input));
            }
        }
    }
    var _f2261 = Array<FunctionDef>();
    var _mode2264 = input.unsigned();
    if (_mode2264 == 2) {
        var _changed2250 = HashMap<ulong, FunctionDef>();
        var _nc2252 = input.count();
        for (var _ in 0.._nc2252) {
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
                _changed2250[_slot] = _el;
            } else {
                input.error = $"no {_name} to change";
            }
        }
        ulong _bi2265 = 0;
        var _n2262 = input.count();
        for (var _ in 0.._n2262) {
            var _at2266 = input.unsigned();
            while (_f2261.count < _at2266 or (input.merging and _bi2265 < base.templates.functions.count)) {
                var _c = _changed2250.try_get(_bi2265);
                _f2261.append(_c.is_value() ? _c.value() : base.templates.functions[_bi2265]);
                _bi2265 += 1;
            }
            _f2261.append(_m_FunctionDef_read(input));
        }
        while (_bi2265 < base.templates.functions.count) {
            var _c = _changed2250.try_get(_bi2265);
            _f2261.append(_c.is_value() ? _c.value() : base.templates.functions[_bi2265]);
            _bi2265 += 1;
        }
    } else if (_mode2264 == 3) {
        var _n2262 = input.count();
        for (var _ in 0.._n2262) {
            _f2261.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2262 = input.count();
        if (input.merging) {
            input.error = "tf" + " written by place";
        }
        for (var _ in 0.._n2262) {
            var _tag2263 = input.unsigned();
            if (_tag2263 & 1 == 1) {
                if (!input.merging) {
                    _f2261.append(base.templates.functions[_tag2263 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2261.append(_read);
                }
            }
        }
    }
    var _f2268 = Templates(_frozen, _f2241, _f2261);
    var _f2269 = DeltaBase.read_checked(input, base.checked);
    var _f2289 = HashMap<String, SpecRequest>();
    var _tag2290 = input.unsigned();
    if (_tag2290 == 1) {
        for (var (_bk2291, _bv) in base.spec_requests) {
            _f2289[_bk2291] = _bv;
        }
        var _v2292 = HashMap<String, SpecRequest>();
        var _n2293 = input.count();
        for (var _ in 0.._n2293) {
            var _k2294 = input.text();
            _v2292[_k2294] = _m_SpecRequest_read(input);
        }
        for (var (_bk2291, _av) in _v2292) {
            _f2289[_bk2291] = _av;
        }
    } else {
        var _v2295 = HashMap<String, SpecRequest>();
        var _n2296 = input.count();
        for (var _ in 0.._n2296) {
            var _k2297 = input.text();
            _v2295[_k2297] = _m_SpecRequest_read(input);
        }
        _f2289 = _v2295;
    }
    var _f2298 = input.flag();
    var _f2310 = Array<(Loc, String)>();
    var _tag2311 = input.unsigned();
    if (_tag2311 == 1) {
        input.unsigned();
        for (var _i2302 in 0..base.summaries_to_record.count) {
            _f2310.append(base.summaries_to_record[_i2302]);
        }
        var _more2313 = input.count();
        for (var _ in 0.._more2313) {
            var _t2314 = input.loc();
            var _t2315 = input.text();
            _f2310.append((_t2314, _t2315));
        }
    } else {
        var _v2316 = Array<(Loc, String)>();
        var _n2317 = input.count();
        for (var _ in 0.._n2317) {
            var _t2318 = input.loc();
            var _t2319 = input.text();
            _v2316.append((_t2318, _t2319));
        }
        _f2310 = _v2316;
    }
    var _f2350 = HashMap<String, Array<bool>>();
    var _tag2351 = input.unsigned();
    if (_tag2351 == 1) {
        for (var (_bk2352, _bv) in base.caller_copies) {
            _f2350[_bk2352] = _bv;
        }
        var _v2353 = HashMap<String, Array<bool>>();
        var _n2354 = input.count();
        for (var _ in 0.._n2354) {
            var _k2355 = input.text();
            var _v2356 = Array<bool>();
            var _n2357 = input.count();
            for (var _ in 0.._n2357) {
                _v2356.append(input.flag());
            }
            _v2353[_k2355] = _v2356;
        }
        for (var (_bk2352, _av) in _v2353) {
            _f2350[_bk2352] = _av;
        }
    } else {
        var _v2358 = HashMap<String, Array<bool>>();
        var _n2359 = input.count();
        for (var _ in 0.._n2359) {
            var _k2360 = input.text();
            var _v2361 = Array<bool>();
            var _n2362 = input.count();
            for (var _ in 0.._n2362) {
                _v2361.append(input.flag());
            }
            _v2358[_k2360] = _v2361;
        }
        _f2350 = _v2358;
    }
    var _f2364 = input.flag();
    return Module(
        _f1496,
        _f1529,
        _f1549,
        _f1568,
        _f1587,
        _f1606,
        _f1625,
        _f1644,
        _f1663,
        _f1682,
        _f1701,
        _f1713,
        _f1729,
        _f1748,
        _f1767,
        _f1786,
        _f1807,
        _f1836,
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
        _f2268,
        _f2269,
        _f2289,
        _f2298,
        _f2310,
        _f2350,
        _f2364
    );
}

_m_Module_index(value: Module, base: DeltaBase) {
    ulong _j1502 = 0;
    for (var _item1484 in value.imports) {
        var scratch = base.scratch();
        _a_Import_write(scratch, _item1484);
        base.add("imports", scratch, _j1502);
        _j1502 += 1;
    }
    if (base.verifying) {
        ulong _j1536 = 0;
        for (var _item1503 in value.structs) {
            var scratch = base.scratch();
            _m_StructDef_write(scratch, _item1503);
            base.add("s", scratch, _j1536);
            base.name("s", _item1503.name, _j1536);
            _patch_s_index(_item1503, base, _j1536);
            _j1536 += 1;
        }
    }
    base.ref_structs = value.structs.clone();
    base.ref_struct_parts = Array<StructDef>();
    for (var _item1503 in value.structs) {
        base.ref_struct_parts.append(_m_StructDef_shallow(_item1503));
    }
    ulong _j1555 = 0;
    for (var _item1537 in value.traits) {
        var scratch = base.scratch();
        _m_TraitDef_write(scratch, _item1537);
        base.add("traits", scratch, _j1555);
        _j1555 += 1;
    }
    ulong _j1574 = 0;
    for (var _item1556 in value.extensions) {
        var scratch = base.scratch();
        _m_ExtensionDef_write(scratch, _item1556);
        base.add("extensions", scratch, _j1574);
        _j1574 += 1;
    }
    if (base.verifying) {
        ulong _j1593 = 0;
        for (var _item1575 in value.functions) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item1575);
            base.add("functions", scratch, _j1593);
            base.name("functions", _item1575.name, _j1593);
            _j1593 += 1;
        }
    }
    base.ref_functions = value.functions.clone();
    ulong _j1612 = 0;
    for (var _item1594 in value.externs) {
        var scratch = base.scratch();
        _m_ExternDef_write(scratch, _item1594);
        base.add("externs", scratch, _j1612);
        _j1612 += 1;
    }
    ulong _j1631 = 0;
    for (var _item1613 in value.globals) {
        var scratch = base.scratch();
        _m_VariableDef_write(scratch, _item1613);
        base.add("globals", scratch, _j1631);
        _j1631 += 1;
    }
    ulong _j1650 = 0;
    for (var _item1632 in value.static_blocks) {
        var scratch = base.scratch();
        _m_ModuleStaticBlock_write(scratch, _item1632);
        base.add("static_blocks", scratch, _j1650);
        _j1650 += 1;
    }
    ulong _j1669 = 0;
    for (var _item1651 in value.enums) {
        var scratch = base.scratch();
        _m_EnumDef_write(scratch, _item1651);
        base.add("enums", scratch, _j1669);
        _j1669 += 1;
    }
    ulong _j1688 = 0;
    for (var _item1670 in value.struct_specs) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item1670);
        base.add("struct_specs", scratch, _j1688);
        _j1688 += 1;
    }
    ulong _j1707 = 0;
    for (var _item1689 in value.func_specs) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item1689);
        base.add("func_specs", scratch, _j1707);
        _j1707 += 1;
    }
    ulong _j1716 = 0;
    for (var _item1708 in value.type_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1708);
        base.add("type_aliases", scratch, _j1716);
        _j1716 += 1;
    }
    ulong _j1735 = 0;
    for (var _item1717 in value.withheld) {
        var scratch = base.scratch();
        _m_Withheld_write(scratch, _item1717);
        base.add("withheld", scratch, _j1735);
        _j1735 += 1;
    }
    ulong _j1754 = 0;
    for (var _item1736 in value.properties) {
        var scratch = base.scratch();
        _m_PropertyDef_write(scratch, _item1736);
        base.add("properties", scratch, _j1754);
        _j1754 += 1;
    }
    ulong _j1773 = 0;
    for (var _item1755 in value.type_uses) {
        var scratch = base.scratch();
        _m_TypeUse_write(scratch, _item1755);
        base.add("type_uses", scratch, _j1773);
        _j1773 += 1;
    }
    ulong _j1792 = 0;
    for (var _item1774 in value.use_contexts) {
        var scratch = base.scratch();
        _m_UseContext_write(scratch, _item1774);
        base.add("use_contexts", scratch, _j1792);
        _j1792 += 1;
    }
    var _xscratch1819 = base.scratch();
    for (var _xitem1820 in value.literal_args) {
        var (_t1821, _t1822, _t1823) = _xitem1820;
        _xscratch1819.loc(_t1821);
        _xscratch1819.unsigned(_t1822);
        _xscratch1819.loc(_t1823);
    }
    base.keep_list("literal_args", value.literal_args.count, _xscratch1819);
    ulong _j1842 = 0;
    for (var _item1824 in value.constrained_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1824);
        base.add("constrained_aliases", scratch, _j1842);
        _j1842 += 1;
    }
    ulong _j1861 = 0;
    for (var _item1843 in value.trait_types) {
        var scratch = base.scratch();
        _m_TraitType_write(scratch, _item1843);
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
    if (base.verifying) {
        ulong _j2248 = 0;
        for (var _item2231 in value.templates.structs) {
            var scratch = base.scratch();
            _m_StructDef_write(scratch, _item2231);
            base.add("t", scratch, _j2248);
            base.name("t", _item2231.name, _j2248);
            _patch_t_index(_item2231, base, _j2248);
            _j2248 += 1;
        }
    }
    base.ref_templates = value.templates.structs.clone();
    base.ref_template_parts = Array<StructDef>();
    for (var _item2231 in value.templates.structs) {
        base.ref_template_parts.append(_m_StructDef_shallow(_item2231));
    }
    if (base.verifying) {
        ulong _j2267 = 0;
        for (var _item2249 in value.templates.functions) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2249);
            base.add("tf", scratch, _j2267);
            base.name("tf", _item2249.name, _j2267);
            _j2267 += 1;
        }
    }
    base.ref_template_functions = value.templates.functions.clone();
    base.keep_checked(value.checked);
    for (var (_key2270, _) in value.spec_requests) {
        var _kscratch2271 = base.scratch();
        _kscratch2271.text(_key2270);
        var _vscratch2272 = base.scratch();
        _m_SpecRequest_write(_vscratch2272, value.spec_requests[_key2270]);
        base.keep_entry("spec_requests", _kscratch2271, _vscratch2272);
    }
    var _xscratch2320 = base.scratch();
    for (var _xitem2321 in value.summaries_to_record) {
        var (_t2322, _t2323) = _xitem2321;
        _xscratch2320.loc(_t2322);
        _xscratch2320.text(_t2323);
    }
    base.keep_list("summaries_to_record", value.summaries_to_record.count, _xscratch2320);
    for (var (_key2324, _) in value.caller_copies) {
        var _kscratch2325 = base.scratch();
        _kscratch2325.text(_key2324);
        var _vscratch2326 = base.scratch();
        _vscratch2326.unsigned(value.caller_copies[_key2324].count);
        for (var _item2363 in value.caller_copies[_key2324]) {
            _vscratch2326.flag(_item2363);
        }
        base.keep_entry("caller_copies", _kscratch2325, _vscratch2326);
    }
}

_m_Module_index_resumed(value: Module, base: DeltaBase) {
    ulong _j1716 = 0;
    for (var _item1708 in value.type_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1708);
        base.add("type_aliases", scratch, _j1716);
        _j1716 += 1;
    }
    for (var (_key2185, _) in value.recorded_summaries) {
        var _kscratch2186 = base.scratch();
        _kscratch2186.loc(_key2185);
        var _vscratch2187 = base.scratch();
        _vscratch2187.text(value.recorded_summaries[_key2185]);
        base.keep_entry("recorded_summaries", _kscratch2186, _vscratch2187);
    }
    var _xscratch2320 = base.scratch();
    for (var _xitem2321 in value.summaries_to_record) {
        var (_t2322, _t2323) = _xitem2321;
        _xscratch2320.loc(_t2322);
        _xscratch2320.text(_t2323);
    }
    base.keep_list("summaries_to_record", value.summaries_to_record.count, _xscratch2320);
}

_patch_s_write(out: RecordOut, value: StructDef, base: DeltaBase, slot: ulong) {
    out.text(value.name);
    _m_TypeName_write(out, value.ty);
    var _seq2372 = base.ref_struct_parts[slot].generic_params;
    ulong _bj2373 = 0;
    var _news2374 = Array<ulong>();
    for (var _i2375 in 0..value.generic_params.count) {
        if (_bj2373 < _seq2372.count and value.generic_params[_i2375] === _seq2372[_bj2373]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_GenericParam_write(scratch, value.generic_params[_i2375]);
                base.verify_same($"s.{slot}.generic_params", _bj2373, scratch);
            }
            _bj2373 += 1;
        } else if (_bj2373 < _seq2372.count
            and _same_m_GenericParam(value.generic_params[_i2375], _seq2372[_bj2373], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_GenericParam_write(scratch, value.generic_params[_i2375]);
                base.verify_same($"s.{slot}.generic_params", _bj2373, scratch);
            }
            _bj2373 += 1;
        } else {
            _news2374.append(_i2375);
        }
    }
    if (_bj2373 == _seq2372.count) {
        out.unsigned(2);
        out.unsigned(_news2374.count);
        for (var _i2375 in _news2374) {
            out.unsigned(_i2375);
            _m_GenericParam_write(out, value.generic_params[_i2375]);
        }
        base.count("s.*.generic_params" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.generic_params" + " whole", 0);
        out.unsigned(value.generic_params.count);
        for (var _i2375 in 0..value.generic_params.count) {
            _m_GenericParam_write(out, value.generic_params[_i2375]);
        }
    }
    var _seq2388 = base.ref_struct_parts[slot].field_members;
    ulong _bj2389 = 0;
    var _news2390 = Array<ulong>();
    for (var _i2391 in 0..value.field_members.count) {
        if (_bj2389 < _seq2388.count and value.field_members[_i2391] === _seq2388[_bj2389]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_VariableDef_write(scratch, value.field_members[_i2391]);
                base.verify_same($"s.{slot}.field_members", _bj2389, scratch);
            }
            _bj2389 += 1;
        } else if (_bj2389 < _seq2388.count
            and _same_m_VariableDef(value.field_members[_i2391], _seq2388[_bj2389], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_VariableDef_write(scratch, value.field_members[_i2391]);
                base.verify_same($"s.{slot}.field_members", _bj2389, scratch);
            }
            _bj2389 += 1;
        } else {
            _news2390.append(_i2391);
        }
    }
    if (_bj2389 == _seq2388.count) {
        out.unsigned(2);
        out.unsigned(_news2390.count);
        for (var _i2391 in _news2390) {
            out.unsigned(_i2391);
            _m_VariableDef_write(out, value.field_members[_i2391]);
        }
        base.count("s.*.field_members" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.field_members" + " whole", 0);
        out.unsigned(value.field_members.count);
        for (var _i2391 in 0..value.field_members.count) {
            _m_VariableDef_write(out, value.field_members[_i2391]);
        }
    }
    var _seq2404 = base.ref_struct_parts[slot].method_members;
    ulong _bj2405 = 0;
    var _news2406 = Array<ulong>();
    for (var _i2407 in 0..value.method_members.count) {
        if (_bj2405 < _seq2404.count and value.method_members[_i2407] === _seq2404[_bj2405]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.method_members[_i2407]);
                base.verify_same($"s.{slot}.method_members", _bj2405, scratch);
            }
            _bj2405 += 1;
        } else if (_bj2405 < _seq2404.count
            and _same_m_FunctionDef(value.method_members[_i2407], _seq2404[_bj2405], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.method_members[_i2407]);
                base.verify_same($"s.{slot}.method_members", _bj2405, scratch);
            }
            _bj2405 += 1;
        } else {
            _news2406.append(_i2407);
        }
    }
    if (_bj2405 == _seq2404.count) {
        out.unsigned(2);
        out.unsigned(_news2406.count);
        for (var _i2407 in _news2406) {
            out.unsigned(_i2407);
            _m_FunctionDef_write(out, value.method_members[_i2407]);
        }
        base.count("s.*.method_members" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.method_members" + " whole", 0);
        out.unsigned(value.method_members.count);
        for (var _i2407 in 0..value.method_members.count) {
            _m_FunctionDef_write(out, value.method_members[_i2407]);
        }
    }
    var _seq2420 = base.ref_struct_parts[slot].generic_methods;
    ulong _bj2421 = 0;
    var _news2422 = Array<ulong>();
    for (var _i2423 in 0..value.generic_methods.count) {
        if (_bj2421 < _seq2420.count and value.generic_methods[_i2423] === _seq2420[_bj2421]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.generic_methods[_i2423]);
                base.verify_same($"s.{slot}.generic_methods", _bj2421, scratch);
            }
            _bj2421 += 1;
        } else if (_bj2421 < _seq2420.count
            and _same_m_FunctionDef(value.generic_methods[_i2423], _seq2420[_bj2421], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.generic_methods[_i2423]);
                base.verify_same($"s.{slot}.generic_methods", _bj2421, scratch);
            }
            _bj2421 += 1;
        } else {
            _news2422.append(_i2423);
        }
    }
    if (_bj2421 == _seq2420.count) {
        out.unsigned(2);
        out.unsigned(_news2422.count);
        for (var _i2423 in _news2422) {
            out.unsigned(_i2423);
            _m_FunctionDef_write(out, value.generic_methods[_i2423]);
        }
        base.count("s.*.generic_methods" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.generic_methods" + " whole", 0);
        out.unsigned(value.generic_methods.count);
        for (var _i2423 in 0..value.generic_methods.count) {
            _m_FunctionDef_write(out, value.generic_methods[_i2423]);
        }
    }
    var _seq2436 = base.ref_struct_parts[slot].constructors;
    ulong _bj2437 = 0;
    var _news2438 = Array<ulong>();
    for (var _i2439 in 0..value.constructors.count) {
        if (_bj2437 < _seq2436.count and value.constructors[_i2439] === _seq2436[_bj2437]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.constructors[_i2439]);
                base.verify_same($"s.{slot}.constructors", _bj2437, scratch);
            }
            _bj2437 += 1;
        } else if (_bj2437 < _seq2436.count
            and _same_m_FunctionDef(value.constructors[_i2439], _seq2436[_bj2437], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.constructors[_i2439]);
                base.verify_same($"s.{slot}.constructors", _bj2437, scratch);
            }
            _bj2437 += 1;
        } else {
            _news2438.append(_i2439);
        }
    }
    if (_bj2437 == _seq2436.count) {
        out.unsigned(2);
        out.unsigned(_news2438.count);
        for (var _i2439 in _news2438) {
            out.unsigned(_i2439);
            _m_FunctionDef_write(out, value.constructors[_i2439]);
        }
        base.count("s.*.constructors" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.constructors" + " whole", 0);
        out.unsigned(value.constructors.count);
        for (var _i2439 in 0..value.constructors.count) {
            _m_FunctionDef_write(out, value.constructors[_i2439]);
        }
    }
    _m_FunctionDef_write(out, value.destructor);
    _m_FunctionDef_write(out, value.acquire);
    _m_FunctionDef_write(out, value.release);
    var _seq2455 = base.ref_struct_parts[slot].traits;
    ulong _bj2456 = 0;
    var _news2457 = Array<ulong>();
    for (var _i2458 in 0..value.traits.count) {
        if (_bj2456 < _seq2455.count and value.traits[_i2458] === _seq2455[_bj2456]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_TypeName_write(scratch, value.traits[_i2458]);
                base.verify_same($"s.{slot}.traits", _bj2456, scratch);
            }
            _bj2456 += 1;
        } else if (_bj2456 < _seq2455.count and _same_m_TypeName(value.traits[_i2458], _seq2455[_bj2456], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_TypeName_write(scratch, value.traits[_i2458]);
                base.verify_same($"s.{slot}.traits", _bj2456, scratch);
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
            _m_TypeName_write(out, value.traits[_i2458]);
        }
        base.count("s.*.traits" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.traits" + " whole", 0);
        out.unsigned(value.traits.count);
        for (var _i2458 in 0..value.traits.count) {
            _m_TypeName_write(out, value.traits[_i2458]);
        }
    }
    var _seq2471 = base.ref_struct_parts[slot].attributes;
    ulong _bj2472 = 0;
    var _news2473 = Array<ulong>();
    for (var _i2474 in 0..value.attributes.count) {
        if (_bj2472 < _seq2471.count and value.attributes[_i2474] === _seq2471[_bj2472]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _a_Attribute_write(scratch, value.attributes[_i2474]);
                base.verify_same($"s.{slot}.attributes", _bj2472, scratch);
            }
            _bj2472 += 1;
        } else if (_bj2472 < _seq2471.count and _same_a_Attribute(value.attributes[_i2474], _seq2471[_bj2472], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _a_Attribute_write(scratch, value.attributes[_i2474]);
                base.verify_same($"s.{slot}.attributes", _bj2472, scratch);
            }
            _bj2472 += 1;
        } else {
            _news2473.append(_i2474);
        }
    }
    if (_bj2472 == _seq2471.count) {
        out.unsigned(2);
        out.unsigned(_news2473.count);
        for (var _i2474 in _news2473) {
            out.unsigned(_i2474);
            _a_Attribute_write(out, value.attributes[_i2474]);
        }
        base.count("s.*.attributes" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.attributes" + " whole", 0);
        out.unsigned(value.attributes.count);
        for (var _i2474 in 0..value.attributes.count) {
            _a_Attribute_write(out, value.attributes[_i2474]);
        }
    }
    out.loc(value.loc);
    if (value.enum_cases.is_value()) {
        out.unsigned(1);
        out.unsigned(value.enum_cases.value().count);
        for (var _item2483 in value.enum_cases.value()) {
            _m_EnumCaseDef_write(out, _item2483);
        }
    } else {
        out.unsigned(0);
    }
}

_patch_s_read(input: RecordIn, was: StructDef): StructDef {
    var _f2365 = input.text();
    var _f2366 = _m_TypeName_read(input);
    var _f2376 = Array<GenericParam>();
    var _mode2379 = input.unsigned();
    if (_mode2379 == 2) {
        var _changed2368 = HashMap<ulong, GenericParam>();
        ulong _bi2380 = 0;
        var _n2377 = input.count();
        for (var _ in 0.._n2377) {
            var _at2381 = input.unsigned();
            while (_f2376.count < _at2381 or (input.merging and _bi2380 < was.generic_params.count)) {
                var _c = _changed2368.try_get(_bi2380);
                _f2376.append(_c.is_value() ? _c.value() : was.generic_params[_bi2380]);
                _bi2380 += 1;
            }
            _f2376.append(_m_GenericParam_read(input));
        }
        while (_bi2380 < was.generic_params.count) {
            var _c = _changed2368.try_get(_bi2380);
            _f2376.append(_c.is_value() ? _c.value() : was.generic_params[_bi2380]);
            _bi2380 += 1;
        }
    } else if (_mode2379 == 3) {
        var _n2377 = input.count();
        for (var _ in 0.._n2377) {
            _f2376.append(_m_GenericParam_read(input));
        }
    } else {
        var _n2377 = input.count();
        if (input.merging) {
            input.error = "s.*.generic_params" + " written by place";
        }
        for (var _ in 0.._n2377) {
            var _tag2378 = input.unsigned();
            if (_tag2378 & 1 == 1) {
                if (!input.merging) {
                    _f2376.append(was.generic_params[_tag2378 >> 1]);
                }
            } else {
                var _read = _m_GenericParam_read(input);
                if (!input.merging or true) {
                    _f2376.append(_read);
                }
            }
        }
    }
    var _f2392 = Array<VariableDef>();
    var _mode2395 = input.unsigned();
    if (_mode2395 == 2) {
        var _changed2384 = HashMap<ulong, VariableDef>();
        ulong _bi2396 = 0;
        var _n2393 = input.count();
        for (var _ in 0.._n2393) {
            var _at2397 = input.unsigned();
            while (_f2392.count < _at2397 or (input.merging and _bi2396 < was.field_members.count)) {
                var _c = _changed2384.try_get(_bi2396);
                _f2392.append(_c.is_value() ? _c.value() : was.field_members[_bi2396]);
                _bi2396 += 1;
            }
            _f2392.append(_m_VariableDef_read(input));
        }
        while (_bi2396 < was.field_members.count) {
            var _c = _changed2384.try_get(_bi2396);
            _f2392.append(_c.is_value() ? _c.value() : was.field_members[_bi2396]);
            _bi2396 += 1;
        }
    } else if (_mode2395 == 3) {
        var _n2393 = input.count();
        for (var _ in 0.._n2393) {
            _f2392.append(_m_VariableDef_read(input));
        }
    } else {
        var _n2393 = input.count();
        if (input.merging) {
            input.error = "s.*.field_members" + " written by place";
        }
        for (var _ in 0.._n2393) {
            var _tag2394 = input.unsigned();
            if (_tag2394 & 1 == 1) {
                if (!input.merging) {
                    _f2392.append(was.field_members[_tag2394 >> 1]);
                }
            } else {
                var _read = _m_VariableDef_read(input);
                if (!input.merging or true) {
                    _f2392.append(_read);
                }
            }
        }
    }
    var _f2408 = Array<FunctionDef>();
    var _mode2411 = input.unsigned();
    if (_mode2411 == 2) {
        var _changed2400 = HashMap<ulong, FunctionDef>();
        ulong _bi2412 = 0;
        var _n2409 = input.count();
        for (var _ in 0.._n2409) {
            var _at2413 = input.unsigned();
            while (_f2408.count < _at2413 or (input.merging and _bi2412 < was.method_members.count)) {
                var _c = _changed2400.try_get(_bi2412);
                _f2408.append(_c.is_value() ? _c.value() : was.method_members[_bi2412]);
                _bi2412 += 1;
            }
            _f2408.append(_m_FunctionDef_read(input));
        }
        while (_bi2412 < was.method_members.count) {
            var _c = _changed2400.try_get(_bi2412);
            _f2408.append(_c.is_value() ? _c.value() : was.method_members[_bi2412]);
            _bi2412 += 1;
        }
    } else if (_mode2411 == 3) {
        var _n2409 = input.count();
        for (var _ in 0.._n2409) {
            _f2408.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2409 = input.count();
        if (input.merging) {
            input.error = "s.*.method_members" + " written by place";
        }
        for (var _ in 0.._n2409) {
            var _tag2410 = input.unsigned();
            if (_tag2410 & 1 == 1) {
                if (!input.merging) {
                    _f2408.append(was.method_members[_tag2410 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2408.append(_read);
                }
            }
        }
    }
    var _f2424 = Array<FunctionDef>();
    var _mode2427 = input.unsigned();
    if (_mode2427 == 2) {
        var _changed2416 = HashMap<ulong, FunctionDef>();
        ulong _bi2428 = 0;
        var _n2425 = input.count();
        for (var _ in 0.._n2425) {
            var _at2429 = input.unsigned();
            while (_f2424.count < _at2429 or (input.merging and _bi2428 < was.generic_methods.count)) {
                var _c = _changed2416.try_get(_bi2428);
                _f2424.append(_c.is_value() ? _c.value() : was.generic_methods[_bi2428]);
                _bi2428 += 1;
            }
            _f2424.append(_m_FunctionDef_read(input));
        }
        while (_bi2428 < was.generic_methods.count) {
            var _c = _changed2416.try_get(_bi2428);
            _f2424.append(_c.is_value() ? _c.value() : was.generic_methods[_bi2428]);
            _bi2428 += 1;
        }
    } else if (_mode2427 == 3) {
        var _n2425 = input.count();
        for (var _ in 0.._n2425) {
            _f2424.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2425 = input.count();
        if (input.merging) {
            input.error = "s.*.generic_methods" + " written by place";
        }
        for (var _ in 0.._n2425) {
            var _tag2426 = input.unsigned();
            if (_tag2426 & 1 == 1) {
                if (!input.merging) {
                    _f2424.append(was.generic_methods[_tag2426 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2424.append(_read);
                }
            }
        }
    }
    var _f2440 = Array<FunctionDef>();
    var _mode2443 = input.unsigned();
    if (_mode2443 == 2) {
        var _changed2432 = HashMap<ulong, FunctionDef>();
        ulong _bi2444 = 0;
        var _n2441 = input.count();
        for (var _ in 0.._n2441) {
            var _at2445 = input.unsigned();
            while (_f2440.count < _at2445 or (input.merging and _bi2444 < was.constructors.count)) {
                var _c = _changed2432.try_get(_bi2444);
                _f2440.append(_c.is_value() ? _c.value() : was.constructors[_bi2444]);
                _bi2444 += 1;
            }
            _f2440.append(_m_FunctionDef_read(input));
        }
        while (_bi2444 < was.constructors.count) {
            var _c = _changed2432.try_get(_bi2444);
            _f2440.append(_c.is_value() ? _c.value() : was.constructors[_bi2444]);
            _bi2444 += 1;
        }
    } else if (_mode2443 == 3) {
        var _n2441 = input.count();
        for (var _ in 0.._n2441) {
            _f2440.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2441 = input.count();
        if (input.merging) {
            input.error = "s.*.constructors" + " written by place";
        }
        for (var _ in 0.._n2441) {
            var _tag2442 = input.unsigned();
            if (_tag2442 & 1 == 1) {
                if (!input.merging) {
                    _f2440.append(was.constructors[_tag2442 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2440.append(_read);
                }
            }
        }
    }
    var _f2447 = _m_FunctionDef_read(input);
    var _f2448 = _m_FunctionDef_read(input);
    var _f2449 = _m_FunctionDef_read(input);
    var _f2459 = Array<TypeName>();
    var _mode2462 = input.unsigned();
    if (_mode2462 == 2) {
        var _changed2451 = HashMap<ulong, TypeName>();
        ulong _bi2463 = 0;
        var _n2460 = input.count();
        for (var _ in 0.._n2460) {
            var _at2464 = input.unsigned();
            while (_f2459.count < _at2464 or (input.merging and _bi2463 < was.traits.count)) {
                var _c = _changed2451.try_get(_bi2463);
                _f2459.append(_c.is_value() ? _c.value() : was.traits[_bi2463]);
                _bi2463 += 1;
            }
            _f2459.append(_m_TypeName_read(input));
        }
        while (_bi2463 < was.traits.count) {
            var _c = _changed2451.try_get(_bi2463);
            _f2459.append(_c.is_value() ? _c.value() : was.traits[_bi2463]);
            _bi2463 += 1;
        }
    } else if (_mode2462 == 3) {
        var _n2460 = input.count();
        for (var _ in 0.._n2460) {
            _f2459.append(_m_TypeName_read(input));
        }
    } else {
        var _n2460 = input.count();
        if (input.merging) {
            input.error = "s.*.traits" + " written by place";
        }
        for (var _ in 0.._n2460) {
            var _tag2461 = input.unsigned();
            if (_tag2461 & 1 == 1) {
                if (!input.merging) {
                    _f2459.append(was.traits[_tag2461 >> 1]);
                }
            } else {
                var _read = _m_TypeName_read(input);
                if (!input.merging or true) {
                    _f2459.append(_read);
                }
            }
        }
    }
    var _f2475 = Array<ast.Attribute>();
    var _mode2478 = input.unsigned();
    if (_mode2478 == 2) {
        var _changed2467 = HashMap<ulong, ast.Attribute>();
        ulong _bi2479 = 0;
        var _n2476 = input.count();
        for (var _ in 0.._n2476) {
            var _at2480 = input.unsigned();
            while (_f2475.count < _at2480 or (input.merging and _bi2479 < was.attributes.count)) {
                var _c = _changed2467.try_get(_bi2479);
                _f2475.append(_c.is_value() ? _c.value() : was.attributes[_bi2479]);
                _bi2479 += 1;
            }
            _f2475.append(_a_Attribute_read(input));
        }
        while (_bi2479 < was.attributes.count) {
            var _c = _changed2467.try_get(_bi2479);
            _f2475.append(_c.is_value() ? _c.value() : was.attributes[_bi2479]);
            _bi2479 += 1;
        }
    } else if (_mode2478 == 3) {
        var _n2476 = input.count();
        for (var _ in 0.._n2476) {
            _f2475.append(_a_Attribute_read(input));
        }
    } else {
        var _n2476 = input.count();
        if (input.merging) {
            input.error = "s.*.attributes" + " written by place";
        }
        for (var _ in 0.._n2476) {
            var _tag2477 = input.unsigned();
            if (_tag2477 & 1 == 1) {
                if (!input.merging) {
                    _f2475.append(was.attributes[_tag2477 >> 1]);
                }
            } else {
                var _read = _a_Attribute_read(input);
                if (!input.merging or true) {
                    _f2475.append(_read);
                }
            }
        }
    }
    var _f2482 = input.loc();
    var _o2484 = Optional<Array<EnumCaseDef>>.Empty;
    if (input.unsigned() == 1) {
        var _v2485 = Array<EnumCaseDef>();
        var _n2486 = input.count();
        for (var _ in 0.._n2486) {
            _v2485.append(_m_EnumCaseDef_read(input));
        }
        _o2484 = Optional<Array<EnumCaseDef>>.Value(_v2485);
    }
    var _f2487 = _o2484;
    return StructDef(
        _f2365, _f2366, _f2376, _f2392, _f2408, _f2424, _f2440, _f2447, _f2448, _f2449, _f2459, _f2475, _f2482, _f2487
    );
}

_patch_s_index(value: StructDef, base: DeltaBase, slot: ulong) {
    if (base.verifying) {
        ulong _j2382 = 0;
        for (var _item2367 in value.generic_params) {
            var scratch = base.scratch();
            _m_GenericParam_write(scratch, _item2367);
            base.add($"s.{slot}.generic_params", scratch, _j2382);
            _j2382 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2398 = 0;
        for (var _item2383 in value.field_members) {
            var scratch = base.scratch();
            _m_VariableDef_write(scratch, _item2383);
            base.add($"s.{slot}.field_members", scratch, _j2398);
            _j2398 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2414 = 0;
        for (var _item2399 in value.method_members) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2399);
            base.add($"s.{slot}.method_members", scratch, _j2414);
            _j2414 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2430 = 0;
        for (var _item2415 in value.generic_methods) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2415);
            base.add($"s.{slot}.generic_methods", scratch, _j2430);
            _j2430 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2446 = 0;
        for (var _item2431 in value.constructors) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2431);
            base.add($"s.{slot}.constructors", scratch, _j2446);
            _j2446 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2465 = 0;
        for (var _item2450 in value.traits) {
            var scratch = base.scratch();
            _m_TypeName_write(scratch, _item2450);
            base.add($"s.{slot}.traits", scratch, _j2465);
            _j2465 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2481 = 0;
        for (var _item2466 in value.attributes) {
            var scratch = base.scratch();
            _a_Attribute_write(scratch, _item2466);
            base.add($"s.{slot}.attributes", scratch, _j2481);
            _j2481 += 1;
        }
    }
}

_patch_t_write(out: RecordOut, value: StructDef, base: DeltaBase, slot: ulong) {
    out.text(value.name);
    _m_TypeName_write(out, value.ty);
    var _seq2495 = base.ref_template_parts[slot].generic_params;
    ulong _bj2496 = 0;
    var _news2497 = Array<ulong>();
    for (var _i2498 in 0..value.generic_params.count) {
        if (_bj2496 < _seq2495.count and value.generic_params[_i2498] === _seq2495[_bj2496]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_GenericParam_write(scratch, value.generic_params[_i2498]);
                base.verify_same($"t.{slot}.generic_params", _bj2496, scratch);
            }
            _bj2496 += 1;
        } else if (_bj2496 < _seq2495.count
            and _same_m_GenericParam(value.generic_params[_i2498], _seq2495[_bj2496], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_GenericParam_write(scratch, value.generic_params[_i2498]);
                base.verify_same($"t.{slot}.generic_params", _bj2496, scratch);
            }
            _bj2496 += 1;
        } else {
            _news2497.append(_i2498);
        }
    }
    if (_bj2496 == _seq2495.count) {
        out.unsigned(2);
        out.unsigned(_news2497.count);
        for (var _i2498 in _news2497) {
            out.unsigned(_i2498);
            _m_GenericParam_write(out, value.generic_params[_i2498]);
        }
        base.count("t.*.generic_params" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.generic_params" + " whole", 0);
        out.unsigned(value.generic_params.count);
        for (var _i2498 in 0..value.generic_params.count) {
            _m_GenericParam_write(out, value.generic_params[_i2498]);
        }
    }
    var _seq2511 = base.ref_template_parts[slot].field_members;
    ulong _bj2512 = 0;
    var _news2513 = Array<ulong>();
    for (var _i2514 in 0..value.field_members.count) {
        if (_bj2512 < _seq2511.count and value.field_members[_i2514] === _seq2511[_bj2512]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_VariableDef_write(scratch, value.field_members[_i2514]);
                base.verify_same($"t.{slot}.field_members", _bj2512, scratch);
            }
            _bj2512 += 1;
        } else if (_bj2512 < _seq2511.count
            and _same_m_VariableDef(value.field_members[_i2514], _seq2511[_bj2512], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_VariableDef_write(scratch, value.field_members[_i2514]);
                base.verify_same($"t.{slot}.field_members", _bj2512, scratch);
            }
            _bj2512 += 1;
        } else {
            _news2513.append(_i2514);
        }
    }
    if (_bj2512 == _seq2511.count) {
        out.unsigned(2);
        out.unsigned(_news2513.count);
        for (var _i2514 in _news2513) {
            out.unsigned(_i2514);
            _m_VariableDef_write(out, value.field_members[_i2514]);
        }
        base.count("t.*.field_members" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.field_members" + " whole", 0);
        out.unsigned(value.field_members.count);
        for (var _i2514 in 0..value.field_members.count) {
            _m_VariableDef_write(out, value.field_members[_i2514]);
        }
    }
    var _seq2527 = base.ref_template_parts[slot].method_members;
    ulong _bj2528 = 0;
    var _news2529 = Array<ulong>();
    for (var _i2530 in 0..value.method_members.count) {
        if (_bj2528 < _seq2527.count and value.method_members[_i2530] === _seq2527[_bj2528]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.method_members[_i2530]);
                base.verify_same($"t.{slot}.method_members", _bj2528, scratch);
            }
            _bj2528 += 1;
        } else if (_bj2528 < _seq2527.count
            and _same_m_FunctionDef(value.method_members[_i2530], _seq2527[_bj2528], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.method_members[_i2530]);
                base.verify_same($"t.{slot}.method_members", _bj2528, scratch);
            }
            _bj2528 += 1;
        } else {
            _news2529.append(_i2530);
        }
    }
    if (_bj2528 == _seq2527.count) {
        out.unsigned(2);
        out.unsigned(_news2529.count);
        for (var _i2530 in _news2529) {
            out.unsigned(_i2530);
            _m_FunctionDef_write(out, value.method_members[_i2530]);
        }
        base.count("t.*.method_members" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.method_members" + " whole", 0);
        out.unsigned(value.method_members.count);
        for (var _i2530 in 0..value.method_members.count) {
            _m_FunctionDef_write(out, value.method_members[_i2530]);
        }
    }
    var _seq2543 = base.ref_template_parts[slot].generic_methods;
    ulong _bj2544 = 0;
    var _news2545 = Array<ulong>();
    for (var _i2546 in 0..value.generic_methods.count) {
        if (_bj2544 < _seq2543.count and value.generic_methods[_i2546] === _seq2543[_bj2544]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.generic_methods[_i2546]);
                base.verify_same($"t.{slot}.generic_methods", _bj2544, scratch);
            }
            _bj2544 += 1;
        } else if (_bj2544 < _seq2543.count
            and _same_m_FunctionDef(value.generic_methods[_i2546], _seq2543[_bj2544], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.generic_methods[_i2546]);
                base.verify_same($"t.{slot}.generic_methods", _bj2544, scratch);
            }
            _bj2544 += 1;
        } else {
            _news2545.append(_i2546);
        }
    }
    if (_bj2544 == _seq2543.count) {
        out.unsigned(2);
        out.unsigned(_news2545.count);
        for (var _i2546 in _news2545) {
            out.unsigned(_i2546);
            _m_FunctionDef_write(out, value.generic_methods[_i2546]);
        }
        base.count("t.*.generic_methods" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.generic_methods" + " whole", 0);
        out.unsigned(value.generic_methods.count);
        for (var _i2546 in 0..value.generic_methods.count) {
            _m_FunctionDef_write(out, value.generic_methods[_i2546]);
        }
    }
    var _seq2559 = base.ref_template_parts[slot].constructors;
    ulong _bj2560 = 0;
    var _news2561 = Array<ulong>();
    for (var _i2562 in 0..value.constructors.count) {
        if (_bj2560 < _seq2559.count and value.constructors[_i2562] === _seq2559[_bj2560]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.constructors[_i2562]);
                base.verify_same($"t.{slot}.constructors", _bj2560, scratch);
            }
            _bj2560 += 1;
        } else if (_bj2560 < _seq2559.count
            and _same_m_FunctionDef(value.constructors[_i2562], _seq2559[_bj2560], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.constructors[_i2562]);
                base.verify_same($"t.{slot}.constructors", _bj2560, scratch);
            }
            _bj2560 += 1;
        } else {
            _news2561.append(_i2562);
        }
    }
    if (_bj2560 == _seq2559.count) {
        out.unsigned(2);
        out.unsigned(_news2561.count);
        for (var _i2562 in _news2561) {
            out.unsigned(_i2562);
            _m_FunctionDef_write(out, value.constructors[_i2562]);
        }
        base.count("t.*.constructors" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.constructors" + " whole", 0);
        out.unsigned(value.constructors.count);
        for (var _i2562 in 0..value.constructors.count) {
            _m_FunctionDef_write(out, value.constructors[_i2562]);
        }
    }
    _m_FunctionDef_write(out, value.destructor);
    _m_FunctionDef_write(out, value.acquire);
    _m_FunctionDef_write(out, value.release);
    var _seq2578 = base.ref_template_parts[slot].traits;
    ulong _bj2579 = 0;
    var _news2580 = Array<ulong>();
    for (var _i2581 in 0..value.traits.count) {
        if (_bj2579 < _seq2578.count and value.traits[_i2581] === _seq2578[_bj2579]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_TypeName_write(scratch, value.traits[_i2581]);
                base.verify_same($"t.{slot}.traits", _bj2579, scratch);
            }
            _bj2579 += 1;
        } else if (_bj2579 < _seq2578.count and _same_m_TypeName(value.traits[_i2581], _seq2578[_bj2579], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_TypeName_write(scratch, value.traits[_i2581]);
                base.verify_same($"t.{slot}.traits", _bj2579, scratch);
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
            _m_TypeName_write(out, value.traits[_i2581]);
        }
        base.count("t.*.traits" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.traits" + " whole", 0);
        out.unsigned(value.traits.count);
        for (var _i2581 in 0..value.traits.count) {
            _m_TypeName_write(out, value.traits[_i2581]);
        }
    }
    var _seq2594 = base.ref_template_parts[slot].attributes;
    ulong _bj2595 = 0;
    var _news2596 = Array<ulong>();
    for (var _i2597 in 0..value.attributes.count) {
        if (_bj2595 < _seq2594.count and value.attributes[_i2597] === _seq2594[_bj2595]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _a_Attribute_write(scratch, value.attributes[_i2597]);
                base.verify_same($"t.{slot}.attributes", _bj2595, scratch);
            }
            _bj2595 += 1;
        } else if (_bj2595 < _seq2594.count and _same_a_Attribute(value.attributes[_i2597], _seq2594[_bj2595], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _a_Attribute_write(scratch, value.attributes[_i2597]);
                base.verify_same($"t.{slot}.attributes", _bj2595, scratch);
            }
            _bj2595 += 1;
        } else {
            _news2596.append(_i2597);
        }
    }
    if (_bj2595 == _seq2594.count) {
        out.unsigned(2);
        out.unsigned(_news2596.count);
        for (var _i2597 in _news2596) {
            out.unsigned(_i2597);
            _a_Attribute_write(out, value.attributes[_i2597]);
        }
        base.count("t.*.attributes" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.attributes" + " whole", 0);
        out.unsigned(value.attributes.count);
        for (var _i2597 in 0..value.attributes.count) {
            _a_Attribute_write(out, value.attributes[_i2597]);
        }
    }
    out.loc(value.loc);
    if (value.enum_cases.is_value()) {
        out.unsigned(1);
        out.unsigned(value.enum_cases.value().count);
        for (var _item2606 in value.enum_cases.value()) {
            _m_EnumCaseDef_write(out, _item2606);
        }
    } else {
        out.unsigned(0);
    }
}

_patch_t_read(input: RecordIn, was: StructDef): StructDef {
    var _f2488 = input.text();
    var _f2489 = _m_TypeName_read(input);
    var _f2499 = Array<GenericParam>();
    var _mode2502 = input.unsigned();
    if (_mode2502 == 2) {
        var _changed2491 = HashMap<ulong, GenericParam>();
        ulong _bi2503 = 0;
        var _n2500 = input.count();
        for (var _ in 0.._n2500) {
            var _at2504 = input.unsigned();
            while (_f2499.count < _at2504 or (input.merging and _bi2503 < was.generic_params.count)) {
                var _c = _changed2491.try_get(_bi2503);
                _f2499.append(_c.is_value() ? _c.value() : was.generic_params[_bi2503]);
                _bi2503 += 1;
            }
            _f2499.append(_m_GenericParam_read(input));
        }
        while (_bi2503 < was.generic_params.count) {
            var _c = _changed2491.try_get(_bi2503);
            _f2499.append(_c.is_value() ? _c.value() : was.generic_params[_bi2503]);
            _bi2503 += 1;
        }
    } else if (_mode2502 == 3) {
        var _n2500 = input.count();
        for (var _ in 0.._n2500) {
            _f2499.append(_m_GenericParam_read(input));
        }
    } else {
        var _n2500 = input.count();
        if (input.merging) {
            input.error = "t.*.generic_params" + " written by place";
        }
        for (var _ in 0.._n2500) {
            var _tag2501 = input.unsigned();
            if (_tag2501 & 1 == 1) {
                if (!input.merging) {
                    _f2499.append(was.generic_params[_tag2501 >> 1]);
                }
            } else {
                var _read = _m_GenericParam_read(input);
                if (!input.merging or true) {
                    _f2499.append(_read);
                }
            }
        }
    }
    var _f2515 = Array<VariableDef>();
    var _mode2518 = input.unsigned();
    if (_mode2518 == 2) {
        var _changed2507 = HashMap<ulong, VariableDef>();
        ulong _bi2519 = 0;
        var _n2516 = input.count();
        for (var _ in 0.._n2516) {
            var _at2520 = input.unsigned();
            while (_f2515.count < _at2520 or (input.merging and _bi2519 < was.field_members.count)) {
                var _c = _changed2507.try_get(_bi2519);
                _f2515.append(_c.is_value() ? _c.value() : was.field_members[_bi2519]);
                _bi2519 += 1;
            }
            _f2515.append(_m_VariableDef_read(input));
        }
        while (_bi2519 < was.field_members.count) {
            var _c = _changed2507.try_get(_bi2519);
            _f2515.append(_c.is_value() ? _c.value() : was.field_members[_bi2519]);
            _bi2519 += 1;
        }
    } else if (_mode2518 == 3) {
        var _n2516 = input.count();
        for (var _ in 0.._n2516) {
            _f2515.append(_m_VariableDef_read(input));
        }
    } else {
        var _n2516 = input.count();
        if (input.merging) {
            input.error = "t.*.field_members" + " written by place";
        }
        for (var _ in 0.._n2516) {
            var _tag2517 = input.unsigned();
            if (_tag2517 & 1 == 1) {
                if (!input.merging) {
                    _f2515.append(was.field_members[_tag2517 >> 1]);
                }
            } else {
                var _read = _m_VariableDef_read(input);
                if (!input.merging or true) {
                    _f2515.append(_read);
                }
            }
        }
    }
    var _f2531 = Array<FunctionDef>();
    var _mode2534 = input.unsigned();
    if (_mode2534 == 2) {
        var _changed2523 = HashMap<ulong, FunctionDef>();
        ulong _bi2535 = 0;
        var _n2532 = input.count();
        for (var _ in 0.._n2532) {
            var _at2536 = input.unsigned();
            while (_f2531.count < _at2536 or (input.merging and _bi2535 < was.method_members.count)) {
                var _c = _changed2523.try_get(_bi2535);
                _f2531.append(_c.is_value() ? _c.value() : was.method_members[_bi2535]);
                _bi2535 += 1;
            }
            _f2531.append(_m_FunctionDef_read(input));
        }
        while (_bi2535 < was.method_members.count) {
            var _c = _changed2523.try_get(_bi2535);
            _f2531.append(_c.is_value() ? _c.value() : was.method_members[_bi2535]);
            _bi2535 += 1;
        }
    } else if (_mode2534 == 3) {
        var _n2532 = input.count();
        for (var _ in 0.._n2532) {
            _f2531.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2532 = input.count();
        if (input.merging) {
            input.error = "t.*.method_members" + " written by place";
        }
        for (var _ in 0.._n2532) {
            var _tag2533 = input.unsigned();
            if (_tag2533 & 1 == 1) {
                if (!input.merging) {
                    _f2531.append(was.method_members[_tag2533 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2531.append(_read);
                }
            }
        }
    }
    var _f2547 = Array<FunctionDef>();
    var _mode2550 = input.unsigned();
    if (_mode2550 == 2) {
        var _changed2539 = HashMap<ulong, FunctionDef>();
        ulong _bi2551 = 0;
        var _n2548 = input.count();
        for (var _ in 0.._n2548) {
            var _at2552 = input.unsigned();
            while (_f2547.count < _at2552 or (input.merging and _bi2551 < was.generic_methods.count)) {
                var _c = _changed2539.try_get(_bi2551);
                _f2547.append(_c.is_value() ? _c.value() : was.generic_methods[_bi2551]);
                _bi2551 += 1;
            }
            _f2547.append(_m_FunctionDef_read(input));
        }
        while (_bi2551 < was.generic_methods.count) {
            var _c = _changed2539.try_get(_bi2551);
            _f2547.append(_c.is_value() ? _c.value() : was.generic_methods[_bi2551]);
            _bi2551 += 1;
        }
    } else if (_mode2550 == 3) {
        var _n2548 = input.count();
        for (var _ in 0.._n2548) {
            _f2547.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2548 = input.count();
        if (input.merging) {
            input.error = "t.*.generic_methods" + " written by place";
        }
        for (var _ in 0.._n2548) {
            var _tag2549 = input.unsigned();
            if (_tag2549 & 1 == 1) {
                if (!input.merging) {
                    _f2547.append(was.generic_methods[_tag2549 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2547.append(_read);
                }
            }
        }
    }
    var _f2563 = Array<FunctionDef>();
    var _mode2566 = input.unsigned();
    if (_mode2566 == 2) {
        var _changed2555 = HashMap<ulong, FunctionDef>();
        ulong _bi2567 = 0;
        var _n2564 = input.count();
        for (var _ in 0.._n2564) {
            var _at2568 = input.unsigned();
            while (_f2563.count < _at2568 or (input.merging and _bi2567 < was.constructors.count)) {
                var _c = _changed2555.try_get(_bi2567);
                _f2563.append(_c.is_value() ? _c.value() : was.constructors[_bi2567]);
                _bi2567 += 1;
            }
            _f2563.append(_m_FunctionDef_read(input));
        }
        while (_bi2567 < was.constructors.count) {
            var _c = _changed2555.try_get(_bi2567);
            _f2563.append(_c.is_value() ? _c.value() : was.constructors[_bi2567]);
            _bi2567 += 1;
        }
    } else if (_mode2566 == 3) {
        var _n2564 = input.count();
        for (var _ in 0.._n2564) {
            _f2563.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2564 = input.count();
        if (input.merging) {
            input.error = "t.*.constructors" + " written by place";
        }
        for (var _ in 0.._n2564) {
            var _tag2565 = input.unsigned();
            if (_tag2565 & 1 == 1) {
                if (!input.merging) {
                    _f2563.append(was.constructors[_tag2565 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2563.append(_read);
                }
            }
        }
    }
    var _f2570 = _m_FunctionDef_read(input);
    var _f2571 = _m_FunctionDef_read(input);
    var _f2572 = _m_FunctionDef_read(input);
    var _f2582 = Array<TypeName>();
    var _mode2585 = input.unsigned();
    if (_mode2585 == 2) {
        var _changed2574 = HashMap<ulong, TypeName>();
        ulong _bi2586 = 0;
        var _n2583 = input.count();
        for (var _ in 0.._n2583) {
            var _at2587 = input.unsigned();
            while (_f2582.count < _at2587 or (input.merging and _bi2586 < was.traits.count)) {
                var _c = _changed2574.try_get(_bi2586);
                _f2582.append(_c.is_value() ? _c.value() : was.traits[_bi2586]);
                _bi2586 += 1;
            }
            _f2582.append(_m_TypeName_read(input));
        }
        while (_bi2586 < was.traits.count) {
            var _c = _changed2574.try_get(_bi2586);
            _f2582.append(_c.is_value() ? _c.value() : was.traits[_bi2586]);
            _bi2586 += 1;
        }
    } else if (_mode2585 == 3) {
        var _n2583 = input.count();
        for (var _ in 0.._n2583) {
            _f2582.append(_m_TypeName_read(input));
        }
    } else {
        var _n2583 = input.count();
        if (input.merging) {
            input.error = "t.*.traits" + " written by place";
        }
        for (var _ in 0.._n2583) {
            var _tag2584 = input.unsigned();
            if (_tag2584 & 1 == 1) {
                if (!input.merging) {
                    _f2582.append(was.traits[_tag2584 >> 1]);
                }
            } else {
                var _read = _m_TypeName_read(input);
                if (!input.merging or true) {
                    _f2582.append(_read);
                }
            }
        }
    }
    var _f2598 = Array<ast.Attribute>();
    var _mode2601 = input.unsigned();
    if (_mode2601 == 2) {
        var _changed2590 = HashMap<ulong, ast.Attribute>();
        ulong _bi2602 = 0;
        var _n2599 = input.count();
        for (var _ in 0.._n2599) {
            var _at2603 = input.unsigned();
            while (_f2598.count < _at2603 or (input.merging and _bi2602 < was.attributes.count)) {
                var _c = _changed2590.try_get(_bi2602);
                _f2598.append(_c.is_value() ? _c.value() : was.attributes[_bi2602]);
                _bi2602 += 1;
            }
            _f2598.append(_a_Attribute_read(input));
        }
        while (_bi2602 < was.attributes.count) {
            var _c = _changed2590.try_get(_bi2602);
            _f2598.append(_c.is_value() ? _c.value() : was.attributes[_bi2602]);
            _bi2602 += 1;
        }
    } else if (_mode2601 == 3) {
        var _n2599 = input.count();
        for (var _ in 0.._n2599) {
            _f2598.append(_a_Attribute_read(input));
        }
    } else {
        var _n2599 = input.count();
        if (input.merging) {
            input.error = "t.*.attributes" + " written by place";
        }
        for (var _ in 0.._n2599) {
            var _tag2600 = input.unsigned();
            if (_tag2600 & 1 == 1) {
                if (!input.merging) {
                    _f2598.append(was.attributes[_tag2600 >> 1]);
                }
            } else {
                var _read = _a_Attribute_read(input);
                if (!input.merging or true) {
                    _f2598.append(_read);
                }
            }
        }
    }
    var _f2605 = input.loc();
    var _o2607 = Optional<Array<EnumCaseDef>>.Empty;
    if (input.unsigned() == 1) {
        var _v2608 = Array<EnumCaseDef>();
        var _n2609 = input.count();
        for (var _ in 0.._n2609) {
            _v2608.append(_m_EnumCaseDef_read(input));
        }
        _o2607 = Optional<Array<EnumCaseDef>>.Value(_v2608);
    }
    var _f2610 = _o2607;
    return StructDef(
        _f2488, _f2489, _f2499, _f2515, _f2531, _f2547, _f2563, _f2570, _f2571, _f2572, _f2582, _f2598, _f2605, _f2610
    );
}

_patch_t_index(value: StructDef, base: DeltaBase, slot: ulong) {
    if (base.verifying) {
        ulong _j2505 = 0;
        for (var _item2490 in value.generic_params) {
            var scratch = base.scratch();
            _m_GenericParam_write(scratch, _item2490);
            base.add($"t.{slot}.generic_params", scratch, _j2505);
            _j2505 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2521 = 0;
        for (var _item2506 in value.field_members) {
            var scratch = base.scratch();
            _m_VariableDef_write(scratch, _item2506);
            base.add($"t.{slot}.field_members", scratch, _j2521);
            _j2521 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2537 = 0;
        for (var _item2522 in value.method_members) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2522);
            base.add($"t.{slot}.method_members", scratch, _j2537);
            _j2537 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2553 = 0;
        for (var _item2538 in value.generic_methods) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2538);
            base.add($"t.{slot}.generic_methods", scratch, _j2553);
            _j2553 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2569 = 0;
        for (var _item2554 in value.constructors) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2554);
            base.add($"t.{slot}.constructors", scratch, _j2569);
            _j2569 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2588 = 0;
        for (var _item2573 in value.traits) {
            var scratch = base.scratch();
            _m_TypeName_write(scratch, _item2573);
            base.add($"t.{slot}.traits", scratch, _j2588);
            _j2588 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2604 = 0;
        for (var _item2589 in value.attributes) {
            var scratch = base.scratch();
            _a_Attribute_write(scratch, _item2589);
            base.add($"t.{slot}.attributes", scratch, _j2604);
            _j2604 += 1;
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
        for (var _item2611 in value.imports) {
            _a_Import_write(out, _item2611);
        }
        found.append(("imports", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.structs.count);
        for (var _item2612 in value.structs) {
            _m_StructDef_write(out, _item2612);
        }
        found.append(("structs", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.blank_bodies = false;
        out.unsigned(value.traits.count);
        for (var _item2613 in value.traits) {
            _m_TraitDef_write(out, _item2613);
        }
        found.append(("traits", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.extensions.count);
        for (var _item2614 in value.extensions) {
            _m_ExtensionDef_write(out, _item2614);
        }
        found.append(("extensions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.functions.count);
        for (var _item2615 in value.functions) {
            _m_FunctionDef_write(out, _item2615);
        }
        found.append(("functions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.externs.count);
        for (var _item2616 in value.externs) {
            _m_ExternDef_write(out, _item2616);
        }
        found.append(("externs", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.globals.count);
        for (var _item2617 in value.globals) {
            _m_VariableDef_write(out, _item2617);
        }
        found.append(("globals", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.static_blocks.count);
        for (var _item2618 in value.static_blocks) {
            _m_ModuleStaticBlock_write(out, _item2618);
        }
        found.append(("static_blocks", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.enums.count);
        for (var _item2619 in value.enums) {
            _m_EnumDef_write(out, _item2619);
        }
        found.append(("enums", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.struct_specs.count);
        for (var _item2620 in value.struct_specs) {
            _m_TypeName_write(out, _item2620);
        }
        found.append(("struct_specs", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.func_specs.count);
        for (var _item2621 in value.func_specs) {
            _m_TypeName_write(out, _item2621);
        }
        found.append(("func_specs", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.type_aliases.count);
        for (var _item2622 in value.type_aliases) {
            _m_TypeAliasDef_write(out, _item2622);
        }
        found.append(("type_aliases", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.withheld.count);
        for (var _item2623 in value.withheld) {
            _m_Withheld_write(out, _item2623);
        }
        found.append(("withheld", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.properties.count);
        for (var _item2624 in value.properties) {
            _m_PropertyDef_write(out, _item2624);
        }
        found.append(("properties", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.type_uses.count);
        for (var _item2625 in value.type_uses) {
            _m_TypeUse_write(out, _item2625);
        }
        found.append(("type_uses", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.use_contexts.count);
        for (var _item2626 in value.use_contexts) {
            _m_UseContext_write(out, _item2626);
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
            for (var _item2627 in value.literal_args) {
                var (_t2628, _t2629, _t2630) = _item2627;
                out.loc(_t2628);
                out.unsigned(_t2629);
                out.loc(_t2630);
            }
        }
        found.append(("literal_args", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.constrained_aliases.count);
        for (var _item2631 in value.constrained_aliases) {
            _m_TypeAliasDef_write(out, _item2631);
        }
        found.append(("constrained_aliases", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.trait_types.count);
        for (var _item2632 in value.trait_types) {
            _m_TraitType_write(out, _item2632);
        }
        found.append(("trait_types", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.conversions.count);
        for (var _item2633 in value.conversions) {
            _m_Conversion_write(out, _item2633);
        }
        found.append(("conversions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2635 = Array<(u8[], u8[], String)>();
        for (var (_key2634, _) in value.overload_sets) {
            var _scratch2636 = out.scratch();
            _scratch2636.text(_key2634);
            var _vscratch2638 = out.scratch();
            _vscratch2638.unsigned(value.overload_sets[_key2634].count);
            for (var _item2639 in value.overload_sets[_key2634]) {
                _vscratch2638.text(_item2639);
            }
            _keys2635.append((_scratch2636.finish(), _vscratch2638.finish(), _key2634));
        }
        _keys2635.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2635.count);
        for (var (_bytes2637, _, _key2634) in _keys2635) {
            out.text(_key2634);
            out.unsigned(value.overload_sets[_key2634].count);
            for (var _item2640 in value.overload_sets[_key2634]) {
                out.text(_item2640);
            }
        }
        found.append(("overload_sets", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2642 = Array<(u8[], u8[], String)>();
        for (var (_key2641, _) in value.overload_unions) {
            var _scratch2643 = out.scratch();
            _scratch2643.text(_key2641);
            var _vscratch2645 = out.scratch();
            _vscratch2645.unsigned(value.overload_unions[_key2641].count);
            for (var _item2646 in value.overload_unions[_key2641]) {
                _vscratch2645.unsigned(_item2646.count);
                for (var _item2647 in _item2646) {
                    _vscratch2645.text(_item2647);
                }
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
            out.unsigned(value.overload_unions[_key2641].count);
            for (var _item2648 in value.overload_unions[_key2641]) {
                out.unsigned(_item2648.count);
                for (var _item2649 in _item2648) {
                    out.text(_item2649);
                }
            }
        }
        found.append(("overload_unions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2651 = Array<(u8[], u8[], String)>();
        for (var (_key2650, _) in value.method_overload_sets) {
            var _scratch2652 = out.scratch();
            _scratch2652.text(_key2650);
            var _vscratch2654 = out.scratch();
            var _keys2656 = Array<(u8[], u8[], String)>();
            for (var (_key2655, _) in value.method_overload_sets[_key2650]) {
                var _scratch2657 = _vscratch2654.scratch();
                _scratch2657.text(_key2655);
                var _vscratch2659 = _vscratch2654.scratch();
                _vscratch2659.unsigned(value.method_overload_sets[_key2650][_key2655].count);
                for (var _item2660 in value.method_overload_sets[_key2650][_key2655]) {
                    _vscratch2659.text(_item2660);
                }
                _keys2656.append((_scratch2657.finish(), _vscratch2659.finish(), _key2655));
            }
            _keys2656.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            _vscratch2654.unsigned(_keys2656.count);
            for (var (_bytes2658, _, _key2655) in _keys2656) {
                _vscratch2654.text(_key2655);
                _vscratch2654.unsigned(value.method_overload_sets[_key2650][_key2655].count);
                for (var _item2661 in value.method_overload_sets[_key2650][_key2655]) {
                    _vscratch2654.text(_item2661);
                }
            }
            _keys2651.append((_scratch2652.finish(), _vscratch2654.finish(), _key2650));
        }
        _keys2651.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2651.count);
        for (var (_bytes2653, _, _key2650) in _keys2651) {
            out.text(_key2650);
            var _keys2663 = Array<(u8[], u8[], String)>();
            for (var (_key2662, _) in value.method_overload_sets[_key2650]) {
                var _scratch2664 = out.scratch();
                _scratch2664.text(_key2662);
                var _vscratch2666 = out.scratch();
                _vscratch2666.unsigned(value.method_overload_sets[_key2650][_key2662].count);
                for (var _item2667 in value.method_overload_sets[_key2650][_key2662]) {
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
            out.unsigned(_keys2663.count);
            for (var (_bytes2665, _, _key2662) in _keys2663) {
                out.text(_key2662);
                out.unsigned(value.method_overload_sets[_key2650][_key2662].count);
                for (var _item2668 in value.method_overload_sets[_key2650][_key2662]) {
                    out.text(_item2668);
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
        var _keys2670 = Array<(u8[], u8[], Loc)>();
        for (var _key2669 in value.private_functions) {
            var _scratch2671 = out.scratch();
            _scratch2671.loc(_key2669);
            var _vscratch2673 = out.scratch();
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
            out.loc(_key2669);
        }
        found.append(("private_functions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2675 = Array<(u8[], u8[], Loc)>();
        for (var _key2674 in value.file_private_functions) {
            var _scratch2676 = out.scratch();
            _scratch2676.loc(_key2674);
            var _vscratch2678 = out.scratch();
            _keys2675.append((_scratch2676.finish(), _vscratch2678.finish(), _key2674));
        }
        _keys2675.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2675.count);
        for (var (_bytes2677, _, _key2674) in _keys2675) {
            out.loc(_key2674);
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
            for (var _item2679 in value.call_targets) {
                var (_t2680, _t2681) = _item2679;
                out.loc(_t2680);
                out.text(_t2681);
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
            for (var _item2682 in value.argument_names) {
                var (_t2683, _t2684) = _item2682;
                out.loc(_t2683);
                out.text(_t2684);
            }
        }
        found.append(("argument_names", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.namespaces.count);
        for (var _item2685 in value.namespaces) {
            out.text(_item2685);
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
            for (var _item2686 in value.cached_files) {
                out.flag(_item2686);
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
            var _keys2688 = Array<(u8[], u8[], Loc)>();
            for (var (_key2687, _) in value.recorded_summaries) {
                var _scratch2689 = out.scratch();
                _scratch2689.loc(_key2687);
                var _vscratch2691 = out.scratch();
                _vscratch2691.text(value.recorded_summaries[_key2687]);
                _keys2688.append((_scratch2689.finish(), _vscratch2691.finish(), _key2687));
            }
            _keys2688.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            out.unsigned(_keys2688.count);
            for (var (_bytes2690, _, _key2687) in _keys2688) {
                out.loc(_key2687);
                out.text(value.recorded_summaries[_key2687]);
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
            var _keys2693 = Array<(u8[], u8[], Loc)>();
            for (var _key2692 in value.stripped) {
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
        var _keys2698 = Array<(u8[], u8[], String)>();
        for (var (_key2697, _) in value.spec_requests) {
            var _scratch2699 = out.scratch();
            _scratch2699.text(_key2697);
            var _vscratch2701 = out.scratch();
            _m_SpecRequest_write(_vscratch2701, value.spec_requests[_key2697]);
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
            out.text(_key2697);
            _m_SpecRequest_write(out, value.spec_requests[_key2697]);
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
            for (var _item2702 in value.summaries_to_record) {
                var (_t2703, _t2704) = _item2702;
                out.loc(_t2703);
                out.text(_t2704);
            }
        }
        found.append(("summaries_to_record", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2706 = Array<(u8[], u8[], String)>();
        for (var (_key2705, _) in value.caller_copies) {
            var _scratch2707 = out.scratch();
            _scratch2707.text(_key2705);
            var _vscratch2709 = out.scratch();
            _vscratch2709.unsigned(value.caller_copies[_key2705].count);
            for (var _item2710 in value.caller_copies[_key2705]) {
                _vscratch2709.flag(_item2710);
            }
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
            out.text(_key2705);
            out.unsigned(value.caller_copies[_key2705].count);
            for (var _item2711 in value.caller_copies[_key2705]) {
                out.flag(_item2711);
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
    for (var _item2712 in value.structs) {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        _m_StructDef_write(out, _item2712);
        found.append(("structs " + _item2712.name, interface_text(out)));
    }
    for (var _item2713 in value.functions) {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        _m_FunctionDef_write(out, _item2713);
        found.append(("functions " + _item2713.name, interface_text(out)));
    }
    return found;
}
