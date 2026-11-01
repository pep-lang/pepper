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
    var _s733 = input.unsigned();
    var _f734 = ast.Span(_s733, input.unsigned());
    var value = ast.PropertyDecl();
    value.attributes = _f722;
    value.name = _f723;
    value.name_span = _f725;
    value.type_name = _f726;
    value.default_value = _f728;
    value.getter = _f730;
    value.setter = _f732;
    value.span = _f734;
    return value;
}

_a_Accessor_write(out: RecordOut, value: ast.Accessor) {
    out.unsigned(out.blank_locs ? 0 : value.span.start);
    out.unsigned(out.blank_locs ? 0 : value.span.end);
    _a_FunctionDecl_write(out, value.function);
}

_a_Accessor_read(input: RecordIn): ast.Accessor {
    var _s735 = input.unsigned();
    var _f736 = ast.Span(_s735, input.unsigned());
    var _f737 = _a_FunctionDecl_read(input);
    var value = ast.Accessor(_f736, _f737);
    value.span = _f736;
    value.function = _f737;
    return value;
}

_a_FunctionDecl_write(out: RecordOut, value: ast.FunctionDecl) {
    out.text(value.name);
    out.unsigned(out.blank_locs ? 0 : value.name_span.start);
    out.unsigned(out.blank_locs ? 0 : value.name_span.end);
    out.unsigned(value.generic_params.count);
    for (var _item738 in value.generic_params) {
        _a_GenericParam_write(out, _item738);
    }
    _a_TypeName_write(out, value.return_type);
    out.unsigned(value.parameters.count);
    for (var _item739 in value.parameters) {
        _a_VariableDecl_write(out, _item739);
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
    for (var _item740 in value.attributes) {
        _a_Attribute_write(out, _item740);
    }
    out.flag(value.is_exported);
    out.flag(value.is_private);
}

_a_FunctionDecl_read(input: RecordIn): ast.FunctionDecl {
    var _f741 = input.text();
    var _s742 = input.unsigned();
    var _f743 = ast.Span(_s742, input.unsigned());
    var _v744 = Array<ast.GenericParam>();
    var _n745 = input.count();
    for (var _ in 0.._n745) {
        _v744.append(_a_GenericParam_read(input));
    }
    var _f746 = _v744;
    var _f747 = _a_TypeName_read(input);
    var _v748 = Array<ast.VariableDecl>();
    var _n749 = input.count();
    for (var _ in 0.._n749) {
        _v748.append(_a_VariableDecl_read(input));
    }
    var _f750 = _v748;
    var _f751 = input.flag();
    var _o752 = Optional<ast.Block>.Empty;
    if (input.unsigned() == 1) {
        _o752 = Optional<ast.Block>.Value(_a_Block_read(input));
    }
    var _f753 = _o752;
    var _f754 = input.flag();
    var _f755 = input.flag();
    var _f756 = input.flag();
    var _s757 = input.unsigned();
    var _f758 = ast.Span(_s757, input.unsigned());
    var _v759 = Array<ast.Attribute>();
    var _n760 = input.count();
    for (var _ in 0.._n760) {
        _v759.append(_a_Attribute_read(input));
    }
    var _f761 = _v759;
    var _f762 = input.flag();
    var _f763 = input.flag();
    var value = ast.FunctionDecl();
    value.name = _f741;
    value.name_span = _f743;
    value.generic_params = _f746;
    value.return_type = _f747;
    value.parameters = _f750;
    value.external = _f751;
    value.body = _f753;
    value.is_static = _f754;
    value.is_indexer = _f755;
    value.is_variadic = _f756;
    value.span = _f758;
    value.attributes = _f761;
    value.is_exported = _f762;
    value.is_private = _f763;
    return value;
}

_a_TraitDecl_write(out: RecordOut, value: ast.TraitDecl) {
    out.unsigned(value.attributes.count);
    for (var _item764 in value.attributes) {
        _a_Attribute_write(out, _item764);
    }
    out.text(value.name);
    out.unsigned(out.blank_locs ? 0 : value.name_span.start);
    out.unsigned(out.blank_locs ? 0 : value.name_span.end);
    out.unsigned(value.generic_params.count);
    for (var _item765 in value.generic_params) {
        _a_GenericParam_write(out, _item765);
    }
    out.unsigned(value.methods.count);
    for (var _item766 in value.methods) {
        _a_FunctionDecl_write(out, _item766);
    }
    out.unsigned(value.properties.count);
    for (var _item767 in value.properties) {
        _a_PropertyDecl_write(out, _item767);
    }
    out.unsigned(out.blank_locs ? 0 : value.span.start);
    out.unsigned(out.blank_locs ? 0 : value.span.end);
    out.flag(value.is_exported);
    out.flag(value.is_private);
}

_a_TraitDecl_read(input: RecordIn): ast.TraitDecl {
    var _v768 = Array<ast.Attribute>();
    var _n769 = input.count();
    for (var _ in 0.._n769) {
        _v768.append(_a_Attribute_read(input));
    }
    var _f770 = _v768;
    var _f771 = input.text();
    var _s772 = input.unsigned();
    var _f773 = ast.Span(_s772, input.unsigned());
    var _v774 = Array<ast.GenericParam>();
    var _n775 = input.count();
    for (var _ in 0.._n775) {
        _v774.append(_a_GenericParam_read(input));
    }
    var _f776 = _v774;
    var _v777 = Array<ast.FunctionDecl>();
    var _n778 = input.count();
    for (var _ in 0.._n778) {
        _v777.append(_a_FunctionDecl_read(input));
    }
    var _f779 = _v777;
    var _v780 = Array<ast.PropertyDecl>();
    var _n781 = input.count();
    for (var _ in 0.._n781) {
        _v780.append(_a_PropertyDecl_read(input));
    }
    var _f782 = _v780;
    var _s783 = input.unsigned();
    var _f784 = ast.Span(_s783, input.unsigned());
    var _f785 = input.flag();
    var _f786 = input.flag();
    var value = ast.TraitDecl();
    value.attributes = _f770;
    value.name = _f771;
    value.name_span = _f773;
    value.generic_params = _f776;
    value.methods = _f779;
    value.properties = _f782;
    value.span = _f784;
    value.is_exported = _f785;
    value.is_private = _f786;
    return value;
}

_a_StructDecl_write(out: RecordOut, value: ast.StructDecl) {
    out.text(value.name);
    out.unsigned(out.blank_locs ? 0 : value.name_span.start);
    out.unsigned(out.blank_locs ? 0 : value.name_span.end);
    out.unsigned(value.generic_params.count);
    for (var _item787 in value.generic_params) {
        _a_GenericParam_write(out, _item787);
    }
    out.unsigned(value.fields.count);
    for (var _item788 in value.fields) {
        _a_VariableDecl_write(out, _item788);
    }
    out.unsigned(value.properties.count);
    for (var _item789 in value.properties) {
        _a_PropertyDecl_write(out, _item789);
    }
    out.unsigned(value.methods.count);
    for (var _item790 in value.methods) {
        _a_FunctionDecl_write(out, _item790);
    }
    out.unsigned(value.constructors.count);
    for (var _item791 in value.constructors) {
        _a_FunctionDecl_write(out, _item791);
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
    for (var _item792 in value.attributes) {
        _a_Attribute_write(out, _item792);
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
    var _f793 = input.text();
    var _s794 = input.unsigned();
    var _f795 = ast.Span(_s794, input.unsigned());
    var _v796 = Array<ast.GenericParam>();
    var _n797 = input.count();
    for (var _ in 0.._n797) {
        _v796.append(_a_GenericParam_read(input));
    }
    var _f798 = _v796;
    var _v799 = Array<ast.VariableDecl>();
    var _n800 = input.count();
    for (var _ in 0.._n800) {
        _v799.append(_a_VariableDecl_read(input));
    }
    var _f801 = _v799;
    var _v802 = Array<ast.PropertyDecl>();
    var _n803 = input.count();
    for (var _ in 0.._n803) {
        _v802.append(_a_PropertyDecl_read(input));
    }
    var _f804 = _v802;
    var _v805 = Array<ast.FunctionDecl>();
    var _n806 = input.count();
    for (var _ in 0.._n806) {
        _v805.append(_a_FunctionDecl_read(input));
    }
    var _f807 = _v805;
    var _v808 = Array<ast.FunctionDecl>();
    var _n809 = input.count();
    for (var _ in 0.._n809) {
        _v808.append(_a_FunctionDecl_read(input));
    }
    var _f810 = _v808;
    var _o811 = Optional<ast.Block>.Empty;
    if (input.unsigned() == 1) {
        _o811 = Optional<ast.Block>.Value(_a_Block_read(input));
    }
    var _f812 = _o811;
    var _o813 = Optional<ast.Span>.Empty;
    if (input.unsigned() == 1) {
        var _s814 = input.unsigned();
        _o813 = Optional<ast.Span>.Value(ast.Span(_s814, input.unsigned()));
    }
    var _f815 = _o813;
    var _s816 = input.unsigned();
    var _f817 = ast.Span(_s816, input.unsigned());
    var _v818 = Array<ast.Attribute>();
    var _n819 = input.count();
    for (var _ in 0.._n819) {
        _v818.append(_a_Attribute_read(input));
    }
    var _f820 = _v818;
    var _f821 = input.flag();
    var _f822 = input.flag();
    var _o823 = Optional<ast.EnumBody>.Empty;
    if (input.unsigned() == 1) {
        _o823 = Optional<ast.EnumBody>.Value(_a_EnumBody_read(input));
    }
    var _f824 = _o823;
    var value = ast.StructDecl();
    value.name = _f793;
    value.name_span = _f795;
    value.generic_params = _f798;
    value.fields = _f801;
    value.properties = _f804;
    value.methods = _f807;
    value.constructors = _f810;
    value.destructor = _f812;
    value.destruct_span = _f815;
    value.span = _f817;
    value.attributes = _f820;
    value.is_exported = _f821;
    value.is_private = _f822;
    value.enumeration = _f824;
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
    for (var _item825 in value.cases) {
        _a_EnumCase_write(out, _item825);
    }
}

_a_EnumBody_read(input: RecordIn): ast.EnumBody {
    var _o826 = Optional<ast.TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o826 = Optional<ast.TypeName>.Value(_a_TypeName_read(input));
    }
    var _f827 = _o826;
    var _v828 = Array<ast.EnumCase>();
    var _n829 = input.count();
    for (var _ in 0.._n829) {
        _v828.append(_a_EnumCase_read(input));
    }
    var _f830 = _v828;
    var value = ast.EnumBody();
    value.representation = _f827;
    value.cases = _f830;
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
        for (var _item831 in value.payload.value()) {
            _a_VariableDecl_write(out, _item831);
        }
    } else {
        out.unsigned(0);
    }
    out.unsigned(value.attributes.count);
    for (var _item832 in value.attributes) {
        _a_Attribute_write(out, _item832);
    }
    out.unsigned(out.blank_locs ? 0 : value.span.start);
    out.unsigned(out.blank_locs ? 0 : value.span.end);
}

_a_EnumCase_read(input: RecordIn): ast.EnumCase {
    var _f833 = input.text();
    var _s834 = input.unsigned();
    var _f835 = ast.Span(_s834, input.unsigned());
    var _o836 = Optional<ast.Expression>.Empty;
    if (input.unsigned() == 1) {
        _o836 = Optional<ast.Expression>.Value(_a_Expression_read(input));
    }
    var _f837 = _o836;
    var _o838 = Optional<Array<ast.VariableDecl>>.Empty;
    if (input.unsigned() == 1) {
        var _v839 = Array<ast.VariableDecl>();
        var _n840 = input.count();
        for (var _ in 0.._n840) {
            _v839.append(_a_VariableDecl_read(input));
        }
        _o838 = Optional<Array<ast.VariableDecl>>.Value(_v839);
    }
    var _f841 = _o838;
    var _v842 = Array<ast.Attribute>();
    var _n843 = input.count();
    for (var _ in 0.._n843) {
        _v842.append(_a_Attribute_read(input));
    }
    var _f844 = _v842;
    var _s845 = input.unsigned();
    var _f846 = ast.Span(_s845, input.unsigned());
    var value = ast.EnumCase();
    value.name = _f833;
    value.name_span = _f835;
    value.value = _f837;
    value.payload = _f841;
    value.attributes = _f844;
    value.span = _f846;
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
        var _f847 = input.text();
        return ast.Literal.String(_f847);
    }
    if (tag == 1) {
        var _f848 = input.signed();
        return ast.Literal.Integer(_f848);
    }
    if (tag == 2) {
        var _f849 = input.unsigned();
        return ast.Literal.Unsigned(_f849);
    }
    if (tag == 3) {
        var _f850 = input.number();
        return ast.Literal.Float(_f850);
    }
    if (tag == 4) {
        var _f851 = input.flag();
        return ast.Literal.Bool(_f851);
    }
    if (tag == 5) {
        var _f852 = input.unsigned() as u8;
        return ast.Literal.Char(_f852);
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
    for (var _item853 in value.items) {
        _m_Statement_write(out, _item853);
    }
    out.unsigned(value.attributes.count);
    for (var _item854 in value.attributes) {
        _a_Attribute_write(out, _item854);
    }
}

_m_Block_read(input: RecordIn): Block {
    var _f855 = input.text();
    var _v856 = Array<Statement>();
    var _n857 = input.count();
    for (var _ in 0.._n857) {
        _v856.append(_m_Statement_read(input));
    }
    var _f858 = _v856;
    var _v859 = Array<ast.Attribute>();
    var _n860 = input.count();
    for (var _ in 0.._n860) {
        _v859.append(_a_Attribute_read(input));
    }
    var _f861 = _v859;
    return Block(_f855, _f858, _f861);
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
        var _f1280 = _m_Expression_read(input);
        return Statement.Expression(_f1280);
    }
    if (tag == 1) {
        var _f1281 = _m_Block_read(input);
        return Statement.Block(_f1281);
    }
    if (tag == 2) {
        var _f1282 = _m_Declaration_read(input);
        return Statement.Declaration(_f1282);
    }
    if (tag == 3) {
        var _f1283 = _m_Branch_read(input);
        return Statement.Branch(_f1283);
    }
    if (tag == 4) {
        var _f1284 = _m_While_read(input);
        return Statement.While(_f1284);
    }
    if (tag == 5) {
        var _f1285 = _m_ReturnStatement_read(input);
        return Statement.Return(_f1285);
    }
    if (tag == 6) {
        var _f1286 = _m_LoopBreak_read(input);
        return Statement.LoopBreak(_f1286);
    }
    if (tag == 7) {
        var _f1287 = _m_StaticBlock_read(input);
        return Statement.Static(_f1287);
    }
    if (tag == 8) {
        var _f1288 = _m_StaticPass_read(input);
        return Statement.StaticPass(_f1288);
    }
    input.fail("Statement", tag);
    return _m_Statement_read(input);
}

_m_StaticPass_write(out: RecordOut, value: StaticPass) {
    out.loc(value.loc);
    out.flag(value.stop);
    out.unsigned(value.values.count);
    for (var _item862 in value.values) {
        var (_t863, _t864) = _item862;
        out.text(_t863);
        _m_StaticConstant_write(out, _t864);
    }
    if (value.header.is_value()) {
        out.unsigned(1);
        out.unsigned(value.header.value() as ulong);
    } else {
        out.unsigned(0);
    }
    out.unsigned(value.lines.count);
    for (var _item865 in value.lines) {
        var (_t866, _t867) = _item865;
        out.loc(_t866);
        out.unsigned(_t867 as ulong);
    }
}

_m_StaticPass_read(input: RecordIn): StaticPass {
    var _f868 = input.loc();
    var _f869 = input.flag();
    var _v870 = Array<(String, StaticConstant)>();
    var _n871 = input.count();
    for (var _ in 0.._n871) {
        var _t872 = input.text();
        var _t873 = _m_StaticConstant_read(input);
        _v870.append((_t872, _t873));
    }
    var _f874 = _v870;
    var _o875 = Optional<uint>.Empty;
    if (input.unsigned() == 1) {
        _o875 = Optional<uint>.Value(input.unsigned() as uint);
    }
    var _f876 = _o875;
    var _v877 = Array<(Loc, uint)>();
    var _n878 = input.count();
    for (var _ in 0.._n878) {
        var _t879 = input.loc();
        var _t880 = input.unsigned() as uint;
        _v877.append((_t879, _t880));
    }
    var _f881 = _v877;
    return StaticPass(_f868, _f869, _f874, _f876, _f881);
}

_m_RecordStaticConstant_write(out: RecordOut, value: RecordStaticConstant) {
    out.text(value.name);
    out.unsigned(value.fields.count);
    for (var _item1293 in value.fields) {
        var (_t1294, _t1295) = _item1293;
        out.text(_t1294);
        _m_StaticConstant_write(out, _t1295);
    }
}

_m_RecordStaticConstant_read(input: RecordIn): RecordStaticConstant {
    var _f1296 = input.text();
    var _v1297 = Array<(String, StaticConstant)>();
    var _n1298 = input.count();
    for (var _ in 0.._n1298) {
        var _t1299 = input.text();
        var _t1300 = _m_StaticConstant_read(input);
        _v1297.append((_t1299, _t1300));
    }
    var _f1301 = _v1297;
    return RecordStaticConstant(_f1296, _f1301);
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
        var _f1289 = input.signed();
        return StaticConstant.Int(_f1289);
    }
    if (tag == 1) {
        var _f1290 = input.number();
        return StaticConstant.Float(_f1290);
    }
    if (tag == 2) {
        var _f1291 = input.flag();
        return StaticConstant.Bool(_f1291);
    }
    if (tag == 3) {
        var _f1292 = input.text();
        return StaticConstant.String(_f1292);
    }
    if (tag == 4) {
        return StaticConstant.Record(_m_RecordStaticConstant_read(input));
    }
    input.fail("StaticConstant", tag);
    return _m_StaticConstant_read(input);
}

_m_StaticBlock_write(out: RecordOut, value: StaticBlock) {
    out.unsigned(value.captures.count);
    for (var _item882 in value.captures) {
        out.text(_item882);
    }
    out.unsigned(value.items.count);
    for (var _item883 in value.items) {
        _m_StaticItem_write(out, _item883);
    }
    out.unsigned(value.type_map.count);
    for (var _item884 in value.type_map) {
        var (_t885, _t886) = _item884;
        out.text(_t885);
        _m_TypeName_write(out, _t886);
    }
    out.loc(value.loc);
    out.unsigned(out.blank_locs ? 0 : value.span.start);
    out.unsigned(out.blank_locs ? 0 : value.span.end);
}

_m_StaticBlock_read(input: RecordIn): StaticBlock {
    var _v887 = Array<String>();
    var _n888 = input.count();
    for (var _ in 0.._n888) {
        _v887.append(input.text());
    }
    var _f889 = _v887;
    var _v890 = Array<StaticItem>();
    var _n891 = input.count();
    for (var _ in 0.._n891) {
        _v890.append(_m_StaticItem_read(input));
    }
    var _f892 = _v890;
    var _v893 = Array<(String, TypeName)>();
    var _n894 = input.count();
    for (var _ in 0.._n894) {
        var _t895 = input.text();
        var _t896 = _m_TypeName_read(input);
        _v893.append((_t895, _t896));
    }
    var _f897 = _v893;
    var _f898 = input.loc();
    var _s899 = input.unsigned();
    var _f900 = ast.Span(_s899, input.unsigned());
    return StaticBlock(_f889, _f892, _f897, _f898, _f900);
}

_m_TypeName_write(out: RecordOut, value: TypeName) {
    out.text(value.name);
    out.unsigned(value.sub_types.count);
    for (var _item901 in value.sub_types) {
        _m_TypeName_write(out, _item901);
    }
    _m_TypeFlags_write(out, value.flags);
    out.unsigned(value.labels.count);
    for (var _item902 in value.labels) {
        out.text(_item902);
    }
}

_m_TypeName_read(input: RecordIn): TypeName {
    var _f903 = input.text();
    var _v904 = Array<TypeName>();
    var _n905 = input.count();
    for (var _ in 0.._n905) {
        _v904.append(_m_TypeName_read(input));
    }
    var _f906 = _v904;
    var _f907 = _m_TypeFlags_read(input);
    var _v908 = Array<String>();
    var _n909 = input.count();
    for (var _ in 0.._n909) {
        _v908.append(input.text());
    }
    var _f910 = _v908;
    return TypeName(_f903, _f906, _f907, _f910);
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
    for (var _item1302 in value.body) {
        _m_StaticItem_write(out, _item1302);
    }
    out.loc(value.loc);
}

_m_ForStaticItem_read(input: RecordIn): ForStaticItem {
    var _f1303 = input.text();
    var _f1304 = _a_Expression_read(input);
    var _v1305 = Array<StaticItem>();
    var _n1306 = input.count();
    for (var _ in 0.._n1306) {
        _v1305.append(_m_StaticItem_read(input));
    }
    var _f1307 = _v1305;
    var _f1308 = input.loc();
    return ForStaticItem(_f1304, _f1303, _f1307, _f1308);
}

_m_WhileStaticItem_write(out: RecordOut, value: WhileStaticItem) {
    _a_Expression_write(out, value.condition);
    out.unsigned(value.body.count);
    for (var _item1309 in value.body) {
        _m_StaticItem_write(out, _item1309);
    }
    out.loc(value.loc);
}

_m_WhileStaticItem_read(input: RecordIn): WhileStaticItem {
    var _f1310 = _a_Expression_read(input);
    var _v1311 = Array<StaticItem>();
    var _n1312 = input.count();
    for (var _ in 0.._n1312) {
        _v1311.append(_m_StaticItem_read(input));
    }
    var _f1313 = _v1311;
    var _f1314 = input.loc();
    return WhileStaticItem(_f1310, _f1313, _f1314);
}

_m_JumpStaticItem_write(out: RecordOut, value: JumpStaticItem) {
    _m_LoopBreakKind_write(out, value.kind);
    out.loc(value.loc);
}

_m_JumpStaticItem_read(input: RecordIn): JumpStaticItem {
    var _f1315 = _m_LoopBreakKind_read(input);
    var _f1316 = input.loc();
    return JumpStaticItem(_f1315, _f1316);
}

_m_IfStaticItem_write(out: RecordOut, value: IfStaticItem) {
    _a_Expression_write(out, value.condition);
    out.unsigned(value.then_items.count);
    for (var _item1317 in value.then_items) {
        _m_StaticItem_write(out, _item1317);
    }
    out.unsigned(value.else_items.count);
    for (var _item1318 in value.else_items) {
        _m_StaticItem_write(out, _item1318);
    }
    out.loc(value.loc);
}

_m_IfStaticItem_read(input: RecordIn): IfStaticItem {
    var _f1319 = _a_Expression_read(input);
    var _v1320 = Array<StaticItem>();
    var _n1321 = input.count();
    for (var _ in 0.._n1321) {
        _v1320.append(_m_StaticItem_read(input));
    }
    var _f1322 = _v1320;
    var _v1323 = Array<StaticItem>();
    var _n1324 = input.count();
    for (var _ in 0.._n1324) {
        _v1323.append(_m_StaticItem_read(input));
    }
    var _f1325 = _v1323;
    var _f1326 = input.loc();
    return IfStaticItem(_f1319, _f1322, _f1325, _f1326);
}

_m_EmitIfStaticItem_write(out: RecordOut, value: EmitIfStaticItem) {
    _m_Expression_write(out, value.condition);
    out.unsigned(value.then_items.count);
    for (var _item1327 in value.then_items) {
        _m_StaticItem_write(out, _item1327);
    }
    out.unsigned(value.else_items.count);
    for (var _item1328 in value.else_items) {
        _m_StaticItem_write(out, _item1328);
    }
    out.unsigned(out.blank_locs ? 0 : value.span.start);
    out.unsigned(out.blank_locs ? 0 : value.span.end);
}

_m_EmitIfStaticItem_read(input: RecordIn): EmitIfStaticItem {
    var _f1329 = _m_Expression_read(input);
    var _v1330 = Array<StaticItem>();
    var _n1331 = input.count();
    for (var _ in 0.._n1331) {
        _v1330.append(_m_StaticItem_read(input));
    }
    var _f1332 = _v1330;
    var _v1333 = Array<StaticItem>();
    var _n1334 = input.count();
    for (var _ in 0.._n1334) {
        _v1333.append(_m_StaticItem_read(input));
    }
    var _f1335 = _v1333;
    var _s1336 = input.unsigned();
    var _f1337 = ast.Span(_s1336, input.unsigned());
    return EmitIfStaticItem(_f1329, _f1332, _f1335, _f1337);
}

_m_VarStaticItem_write(out: RecordOut, value: VarStaticItem) {
    out.text(value.name);
    _a_Expression_write(out, value.value);
    out.loc(value.loc);
}

_m_VarStaticItem_read(input: RecordIn): VarStaticItem {
    var _f1342 = input.text();
    var _f1343 = _a_Expression_read(input);
    var _f1344 = input.loc();
    return VarStaticItem(_f1343, _f1342, _f1344);
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
            for (var _item1338 in v) {
                _m_StaticItem_write(out, _item1338);
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
        var _v1339 = Array<StaticItem>();
        var _n1340 = input.count();
        for (var _ in 0.._n1340) {
            _v1339.append(_m_StaticItem_read(input));
        }
        var _f1341 = _v1339;
        return StaticItem.Block(_f1341);
    }
    if (tag == 6) {
        return StaticItem.Var(_m_VarStaticItem_read(input));
    }
    if (tag == 7) {
        var _f1345 = _a_Expression_read(input);
        return StaticItem.Evaluate(_f1345);
    }
    if (tag == 8) {
        var _f1346 = _m_Statement_read(input);
        var _s1347 = input.unsigned();
        var _f1348 = ast.Span(_s1347, input.unsigned());
        return StaticItem.Emit(_f1346, _f1348);
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
    var _f1349 = input.text();
    var _f1350 = _m_TypeName_read(input);
    var _f1351 = input.loc();
    return SymbolRefExpression(_f1349, _f1350, _f1351);
}

_m_MemberRefExpression_write(out: RecordOut, value: MemberRefExpression) {
    _m_Expression_write(out, value.lhs);
    out.text(value.name);
    out.loc(value.loc);
}

_m_MemberRefExpression_read(input: RecordIn): MemberRefExpression {
    var _f1352 = _m_Expression_read(input);
    var _f1353 = input.text();
    var _f1354 = input.loc();
    return MemberRefExpression(_f1352, _f1353, _f1354);
}

_m_StringLiteralExpression_write(out: RecordOut, value: StringLiteralExpression) {
    out.text(value.value);
    out.flag(value.is_raw);
    out.loc(value.loc);
}

_m_StringLiteralExpression_read(input: RecordIn): StringLiteralExpression {
    var _f1358 = input.text();
    var _f1359 = input.flag();
    var _f1360 = input.loc();
    return StringLiteralExpression(_f1358, _f1359, _f1360);
}

_m_BinaryExpression_write(out: RecordOut, value: BinaryExpression) {
    _m_BinaryOp_write(out, value.op);
    _m_Expression_write(out, value.lhs);
    _m_Expression_write(out, value.rhs);
    out.loc(value.loc);
}

_m_BinaryExpression_read(input: RecordIn): BinaryExpression {
    var _f1361 = _m_BinaryOp_read(input);
    var _f1362 = _m_Expression_read(input);
    var _f1363 = _m_Expression_read(input);
    var _f1364 = input.loc();
    return BinaryExpression(_f1362, _f1363, _f1361, _f1364);
}

_m_UnaryExpression_write(out: RecordOut, value: UnaryExpression) {
    _m_UnaryOp_write(out, value.op);
    _m_Expression_write(out, value.operand);
    out.loc(value.loc);
}

_m_UnaryExpression_read(input: RecordIn): UnaryExpression {
    var _f1365 = _m_UnaryOp_read(input);
    var _f1366 = _m_Expression_read(input);
    var _f1367 = input.loc();
    return UnaryExpression(_f1366, _f1365, _f1367);
}

_m_CastExpression_write(out: RecordOut, value: CastExpression) {
    _m_Expression_write(out, value.expr);
    _m_TypeName_write(out, value.ty);
    out.loc(value.loc);
    _m_CastKind_write(out, value.kind);
}

_m_CastExpression_read(input: RecordIn): CastExpression {
    var _f1368 = _m_Expression_read(input);
    var _f1369 = _m_TypeName_read(input);
    var _f1370 = input.loc();
    var _f1371 = _m_CastKind_read(input);
    return CastExpression(_f1368, _f1369, _f1370, _f1371);
}

_m_TernaryExpression_write(out: RecordOut, value: TernaryExpression) {
    _m_Expression_write(out, value.condition);
    _m_Expression_write(out, value.true_expr);
    _m_Expression_write(out, value.false_expr);
}

_m_TernaryExpression_read(input: RecordIn): TernaryExpression {
    var _f1372 = _m_Expression_read(input);
    var _f1373 = _m_Expression_read(input);
    var _f1374 = _m_Expression_read(input);
    return TernaryExpression(_f1372, _f1373, _f1374);
}

_m_IndexExpression_write(out: RecordOut, value: IndexExpression) {
    _m_Expression_write(out, value.lhs);
    _m_Expression_write(out, value.rhs);
    out.loc(value.loc);
}

_m_IndexExpression_read(input: RecordIn): IndexExpression {
    var _f1375 = _m_Expression_read(input);
    var _f1376 = _m_Expression_read(input);
    var _f1377 = input.loc();
    return IndexExpression(_f1375, _f1376, _f1377);
}

_m_ArrayIndexExpression_write(out: RecordOut, value: ArrayIndexExpression) {
    _m_TypeName_write(out, value.ty);
    _m_Expression_write(out, value.lhs);
    _m_Expression_write(out, value.rhs);
    out.loc(value.loc);
}

_m_ArrayIndexExpression_read(input: RecordIn): ArrayIndexExpression {
    var _f1378 = _m_TypeName_read(input);
    var _f1379 = _m_Expression_read(input);
    var _f1380 = _m_Expression_read(input);
    var _f1381 = input.loc();
    return ArrayIndexExpression(_f1379, _f1380, _f1378, _f1381);
}

_m_SimdExpression_write(out: RecordOut, value: SimdExpression) {
    _m_SimdOp_write(out, value.op);
    _m_TypeName_write(out, value.ty);
    out.unsigned(value.args.count);
    for (var _item1405 in value.args) {
        _m_Expression_write(out, _item1405);
    }
    out.loc(value.loc);
}

_m_SimdExpression_read(input: RecordIn): SimdExpression {
    var _f1406 = _m_SimdOp_read(input);
    var _f1407 = _m_TypeName_read(input);
    var _v1408 = Array<Expression>();
    var _n1409 = input.count();
    for (var _ in 0.._n1409) {
        _v1408.append(_m_Expression_read(input));
    }
    var _f1410 = _v1408;
    var _f1411 = input.loc();
    return SimdExpression(_f1406, _f1407, _f1410, _f1411);
}

_m_CountStepExpression_write(out: RecordOut, value: CountStepExpression) {
    _m_CountField_write(out, value.field);
    out.flag(value.increment);
    out.flag(value.atomic);
}

_m_CountStepExpression_read(input: RecordIn): CountStepExpression {
    var _f1415 = _m_CountField_read(input);
    var _f1416 = input.flag();
    var _f1417 = input.flag();
    return CountStepExpression(_f1415, _f1416, _f1417);
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
    var _o1418 = Optional<TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o1418 = Optional<TypeName>.Value(_m_TypeName_read(input));
    }
    var _f1419 = _o1418;
    var _f1420 = input.text();
    var _f1421 = input.loc();
    return FunctionPointerExpression(_f1419, _f1420, _f1421);
}

_m_FunctionCallExpression_write(out: RecordOut, value: FunctionCallExpression) {
    out.text(value.function);
    out.unsigned(value.args.count);
    for (var _item1422 in value.args) {
        _m_Expression_write(out, _item1422);
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
    var _f1423 = input.text();
    var _v1424 = Array<Expression>();
    var _n1425 = input.count();
    for (var _ in 0.._n1425) {
        _v1424.append(_m_Expression_read(input));
    }
    var _f1426 = _v1424;
    var _f1427 = input.loc();
    var _o1428 = Optional<TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o1428 = Optional<TypeName>.Value(_m_TypeName_read(input));
    }
    var _f1429 = _o1428;
    var _f1430 = input.flag();
    return FunctionCallExpression(_f1423, _f1426, _f1427, _f1429, _f1430);
}

_m_NamedArgumentExpression_write(out: RecordOut, value: NamedArgumentExpression) {
    out.text(value.name);
    _m_Expression_write(out, value.value);
    out.loc(value.loc);
}

_m_NamedArgumentExpression_read(input: RecordIn): NamedArgumentExpression {
    var _f1431 = input.text();
    var _f1432 = _m_Expression_read(input);
    var _f1433 = input.loc();
    return NamedArgumentExpression(_f1432, _f1431, _f1433);
}

_m_DefaultArgumentExpression_write(out: RecordOut, value: DefaultArgumentExpression) {
    _m_TypeName_write(out, value.ty);
}

_m_DefaultArgumentExpression_read(input: RecordIn): DefaultArgumentExpression {
    var _f1434 = _m_TypeName_read(input);
    return DefaultArgumentExpression(_f1434);
}

_m_MethodCallExpression_write(out: RecordOut, value: MethodCallExpression) {
    _m_Expression_write(out, value.this_value);
    out.text(value.method);
    out.unsigned(value.args.count);
    for (var _item1435 in value.args) {
        _m_Expression_write(out, _item1435);
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
    var _f1436 = _m_Expression_read(input);
    var _f1437 = input.text();
    var _v1438 = Array<Expression>();
    var _n1439 = input.count();
    for (var _ in 0.._n1439) {
        _v1438.append(_m_Expression_read(input));
    }
    var _f1440 = _v1438;
    var _f1441 = input.loc();
    var _o1442 = Optional<TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o1442 = Optional<TypeName>.Value(_m_TypeName_read(input));
    }
    var _f1443 = _o1442;
    return MethodCallExpression(_f1436, _f1437, _f1440, _f1441, _f1443);
}

_m_FunctionRefExpression_write(out: RecordOut, value: FunctionRefExpression) {
    out.text(value.function);
    _m_TypeName_write(out, value.ty);
    out.loc(value.loc);
}

_m_FunctionRefExpression_read(input: RecordIn): FunctionRefExpression {
    var _f1444 = input.text();
    var _f1445 = _m_TypeName_read(input);
    var _f1446 = input.loc();
    return FunctionRefExpression(_f1444, _f1445, _f1446);
}

_m_InvokeExpression_write(out: RecordOut, value: InvokeExpression) {
    _m_Expression_write(out, value.callee);
    out.unsigned(value.args.count);
    for (var _item1447 in value.args) {
        _m_Expression_write(out, _item1447);
    }
}

_m_InvokeExpression_read(input: RecordIn): InvokeExpression {
    var _f1448 = _m_Expression_read(input);
    var _v1449 = Array<Expression>();
    var _n1450 = input.count();
    for (var _ in 0.._n1450) {
        _v1449.append(_m_Expression_read(input));
    }
    var _f1451 = _v1449;
    return InvokeExpression(_f1448, _f1451);
}

_m_MakeClosureExpression_write(out: RecordOut, value: MakeClosureExpression) {
    _m_Expression_write(out, value.value);
    out.text(value.closure);
    _m_TypeName_write(out, value.ty);
    out.loc(value.loc);
}

_m_MakeClosureExpression_read(input: RecordIn): MakeClosureExpression {
    var _f1453 = _m_Expression_read(input);
    var _f1454 = input.text();
    var _f1455 = _m_TypeName_read(input);
    var _f1456 = input.loc();
    return MakeClosureExpression(_f1453, _f1454, _f1455, _f1456);
}

_m_CallPointerExpression_write(out: RecordOut, value: CallPointerExpression) {
    _m_Expression_write(out, value.pointer);
    out.unsigned(value.args.count);
    for (var _item1458 in value.args) {
        _m_Expression_write(out, _item1458);
    }
}

_m_CallPointerExpression_read(input: RecordIn): CallPointerExpression {
    var _f1459 = _m_Expression_read(input);
    var _v1460 = Array<Expression>();
    var _n1461 = input.count();
    for (var _ in 0.._n1461) {
        _v1460.append(_m_Expression_read(input));
    }
    var _f1462 = _v1460;
    return CallPointerExpression(_f1459, _f1462);
}

_m_MoveExpression_write(out: RecordOut, value: MoveExpression) {
    _m_Expression_write(out, value.value);
    out.loc(value.loc);
}

_m_MoveExpression_read(input: RecordIn): MoveExpression {
    var _f1465 = _m_Expression_read(input);
    var _f1466 = input.loc();
    return MoveExpression(_f1465, _f1466);
}

_m_DestructureExpression_write(out: RecordOut, value: DestructureExpression) {
    _m_Expression_write(out, value.value);
    out.unsigned(value.count);
    out.loc(value.loc);
}

_m_DestructureExpression_read(input: RecordIn): DestructureExpression {
    var _f1467 = _m_Expression_read(input);
    var _f1468 = input.unsigned();
    var _f1469 = input.loc();
    return DestructureExpression(_f1467, _f1468, _f1469);
}

_m_StaticCaseExpression_write(out: RecordOut, value: StaticCaseExpression) {
    _m_TypeName_write(out, value.ty);
    out.signed(value.tag as long);
}

_m_StaticCaseExpression_read(input: RecordIn): StaticCaseExpression {
    var _f1472 = _m_TypeName_read(input);
    var _f1473 = input.signed();
    return StaticCaseExpression(_f1472, _f1473);
}

_m_StaticStringExpression_write(out: RecordOut, value: StaticStringExpression) {
    out.text(value.value);
    out.loc(value.loc);
}

_m_StaticStringExpression_read(input: RecordIn): StaticStringExpression {
    var _f1474 = input.text();
    var _f1475 = input.loc();
    return StaticStringExpression(_f1474, _f1475);
}

_m_SubjectExpression_write(out: RecordOut, value: SubjectExpression) {
    out.unsigned(value.id);
    _m_TypeName_write(out, value.ty);
    out.loc(value.loc);
}

_m_SubjectExpression_read(input: RecordIn): SubjectExpression {
    var _f1477 = input.unsigned();
    var _f1478 = _m_TypeName_read(input);
    var _f1479 = input.loc();
    return SubjectExpression(_f1477, _f1478, _f1479);
}

_m_ToTraitExpression_write(out: RecordOut, value: ToTraitExpression) {
    _m_Expression_write(out, value.value);
    _m_TypeName_write(out, value.from);
    _m_TypeName_write(out, value.to);
    out.loc(value.loc);
}

_m_ToTraitExpression_read(input: RecordIn): ToTraitExpression {
    var _f1480 = _m_Expression_read(input);
    var _f1481 = _m_TypeName_read(input);
    var _f1482 = _m_TypeName_read(input);
    var _f1483 = input.loc();
    return ToTraitExpression(_f1480, _f1481, _f1482, _f1483);
}

_m_FromTraitExpression_write(out: RecordOut, value: FromTraitExpression) {
    _m_Expression_write(out, value.value);
    _m_TypeName_write(out, value.from);
    _m_TypeName_write(out, value.to);
    out.unsigned(value.candidates.count);
    for (var _item1484 in value.candidates) {
        _m_TypeName_write(out, _item1484);
    }
    out.flag(value.test);
    out.loc(value.loc);
}

_m_FromTraitExpression_read(input: RecordIn): FromTraitExpression {
    var _f1485 = _m_Expression_read(input);
    var _f1486 = _m_TypeName_read(input);
    var _f1487 = _m_TypeName_read(input);
    var _v1488 = Array<TypeName>();
    var _n1489 = input.count();
    for (var _ in 0.._n1489) {
        _v1488.append(_m_TypeName_read(input));
    }
    var _f1490 = _v1488;
    var _f1491 = input.flag();
    var _f1492 = input.loc();
    return FromTraitExpression(_f1485, _f1486, _f1487, _f1490, _f1491, _f1492);
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
        var _f1355 = input.flag();
        return Expression.BoolLiteral(_f1355);
    }
    if (tag == 4) {
        var _f1356 = input.signed();
        return Expression.IntLiteral(_f1356);
    }
    if (tag == 5) {
        var _f1357 = input.number();
        return Expression.FloatLiteral(_f1357);
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
        var _f1382 = _m_TypeName_read(input);
        return Expression.SizeOf(_f1382);
    }
    if (tag == 15) {
        var _f1383 = _m_TypeName_read(input);
        return Expression.IsPod(_f1383);
    }
    if (tag == 16) {
        var _f1384 = _m_TypeName_read(input);
        return Expression.Default(_f1384);
    }
    if (tag == 17) {
        var _f1385 = _m_TypeName_read(input);
        return Expression.Allocate(_f1385);
    }
    if (tag == 18) {
        var _f1386 = _m_TypeName_read(input);
        var _f1387 = _m_Expression_read(input);
        return Expression.RefCount(_f1386, _f1387);
    }
    if (tag == 19) {
        var _f1388 = _m_TypeName_read(input);
        var _f1389 = _m_Expression_read(input);
        return Expression.Address(_f1388, _f1389);
    }
    if (tag == 20) {
        var _f1390 = _m_TypeName_read(input);
        var _f1391 = _m_Expression_read(input);
        return Expression.AtomicLoad(_f1390, _f1391);
    }
    if (tag == 21) {
        var _f1392 = _m_TypeName_read(input);
        var _f1393 = _m_Expression_read(input);
        var _f1394 = _m_Expression_read(input);
        return Expression.AtomicStore(_f1392, _f1393, _f1394);
    }
    if (tag == 22) {
        var _f1395 = _m_Expression_read(input);
        var _f1396 = _m_Expression_read(input);
        return Expression.ConstructAt(_f1395, _f1396);
    }
    if (tag == 23) {
        var _f1397 = _m_TypeName_read(input);
        var _f1398 = _m_Expression_read(input);
        var _f1399 = _m_Expression_read(input);
        var _f1400 = _m_Expression_read(input);
        return Expression.AtomicCmpXchg(_f1397, _f1398, _f1399, _f1400);
    }
    if (tag == 24) {
        var _f1401 = _m_AtomicFetchOp_read(input);
        var _f1402 = _m_TypeName_read(input);
        var _f1403 = _m_Expression_read(input);
        var _f1404 = _m_Expression_read(input);
        return Expression.AtomicFetch(_f1401, _f1402, _f1403, _f1404);
    }
    if (tag == 25) {
        return Expression.Simd(_m_SimdExpression_read(input));
    }
    if (tag == 26) {
        var _f1412 = _m_WeakOp_read(input);
        var _f1413 = _m_TypeName_read(input);
        var _f1414 = _m_Expression_read(input);
        return Expression.Weak(_f1412, _f1413, _f1414);
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
        var _f1452 = _m_ClosureLiteral_read(input);
        return Expression.ClosureLiteral(_f1452);
    }
    if (tag == 36) {
        return Expression.MakeClosure(_m_MakeClosureExpression_read(input));
    }
    if (tag == 37) {
        var _f1457 = input.text();
        return Expression.MethodAddress(_f1457);
    }
    if (tag == 38) {
        return Expression.CallPointer(_m_CallPointerExpression_read(input));
    }
    if (tag == 39) {
        var _f1463 = _m_Expression_read(input);
        return Expression.ForIterator(_f1463);
    }
    if (tag == 40) {
        var _f1464 = _m_Expression_read(input);
        return Expression.WithEntered(_f1464);
    }
    if (tag == 41) {
        return Expression.Move(_m_MoveExpression_read(input));
    }
    if (tag == 42) {
        return Expression.Destructure(_m_DestructureExpression_read(input));
    }
    if (tag == 43) {
        var _f1470 = _m_MatchArmTest_read(input);
        return Expression.MatchArm(_f1470);
    }
    if (tag == 44) {
        var _f1471 = _m_CaseValue_read(input);
        return Expression.CaseValue(_f1471);
    }
    if (tag == 45) {
        return Expression.StaticCase(_m_StaticCaseExpression_read(input));
    }
    if (tag == 46) {
        return Expression.StaticString(_m_StaticStringExpression_read(input));
    }
    if (tag == 47) {
        var _f1476 = _m_WithSubject_read(input);
        return Expression.WithSubject(_f1476);
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
        var _f1493 = _m_StaticValue_read(input);
        return Expression.StaticValue(_f1493);
    }
    if (tag == 53) {
        var _f1494 = _m_StaticMember_read(input);
        return Expression.StaticMember(_f1494);
    }
    input.fail("Expression", tag);
    return _m_Expression_read(input);
}

_m_StaticMember_write(out: RecordOut, value: StaticMember) {
    _a_Expression_write(out, value.member);
    out.text(value.method);
    out.unsigned(value.args.count);
    for (var _item911 in value.args) {
        _m_Expression_write(out, _item911);
    }
    out.loc(value.loc);
    out.unsigned(out.blank_locs ? 0 : value.span.start);
    out.unsigned(out.blank_locs ? 0 : value.span.end);
    out.unsigned(value.argument_spans.count);
    for (var _item912 in value.argument_spans) {
        out.unsigned(out.blank_locs ? 0 : _item912.start);
        out.unsigned(out.blank_locs ? 0 : _item912.end);
    }
}

_m_StaticMember_read(input: RecordIn): StaticMember {
    var _f913 = _a_Expression_read(input);
    var _f914 = input.text();
    var _v915 = Array<Expression>();
    var _n916 = input.count();
    for (var _ in 0.._n916) {
        _v915.append(_m_Expression_read(input));
    }
    var _f917 = _v915;
    var _f918 = input.loc();
    var _s919 = input.unsigned();
    var _f920 = ast.Span(_s919, input.unsigned());
    var _v921 = Array<ast.Span>();
    var _n922 = input.count();
    for (var _ in 0.._n922) {
        var _s923 = input.unsigned();
        _v921.append(ast.Span(_s923, input.unsigned()));
    }
    var _f924 = _v921;
    return StaticMember(_f913, _f914, _f917, _f918, _f920, _f924);
}

_m_StaticValue_write(out: RecordOut, value: StaticValue) {
    _a_Expression_write(out, value.expr);
    out.loc(value.loc);
}

_m_StaticValue_read(input: RecordIn): StaticValue {
    var _f925 = _a_Expression_read(input);
    var _f926 = input.loc();
    return StaticValue(_f925, _f926);
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
    var _f927 = input.unsigned();
    var _f928 = _m_Expression_read(input);
    var _f929 = _m_Expression_read(input);
    var _o930 = Optional<String>.Empty;
    if (input.unsigned() == 1) {
        _o930 = Optional<String>.Value(input.text());
    }
    var _f931 = _o930;
    var _f932 = input.loc();
    return WithSubject(_f928, _f929, _f927, _f931, _f932);
}

_m_CaseValue_write(out: RecordOut, value: CaseValue) {
    _m_Expression_write(out, value.subject);
    out.text(value.name);
    out.unsigned(value.choices.count);
    for (var _item933 in value.choices) {
        _m_CaseChoice_write(out, _item933);
    }
    out.loc(value.loc);
}

_m_CaseValue_read(input: RecordIn): CaseValue {
    var _f934 = _m_Expression_read(input);
    var _f935 = input.text();
    var _v936 = Array<CaseChoice>();
    var _n937 = input.count();
    for (var _ in 0.._n937) {
        _v936.append(_m_CaseChoice_read(input));
    }
    var _f938 = _v936;
    var _f939 = input.loc();
    return CaseValue(_f934, _f935, _f938, _f939);
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
    for (var _item940 in value.bindings) {
        out.loc(_item940);
    }
    out.loc(value.loc);
}

_m_CaseChoice_read(input: RecordIn): CaseChoice {
    var _f941 = input.text();
    var _f942 = input.loc();
    var _o943 = Optional<TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o943 = Optional<TypeName>.Value(_m_TypeName_read(input));
    }
    var _f944 = _o943;
    var _f945 = input.unsigned();
    var _v946 = Array<Loc>();
    var _n947 = input.count();
    for (var _ in 0.._n947) {
        _v946.append(input.loc());
    }
    var _f948 = _v946;
    var _f949 = input.loc();
    return CaseChoice(_f941, _f942, _f944, _f945, _f948, _f949);
}

_m_MatchArmTest_write(out: RecordOut, value: MatchArmTest) {
    _m_Expression_write(out, value.subject);
    out.unsigned(value.patterns.count);
    for (var _item950 in value.patterns) {
        _m_CasePattern_write(out, _item950);
    }
    _m_MatchSite_write(out, value.site);
    out.unsigned(value.element_names.count);
    for (var _item951 in value.element_names) {
        _m_ElementName_write(out, _item951);
    }
    out.flag(value.guarded);
}

_m_MatchArmTest_read(input: RecordIn): MatchArmTest {
    var _f952 = _m_Expression_read(input);
    var _v953 = Array<CasePattern>();
    var _n954 = input.count();
    for (var _ in 0.._n954) {
        _v953.append(_m_CasePattern_read(input));
    }
    var _f955 = _v953;
    var _f956 = _m_MatchSite_read(input);
    var _v957 = Array<ElementName>();
    var _n958 = input.count();
    for (var _ in 0.._n958) {
        _v957.append(_m_ElementName_read(input));
    }
    var _f959 = _v957;
    var _f960 = input.flag();
    return MatchArmTest(_f952, _f955, _f956, _f959, _f960);
}

_m_ElementName_write(out: RecordOut, value: ElementName) {
    out.text(value.name);
    out.loc(value.loc);
    out.flag(value.declared);
    if (value.missing.is_value()) {
        out.unsigned(1);
        var (_t961, _t962) = value.missing.value();
        out.text(_t961);
        out.loc(_t962);
    } else {
        out.unsigned(0);
    }
}

_m_ElementName_read(input: RecordIn): ElementName {
    var _f963 = input.text();
    var _f964 = input.loc();
    var _f965 = input.flag();
    var _o966 = Optional<(String, Loc)>.Empty;
    if (input.unsigned() == 1) {
        var _t967 = input.text();
        var _t968 = input.loc();
        _o966 = Optional<(String, Loc)>.Value((_t967, _t968));
    }
    var _f969 = _o966;
    return ElementName(_f963, _f964, _f965, _f969);
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
    var _f970 = input.unsigned();
    var _f971 = input.loc();
    var _o972 = Optional<Loc>.Empty;
    if (input.unsigned() == 1) {
        _o972 = Optional<Loc>.Value(input.loc());
    }
    var _f973 = _o972;
    var _f974 = input.flag();
    var _f975 = input.flag();
    return MatchSite(_f970, _f971, _f973, _f974, _f975);
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
        for (var _item976 in value.bindings.value()) {
            _m_CasePattern_write(out, _item976);
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
        for (var _item977 in value.elements.value()) {
            _m_CasePattern_write(out, _item977);
        }
    } else {
        out.unsigned(0);
    }
    out.flag(value.range);
    out.flag(value.constant);
    if (value.values.is_value()) {
        out.unsigned(1);
        var (_t978, _t979) = value.values.value();
        out.signed(_t978 as long);
        out.signed(_t979 as long);
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
    var _o980 = Optional<TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o980 = Optional<TypeName>.Value(_m_TypeName_read(input));
    }
    var _f981 = _o980;
    var _f982 = input.text();
    var _f983 = input.loc();
    var _o984 = Optional<Array<CasePattern>>.Empty;
    if (input.unsigned() == 1) {
        var _v985 = Array<CasePattern>();
        var _n986 = input.count();
        for (var _ in 0.._n986) {
            _v985.append(_m_CasePattern_read(input));
        }
        _o984 = Optional<Array<CasePattern>>.Value(_v985);
    }
    var _f987 = _o984;
    var _o988 = Optional<Expression>.Empty;
    if (input.unsigned() == 1) {
        _o988 = Optional<Expression>.Value(_m_Expression_read(input));
    }
    var _f989 = _o988;
    var _o990 = Optional<Array<CasePattern>>.Empty;
    if (input.unsigned() == 1) {
        var _v991 = Array<CasePattern>();
        var _n992 = input.count();
        for (var _ in 0.._n992) {
            _v991.append(_m_CasePattern_read(input));
        }
        _o990 = Optional<Array<CasePattern>>.Value(_v991);
    }
    var _f993 = _o990;
    var _f994 = input.flag();
    var _f995 = input.flag();
    var _o996 = Optional<(long, long)>.Empty;
    if (input.unsigned() == 1) {
        var _t997 = input.signed();
        var _t998 = input.signed();
        _o996 = Optional<(long, long)>.Value((_t997, _t998));
    }
    var _f999 = _o996;
    var _o1000 = Optional<TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o1000 = Optional<TypeName>.Value(_m_TypeName_read(input));
    }
    var _f1001 = _o1000;
    return CasePattern(_f981, _f982, _f983, _f987, _f989, _f993, _f994, _f995, _f999, _f1001);
}

_m_ClosureLiteral_write(out: RecordOut, value: ClosureLiteral) {
    out.unsigned(value.parameters.count);
    for (var _item1002 in value.parameters) {
        _m_VariableDef_write(out, _item1002);
    }
    _m_TypeName_write(out, value.ty);
    _m_Block_write(out, value.body);
    out.flag(value.expression_body);
    out.loc(value.loc);
}

_m_ClosureLiteral_read(input: RecordIn): ClosureLiteral {
    var _v1003 = Array<VariableDef>();
    var _n1004 = input.count();
    for (var _ in 0.._n1004) {
        _v1003.append(_m_VariableDef_read(input));
    }
    var _f1005 = _v1003;
    var _f1006 = _m_TypeName_read(input);
    var _f1007 = _m_Block_read(input);
    var _f1008 = input.flag();
    var _f1009 = input.loc();
    return ClosureLiteral(_f1005, _f1006, _f1007, _f1008, _f1009);
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
    for (var _item1010 in value.attributes) {
        _a_Attribute_write(out, _item1010);
    }
    out.loc(value.loc);
    out.loc(value.type_loc);
    out.flag(value.is_const);
}

_m_VariableDef_read(input: RecordIn): VariableDef {
    var _f1011 = input.text();
    var _f1012 = _m_TypeName_read(input);
    var _o1013 = Optional<Expression>.Empty;
    if (input.unsigned() == 1) {
        _o1013 = Optional<Expression>.Value(_m_Expression_read(input));
    }
    var _f1014 = _o1013;
    var _f1015 = input.flag();
    var _f1016 = _m_Kind_read(input);
    var _v1017 = Array<ast.Attribute>();
    var _n1018 = input.count();
    for (var _ in 0.._n1018) {
        _v1017.append(_a_Attribute_read(input));
    }
    var _f1019 = _v1017;
    var _f1020 = input.loc();
    var _f1021 = input.loc();
    var _f1022 = input.flag();
    return VariableDef(_f1011, _f1012, _f1014, _f1015, _f1016, _f1019, _f1020, _f1021, _f1022);
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
    var _f1023 = _m_LoopBreakKind_read(input);
    var _f1024 = input.text();
    return LoopBreak(_f1023, _f1024);
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
    var _o1025 = Optional<Expression>.Empty;
    if (input.unsigned() == 1) {
        _o1025 = Optional<Expression>.Value(_m_Expression_read(input));
    }
    var _f1026 = _o1025;
    var _f1027 = input.loc();
    return ReturnStatement(_f1026, _f1027);
}

_m_While_write(out: RecordOut, value: While) {
    _m_Expression_write(out, value.condition);
    _m_Block_write(out, value.block);
    out.text(value.label);
}

_m_While_read(input: RecordIn): While {
    var _f1028 = _m_Expression_read(input);
    var _f1029 = _m_Block_read(input);
    var _f1030 = input.text();
    return While(_f1028, _f1029, _f1030);
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
    var _f1031 = _m_Expression_read(input);
    var _f1032 = _m_Block_read(input);
    var _o1033 = Optional<Block>.Empty;
    if (input.unsigned() == 1) {
        _o1033 = Optional<Block>.Value(_m_Block_read(input));
    }
    var _f1034 = _o1033;
    return Branch(_f1031, _f1032, _f1034);
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
        var _f1495 = _m_VariableDef_read(input);
        return Declaration.Variable(_f1495);
    }
    if (tag == 1) {
        var _f1496 = _m_FunctionDef_read(input);
        return Declaration.Function(_f1496);
    }
    if (tag == 2) {
        var _f1497 = _m_StructDef_read(input);
        return Declaration.Struct(_f1497);
    }
    if (tag == 3) {
        var _f1498 = _m_TraitDef_read(input);
        return Declaration.Trait(_f1498);
    }
    if (tag == 4) {
        var _f1499 = _m_ExtensionDef_read(input);
        return Declaration.Extension(_f1499);
    }
    if (tag == 5) {
        var _f1500 = _m_ExternDef_read(input);
        return Declaration.Extern(_f1500);
    }
    if (tag == 6) {
        var _f1501 = _m_TypeAliasDef_read(input);
        return Declaration.TypeAlias(_f1501);
    }
    input.fail("Declaration", tag);
    return _m_Declaration_read(input);
}

_m_TypeAliasDef_write(out: RecordOut, value: TypeAliasDef) {
    out.text(value.name);
    out.unsigned(value.generic_params.count);
    for (var _item1035 in value.generic_params) {
        _m_GenericParam_write(out, _item1035);
    }
    _m_TypeName_write(out, value.target);
    out.unsigned(value.attributes.count);
    for (var _item1036 in value.attributes) {
        _a_Attribute_write(out, _item1036);
    }
    out.loc(value.loc);
}

_m_TypeAliasDef_read(input: RecordIn): TypeAliasDef {
    var _f1037 = input.text();
    var _v1038 = Array<GenericParam>();
    var _n1039 = input.count();
    for (var _ in 0.._n1039) {
        _v1038.append(_m_GenericParam_read(input));
    }
    var _f1040 = _v1038;
    var _f1041 = _m_TypeName_read(input);
    var _v1042 = Array<ast.Attribute>();
    var _n1043 = input.count();
    for (var _ in 0.._n1043) {
        _v1042.append(_a_Attribute_read(input));
    }
    var _f1044 = _v1042;
    var _f1045 = input.loc();
    return TypeAliasDef(_f1037, _f1040, _f1041, _f1044, _f1045);
}

_m_GenericParam_write(out: RecordOut, value: GenericParam) {
    out.text(value.name);
    out.loc(value.loc);
    out.unsigned(value.bounds.count);
    for (var _item1046 in value.bounds) {
        _m_Bound_write(out, _item1046);
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
    var _f1047 = input.text();
    var _f1048 = input.loc();
    var _v1049 = Array<Bound>();
    var _n1050 = input.count();
    for (var _ in 0.._n1050) {
        _v1049.append(_m_Bound_read(input));
    }
    var _f1051 = _v1049;
    var _o1052 = Optional<TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o1052 = Optional<TypeName>.Value(_m_TypeName_read(input));
    }
    var _f1053 = _o1052;
    var _f1054 = input.loc();
    var _f1055 = input.flag();
    return GenericParam(_f1047, _f1048, _f1051, _f1053, _f1054, _f1055);
}

_m_Bound_write(out: RecordOut, value: Bound) {
    _m_TypeName_write(out, value.ty);
    out.loc(value.loc);
}

_m_Bound_read(input: RecordIn): Bound {
    var _f1056 = _m_TypeName_read(input);
    var _f1057 = input.loc();
    return Bound(_f1056, _f1057);
}

_m_ExternDef_write(out: RecordOut, value: ExternDef) {
    out.text(value.name);
    _m_TypeName_write(out, value.ty);
    out.unsigned(value.parameters.count);
    for (var _item1058 in value.parameters) {
        _m_VariableDef_write(out, _item1058);
    }
    out.flag(value.is_variadic);
    out.unsigned(value.attributes.count);
    for (var _item1059 in value.attributes) {
        _a_Attribute_write(out, _item1059);
    }
    out.loc(value.loc);
}

_m_ExternDef_read(input: RecordIn): ExternDef {
    var _f1060 = input.text();
    var _f1061 = _m_TypeName_read(input);
    var _v1062 = Array<VariableDef>();
    var _n1063 = input.count();
    for (var _ in 0.._n1063) {
        _v1062.append(_m_VariableDef_read(input));
    }
    var _f1064 = _v1062;
    var _f1065 = input.flag();
    var _v1066 = Array<ast.Attribute>();
    var _n1067 = input.count();
    for (var _ in 0.._n1067) {
        _v1066.append(_a_Attribute_read(input));
    }
    var _f1068 = _v1066;
    var _f1069 = input.loc();
    return ExternDef(_f1060, _f1061, _f1064, _f1065, _f1068, _f1069);
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
    for (var _item1070 in value.traits) {
        _m_TypeName_write(out, _item1070);
    }
    out.unsigned(value.trait_locs.count);
    for (var _item1071 in value.trait_locs) {
        out.loc(_item1071);
    }
    out.unsigned(value.restated.count);
    for (var _item1072 in value.restated) {
        var (_t1073, _t1074) = _item1072;
        out.unsigned(_t1073);
        _m_Bound_write(out, _t1074);
    }
    out.unsigned(value.methods.count);
    for (var _item1075 in value.methods) {
        _m_FunctionDef_write(out, _item1075);
    }
    out.unsigned(value.attributes.count);
    for (var _item1076 in value.attributes) {
        _a_Attribute_write(out, _item1076);
    }
    out.loc(value.loc);
    out.flag(value.is_exported);
    out.flag(value.is_private);
}

_m_ExtensionDef_read(input: RecordIn): ExtensionDef {
    var _f1077 = _m_TypeName_read(input);
    var _o1078 = Optional<String>.Empty;
    if (input.unsigned() == 1) {
        _o1078 = Optional<String>.Value(input.text());
    }
    var _f1079 = _o1078;
    var _v1080 = Array<TypeName>();
    var _n1081 = input.count();
    for (var _ in 0.._n1081) {
        _v1080.append(_m_TypeName_read(input));
    }
    var _f1082 = _v1080;
    var _v1083 = Array<Loc>();
    var _n1084 = input.count();
    for (var _ in 0.._n1084) {
        _v1083.append(input.loc());
    }
    var _f1085 = _v1083;
    var _v1086 = Array<(ulong, Bound)>();
    var _n1087 = input.count();
    for (var _ in 0.._n1087) {
        var _t1088 = input.unsigned();
        var _t1089 = _m_Bound_read(input);
        _v1086.append((_t1088, _t1089));
    }
    var _f1090 = _v1086;
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
    var _f1098 = input.flag();
    var _f1099 = input.flag();
    return ExtensionDef(_f1077, _f1079, _f1082, _f1085, _f1090, _f1093, _f1096, _f1097, _f1098, _f1099);
}

_m_TraitDef_write(out: RecordOut, value: TraitDef) {
    out.text(value.name);
    out.unsigned(value.generic_params.count);
    for (var _item1100 in value.generic_params) {
        _m_GenericParam_write(out, _item1100);
    }
    out.unsigned(value.methods.count);
    for (var _item1101 in value.methods) {
        _m_FunctionDef_write(out, _item1101);
    }
    out.unsigned(value.attributes.count);
    for (var _item1102 in value.attributes) {
        _a_Attribute_write(out, _item1102);
    }
    out.loc(value.loc);
}

_m_TraitDef_read(input: RecordIn): TraitDef {
    var _f1103 = input.text();
    var _v1104 = Array<GenericParam>();
    var _n1105 = input.count();
    for (var _ in 0.._n1105) {
        _v1104.append(_m_GenericParam_read(input));
    }
    var _f1106 = _v1104;
    var _v1107 = Array<FunctionDef>();
    var _n1108 = input.count();
    for (var _ in 0.._n1108) {
        _v1107.append(_m_FunctionDef_read(input));
    }
    var _f1109 = _v1107;
    var _v1110 = Array<ast.Attribute>();
    var _n1111 = input.count();
    for (var _ in 0.._n1111) {
        _v1110.append(_a_Attribute_read(input));
    }
    var _f1112 = _v1110;
    var _f1113 = input.loc();
    return TraitDef(_f1103, _f1106, _f1109, _f1112, _f1113);
}

_m_StructDef_write(out: RecordOut, value: StructDef) {
    out.text(value.name);
    _m_TypeName_write(out, value.ty);
    out.unsigned(value.generic_params.count);
    for (var _item1114 in value.generic_params) {
        _m_GenericParam_write(out, _item1114);
    }
    out.unsigned(value.field_members.count);
    for (var _item1115 in value.field_members) {
        _m_VariableDef_write(out, _item1115);
    }
    out.unsigned(value.method_members.count);
    for (var _item1116 in value.method_members) {
        _m_FunctionDef_write(out, _item1116);
    }
    out.unsigned(value.generic_methods.count);
    for (var _item1117 in value.generic_methods) {
        _m_FunctionDef_write(out, _item1117);
    }
    out.unsigned(value.constructors.count);
    for (var _item1118 in value.constructors) {
        _m_FunctionDef_write(out, _item1118);
    }
    _m_FunctionDef_write(out, value.destructor);
    _m_FunctionDef_write(out, value.acquire);
    _m_FunctionDef_write(out, value.release);
    out.unsigned(value.traits.count);
    for (var _item1119 in value.traits) {
        _m_TypeName_write(out, _item1119);
    }
    out.unsigned(value.attributes.count);
    for (var _item1120 in value.attributes) {
        _a_Attribute_write(out, _item1120);
    }
    out.loc(value.loc);
    if (value.enum_cases.is_value()) {
        out.unsigned(1);
        out.unsigned(value.enum_cases.value().count);
        for (var _item1121 in value.enum_cases.value()) {
            _m_EnumCaseDef_write(out, _item1121);
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
    var _f1122 = input.text();
    var _f1123 = _m_TypeName_read(input);
    var _v1124 = Array<GenericParam>();
    var _n1125 = input.count();
    for (var _ in 0.._n1125) {
        _v1124.append(_m_GenericParam_read(input));
    }
    var _f1126 = _v1124;
    var _v1127 = Array<VariableDef>();
    var _n1128 = input.count();
    for (var _ in 0.._n1128) {
        _v1127.append(_m_VariableDef_read(input));
    }
    var _f1129 = _v1127;
    var _v1130 = Array<FunctionDef>();
    var _n1131 = input.count();
    for (var _ in 0.._n1131) {
        _v1130.append(_m_FunctionDef_read_with(input, lazy));
    }
    var _f1132 = _v1130;
    var _v1133 = Array<FunctionDef>();
    var _n1134 = input.count();
    for (var _ in 0.._n1134) {
        _v1133.append(_m_FunctionDef_read(input));
    }
    var _f1135 = _v1133;
    var _v1136 = Array<FunctionDef>();
    var _n1137 = input.count();
    for (var _ in 0.._n1137) {
        _v1136.append(_m_FunctionDef_read_with(input, lazy));
    }
    var _f1138 = _v1136;
    var _f1139 = _m_FunctionDef_read_with(input, lazy);
    var _f1140 = _m_FunctionDef_read_with(input, lazy);
    var _f1141 = _m_FunctionDef_read_with(input, lazy);
    var _v1142 = Array<TypeName>();
    var _n1143 = input.count();
    for (var _ in 0.._n1143) {
        _v1142.append(_m_TypeName_read(input));
    }
    var _f1144 = _v1142;
    var _v1145 = Array<ast.Attribute>();
    var _n1146 = input.count();
    for (var _ in 0.._n1146) {
        _v1145.append(_a_Attribute_read(input));
    }
    var _f1147 = _v1145;
    var _f1148 = input.loc();
    var _o1149 = Optional<Array<EnumCaseDef>>.Empty;
    if (input.unsigned() == 1) {
        var _v1150 = Array<EnumCaseDef>();
        var _n1151 = input.count();
        for (var _ in 0.._n1151) {
            _v1150.append(_m_EnumCaseDef_read(input));
        }
        _o1149 = Optional<Array<EnumCaseDef>>.Value(_v1150);
    }
    var _f1152 = _o1149;
    return StructDef(
        _f1122, _f1123, _f1126, _f1129, _f1132, _f1135, _f1138, _f1139, _f1140, _f1141, _f1144, _f1147, _f1148, _f1152
    );
}

_m_EnumCaseDef_write(out: RecordOut, value: EnumCaseDef) {
    out.text(value.name);
    out.signed(value.value as long);
    out.unsigned(value.payload.count);
    for (var _item1153 in value.payload) {
        var (_t1154, _t1155) = _item1153;
        out.text(_t1154);
        out.loc(_t1155);
    }
    out.unsigned(value.attributes.count);
    for (var _item1156 in value.attributes) {
        _a_Attribute_write(out, _item1156);
    }
    out.loc(value.loc);
}

_m_EnumCaseDef_read(input: RecordIn): EnumCaseDef {
    var _f1157 = input.text();
    var _f1158 = input.signed();
    var _v1159 = Array<(String, Loc)>();
    var _n1160 = input.count();
    for (var _ in 0.._n1160) {
        var _t1161 = input.text();
        var _t1162 = input.loc();
        _v1159.append((_t1161, _t1162));
    }
    var _f1163 = _v1159;
    var _v1164 = Array<ast.Attribute>();
    var _n1165 = input.count();
    for (var _ in 0.._n1165) {
        _v1164.append(_a_Attribute_read(input));
    }
    var _f1166 = _v1164;
    var _f1167 = input.loc();
    return EnumCaseDef(_f1157, _f1158, _f1163, _f1166, _f1167);
}

_m_ExtensionScopes_write(out: RecordOut, value: ExtensionScopes) {
    var _keys1169 = Array<(u8[], u8[], uint)>();
    for (var _key1168 in value.prelude) {
        var _scratch1170 = out.scratch();
        _scratch1170.unsigned(_key1168 as ulong);
        var _vscratch1172 = out.scratch();
        _keys1169.append((_scratch1170.finish(), _vscratch1172.finish(), _key1168));
    }
    _keys1169.sort((a, b) => {
        var (x, xv, _) = a;
        var (y, yv, _) = b;
        var by_key = compare_bytes(x, y);
        return by_key != 0 ? by_key : compare_bytes(xv, yv);
    });
    out.unsigned(_keys1169.count);
    for (var (_bytes1171, _, _key1168) in _keys1169) {
        out.unsigned(_key1168 as ulong);
    }
    out.unsigned(value.visible.count);
    for (var _item1173 in value.visible) {
        var _keys1175 = Array<(u8[], u8[], uint)>();
        for (var _key1174 in _item1173) {
            var _scratch1176 = out.scratch();
            _scratch1176.unsigned(_key1174 as ulong);
            var _vscratch1178 = out.scratch();
            _keys1175.append((_scratch1176.finish(), _vscratch1178.finish(), _key1174));
        }
        _keys1175.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1175.count);
        for (var (_bytes1177, _, _key1174) in _keys1175) {
            out.unsigned(_key1174 as ulong);
        }
    }
    out.unsigned(value.module.count);
    for (var _item1179 in value.module) {
        if (_item1179.is_value()) {
            out.unsigned(1);
            out.unsigned(_item1179.value() as ulong);
        } else {
            out.unsigned(0);
        }
    }
}

_m_ExtensionScopes_read(input: RecordIn): ExtensionScopes {
    var _v1180 = HashSet<uint>();
    var _n1181 = input.count();
    for (var _ in 0.._n1181) {
        _v1180.insert(input.unsigned() as uint);
    }
    var _f1182 = _v1180;
    var _v1183 = Array<HashSet<uint>>();
    var _n1184 = input.count();
    for (var _ in 0.._n1184) {
        var _v1185 = HashSet<uint>();
        var _n1186 = input.count();
        for (var _ in 0.._n1186) {
            _v1185.insert(input.unsigned() as uint);
        }
        _v1183.append(_v1185);
    }
    var _f1187 = _v1183;
    var _v1188 = Array<Optional<uint>>();
    var _n1189 = input.count();
    for (var _ in 0.._n1189) {
        var _o1190 = Optional<uint>.Empty;
        if (input.unsigned() == 1) {
            _o1190 = Optional<uint>.Value(input.unsigned() as uint);
        }
        _v1188.append(_o1190);
    }
    var _f1191 = _v1188;
    return ExtensionScopes(_f1182, _f1187, _f1191);
}

_m_Conversion_write(out: RecordOut, value: Conversion) {
    out.loc(value.at);
    _m_TypeName_write(out, value.from);
    _m_TypeName_write(out, value.to);
    out.loc(value.constructor);
}

_m_Conversion_read(input: RecordIn): Conversion {
    var _f1192 = input.loc();
    var _f1193 = _m_TypeName_read(input);
    var _f1194 = _m_TypeName_read(input);
    var _f1195 = input.loc();
    return Conversion(_f1192, _f1193, _f1194, _f1195);
}

_m_TraitType_write(out: RecordOut, value: TraitType) {
    _m_TypeName_write(out, value.ty);
    out.unsigned(value.methods.count);
    for (var _item1196 in value.methods) {
        _m_FunctionDef_write(out, _item1196);
    }
}

_m_TraitType_read(input: RecordIn): TraitType {
    var _f1197 = _m_TypeName_read(input);
    var _v1198 = Array<FunctionDef>();
    var _n1199 = input.count();
    for (var _ in 0.._n1199) {
        _v1198.append(_m_FunctionDef_read(input));
    }
    var _f1200 = _v1198;
    return TraitType(_f1197, _f1200);
}

_m_UseContext_write(out: RecordOut, value: UseContext) {
    out.unsigned(value.scope.count);
    for (var _item1201 in value.scope) {
        _m_GenericParam_write(out, _item1201);
    }
    if (value.extension.is_value()) {
        out.unsigned(1);
        _m_TypeName_write(out, value.extension.value());
    } else {
        out.unsigned(0);
    }
    out.unsigned(value.conditions.count);
    for (var _item1202 in value.conditions) {
        _a_Attribute_write(out, _item1202);
    }
}

_m_UseContext_read(input: RecordIn): UseContext {
    var _v1203 = Array<GenericParam>();
    var _n1204 = input.count();
    for (var _ in 0.._n1204) {
        _v1203.append(_m_GenericParam_read(input));
    }
    var _f1205 = _v1203;
    var _o1206 = Optional<TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o1206 = Optional<TypeName>.Value(_m_TypeName_read(input));
    }
    var _f1207 = _o1206;
    var _v1208 = Array<ast.Attribute>();
    var _n1209 = input.count();
    for (var _ in 0.._n1209) {
        _v1208.append(_a_Attribute_read(input));
    }
    var _f1210 = _v1208;
    return UseContext(_f1205, _f1207, _f1210);
}

_m_TypeUse_write(out: RecordOut, value: TypeUse) {
    _m_TypeName_write(out, value.ty);
    out.unsigned(value.args.count);
    for (var _item1211 in value.args) {
        out.loc(_item1211);
    }
    out.unsigned(value.context);
}

_m_TypeUse_read(input: RecordIn): TypeUse {
    var _f1212 = _m_TypeName_read(input);
    var _v1213 = Array<Loc>();
    var _n1214 = input.count();
    for (var _ in 0.._n1214) {
        _v1213.append(input.loc());
    }
    var _f1215 = _v1213;
    var _f1216 = input.unsigned();
    return TypeUse(_f1212, _f1215, _f1216);
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
    var _f1217 = input.text();
    var _f1218 = input.text();
    var _f1219 = input.flag();
    var _f1220 = input.loc();
    var _f1221 = _m_AccessorKind_read(input);
    var _o1222 = Optional<AccessorKind>.Empty;
    if (input.unsigned() == 1) {
        _o1222 = Optional<AccessorKind>.Value(_m_AccessorKind_read(input));
    }
    var _f1223 = _o1222;
    var _f1224 = input.loc();
    var _o1225 = Optional<String>.Empty;
    if (input.unsigned() == 1) {
        _o1225 = Optional<String>.Value(input.text());
    }
    var _f1226 = _o1225;
    var _f1227 = input.flag();
    return PropertyDef(_f1217, _f1218, _f1219, _f1220, _f1221, _f1223, _f1224, _f1226, _f1227);
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
    var _f1228 = input.text();
    var _f1229 = input.text();
    var _f1230 = input.text();
    var _f1231 = input.unsigned();
    var _f1232 = _m_TypeName_read(input);
    var _f1233 = _m_TypeName_read(input);
    var _f1234 = input.loc();
    return Withheld(_f1228, _f1229, _f1230, _f1231, _f1232, _f1233, _f1234);
}

_m_EnumDef_write(out: RecordOut, value: EnumDef) {
    out.text(value.name);
    _m_TypeName_write(out, value.representation);
    out.unsigned(value.cases.count);
    for (var _item1235 in value.cases) {
        _m_EnumCaseDef_write(out, _item1235);
    }
    out.unsigned(value.attributes.count);
    for (var _item1236 in value.attributes) {
        _a_Attribute_write(out, _item1236);
    }
    out.loc(value.loc);
}

_m_EnumDef_read(input: RecordIn): EnumDef {
    var _f1237 = input.text();
    var _f1238 = _m_TypeName_read(input);
    var _v1239 = Array<EnumCaseDef>();
    var _n1240 = input.count();
    for (var _ in 0.._n1240) {
        _v1239.append(_m_EnumCaseDef_read(input));
    }
    var _f1241 = _v1239;
    var _v1242 = Array<ast.Attribute>();
    var _n1243 = input.count();
    for (var _ in 0.._n1243) {
        _v1242.append(_a_Attribute_read(input));
    }
    var _f1244 = _v1242;
    var _f1245 = input.loc();
    return EnumDef(_f1237, _f1238, _f1241, _f1244, _f1245);
}

_m_ModuleStaticBlock_write(out: RecordOut, value: ModuleStaticBlock) {
    _m_StaticBlock_write(out, value.block);
    out.unsigned(value.constants.count);
    for (var _item1246 in value.constants) {
        var (_t1247, _t1248) = _item1246;
        out.text(_t1247);
        out.loc(_t1248);
    }
}

_m_ModuleStaticBlock_read(input: RecordIn): ModuleStaticBlock {
    var _f1249 = _m_StaticBlock_read(input);
    var _v1250 = Array<(String, Loc)>();
    var _n1251 = input.count();
    for (var _ in 0.._n1251) {
        var _t1252 = input.text();
        var _t1253 = input.loc();
        _v1250.append((_t1252, _t1253));
    }
    var _f1254 = _v1250;
    return ModuleStaticBlock(_f1249, _f1254);
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
        for (var _item1255 in value.symbols.value()) {
            _a_ImportedSymbol_write(out, _item1255);
        }
    } else {
        out.unsigned(0);
    }
    out.flag(value.reexport);
    out.unsigned(value.attributes.count);
    for (var _item1256 in value.attributes) {
        _a_Attribute_write(out, _item1256);
    }
    out.unsigned(out.blank_locs ? 0 : value.span.start);
    out.unsigned(out.blank_locs ? 0 : value.span.end);
}

_a_Import_read(input: RecordIn): ast.Import {
    var _f1257 = input.text();
    var _s1258 = input.unsigned();
    var _f1259 = ast.Span(_s1258, input.unsigned());
    var _o1260 = Optional<String>.Empty;
    if (input.unsigned() == 1) {
        _o1260 = Optional<String>.Value(input.text());
    }
    var _f1261 = _o1260;
    var _f1262 = input.flag();
    var _o1263 = Optional<Array<ast.ImportedSymbol>>.Empty;
    if (input.unsigned() == 1) {
        var _v1264 = Array<ast.ImportedSymbol>();
        var _n1265 = input.count();
        for (var _ in 0.._n1265) {
            _v1264.append(_a_ImportedSymbol_read(input));
        }
        _o1263 = Optional<Array<ast.ImportedSymbol>>.Value(_v1264);
    }
    var _f1266 = _o1263;
    var _f1267 = input.flag();
    var _v1268 = Array<ast.Attribute>();
    var _n1269 = input.count();
    for (var _ in 0.._n1269) {
        _v1268.append(_a_Attribute_read(input));
    }
    var _f1270 = _v1268;
    var _s1271 = input.unsigned();
    var _f1272 = ast.Span(_s1271, input.unsigned());
    var value = ast.Import();
    value.name = _f1257;
    value.name_span = _f1259;
    value.alias = _f1261;
    value.is_local = _f1262;
    value.symbols = _f1266;
    value.reexport = _f1267;
    value.attributes = _f1270;
    value.span = _f1272;
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
    var _f1273 = input.text();
    var _s1274 = input.unsigned();
    var _f1275 = ast.Span(_s1274, input.unsigned());
    var _o1276 = Optional<String>.Empty;
    if (input.unsigned() == 1) {
        _o1276 = Optional<String>.Value(input.text());
    }
    var _f1277 = _o1276;
    var _s1278 = input.unsigned();
    var _f1279 = ast.Span(_s1278, input.unsigned());
    var value = ast.ImportedSymbol();
    value.name = _f1273;
    value.name_span = _f1275;
    value.alias = _f1277;
    value.span = _f1279;
    return value;
}

_m_Module_write_delta(out: RecordOut, value: Module, base: DeltaBase) {
    ulong _mark = out.values.count;
    var _hs1507 = Array<String>();
    for (var _item1502 in value.imports) {
        var scratch = base.scratch();
        _a_Import_write(scratch, _item1502);
        _hs1507.append(base.hash_of(scratch));
    }
    var _seq1508 = base.sequence("imports");
    ulong _bj1509 = 0;
    var _news1510 = Array<ulong>();
    for (var _i1511 in 0.._hs1507.count) {
        if (_bj1509 < _seq1508.count and _hs1507[_i1511] == _seq1508[_bj1509]) {
            _bj1509 += 1;
        } else {
            _news1510.append(_i1511);
        }
    }
    if (_bj1509 == _seq1508.count) {
        out.unsigned(2);
        out.unsigned(_news1510.count);
        for (var _i1511 in _news1510) {
            out.unsigned(_i1511);
            _a_Import_write(out, value.imports[_i1511]);
            {
                var _own1512 = RecordOut();
                _own1512.blank_bodies = true;
                _own1512.blank_locs = true;
                _own1512.pending_as_bytes = true;
                _a_Import_write(_own1512, value.imports[_i1511]);
                base.own("imports", interface_text(_own1512));
            }
        }
        base.count("imports" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("imports" + " whole", 0);
        out.unsigned(value.imports.count);
        for (var _i1511 in 0..value.imports.count) {
            _a_Import_write(out, value.imports[_i1511]);
            {
                var _own1513 = RecordOut();
                _own1513.blank_bodies = true;
                _own1513.blank_locs = true;
                _own1513.pending_as_bytes = true;
                _a_Import_write(_own1513, value.imports[_i1511]);
                base.own("imports", interface_text(_own1513));
            }
        }
    }
    base.stat("imports", out.values.count - _mark);
    _mark = out.values.count;
    var _seq1523 = base.ref_structs;
    ulong _bj1524 = 0;
    var _news1526 = Array<ulong>();
    var _patches1527 = Array<(ulong, ulong)>();
    for (var _i1528 in 0..value.structs.count) {
        if (_bj1524 < _seq1523.count
            and value.structs[_i1528] === _seq1523[_bj1524]
            and !value.extended_checked.contains(value.structs[_i1528].name)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_StructDef_write(scratch, value.structs[_i1528]);
                base.verify_same("s", _bj1524, scratch, value.structs[_i1528].name);
            }
            _bj1524 += 1;
        } else if (_bj1524 < _seq1523.count
            and !(value.structs[_i1528] === _seq1523[_bj1524])
            and _same_m_StructDef(value.structs[_i1528], _seq1523[_bj1524], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_StructDef_write(scratch, value.structs[_i1528]);
                base.verify_same("s", _bj1524, scratch, value.structs[_i1528].name);
            }
            _bj1524 += 1;
        } else if (_bj1524 < _seq1523.count and value.structs[_i1528].name == _seq1523[_bj1524].name) {
            _patches1527.append((_i1528, _bj1524));
            _bj1524 += 1;
        } else {
            _news1526.append(_i1528);
        }
    }
    if (_bj1524 == _seq1523.count) {
        out.unsigned(2);
        out.unsigned(_patches1527.count);
        for (var (_i1528, _b) in _patches1527) {
            ulong _before = out.values.count;
            out.text(value.structs[_i1528].name);
            out.unsigned(_b);
            _patch_s_write(out, value.structs[_i1528], base, _b);
            base.count("s patched", out.values.count - _before);
            {
                var _own1529 = RecordOut();
                _own1529.blank_bodies = true;
                _own1529.blank_locs = true;
                _own1529.pending_as_bytes = true;
                var _s1530 = value.structs[_i1528];
                var _methods1531 = _s1530.method_members;
                _s1530.method_members = Array<FunctionDef>();
                var _fields1532 = _s1530.field_members;
                var split__fields1532 = splits_fields(_s1530);
                if (split__fields1532) {
                    _s1530.field_members = Array<VariableDef>();
                }
                _m_StructDef_write(_own1529, _s1530);
                _s1530.method_members = _methods1531;
                _s1530.field_members = _fields1532;
                base.own_named("structs", _s1530.name, interface_text(_own1529));
                for (var _m1533 in _methods1531) {
                    var _own1534 = RecordOut();
                    _own1534.blank_bodies = true;
                    _own1534.blank_locs = true;
                    _own1534.pending_as_bytes = true;
                    _m_FunctionDef_write(_own1534, _m1533);
                    base.own_method("structs", _s1530.name, _m1533.name, interface_text(_own1534));
                }
                if (_s1530.is_value()) {
                    for (var _m1533 in _s1530.constructors) {
                        var _own1534 = RecordOut();
                        _own1534.blank_locs = true;
                        _own1534.pending_as_bytes = true;
                        _m_FunctionDef_write(_own1534, _m1533);
                        base.own_method("structs", _s1530.name, "__ctor", interface_text(_own1534));
                    }
                }
                if (split__fields1532) {
                    var _order1536 = StringBuilder();
                    for (var _f1535 in _fields1532) {
                        var _own1537 = RecordOut();
                        _own1537.blank_locs = true;
                        _m_VariableDef_write(_own1537, _f1535);
                        base.own_method("structs", _s1530.name, "." + _f1535.name, interface_text(_own1537));
                        _order1536.append(_f1535.name);
                        _order1536.append(",");
                    }
                    base.own_method("structs", _s1530.name, ".#order", _order1536.to_string());
                }
            }
        }
        out.unsigned(_news1526.count);
        for (var _i1528 in _news1526) {
            ulong _before = out.values.count;
            out.unsigned(_i1528);
            _m_StructDef_write(out, value.structs[_i1528]);
            base.count("s new", out.values.count - _before);
            {
                var _own1538 = RecordOut();
                _own1538.blank_bodies = true;
                _own1538.blank_locs = true;
                _own1538.pending_as_bytes = true;
                var _s1539 = value.structs[_i1528];
                var _methods1540 = _s1539.method_members;
                _s1539.method_members = Array<FunctionDef>();
                var _fields1541 = _s1539.field_members;
                var split__fields1541 = splits_fields(_s1539);
                if (split__fields1541) {
                    _s1539.field_members = Array<VariableDef>();
                }
                _m_StructDef_write(_own1538, _s1539);
                _s1539.method_members = _methods1540;
                _s1539.field_members = _fields1541;
                base.own_named("structs", _s1539.name, interface_text(_own1538));
                for (var _m1542 in _methods1540) {
                    var _own1543 = RecordOut();
                    _own1543.blank_bodies = true;
                    _own1543.blank_locs = true;
                    _own1543.pending_as_bytes = true;
                    _m_FunctionDef_write(_own1543, _m1542);
                    base.own_method("structs", _s1539.name, _m1542.name, interface_text(_own1543));
                }
                if (_s1539.is_value()) {
                    for (var _m1542 in _s1539.constructors) {
                        var _own1543 = RecordOut();
                        _own1543.blank_locs = true;
                        _own1543.pending_as_bytes = true;
                        _m_FunctionDef_write(_own1543, _m1542);
                        base.own_method("structs", _s1539.name, "__ctor", interface_text(_own1543));
                    }
                }
                if (split__fields1541) {
                    var _order1545 = StringBuilder();
                    for (var _f1544 in _fields1541) {
                        var _own1546 = RecordOut();
                        _own1546.blank_locs = true;
                        _m_VariableDef_write(_own1546, _f1544);
                        base.own_method("structs", _s1539.name, "." + _f1544.name, interface_text(_own1546));
                        _order1545.append(_f1544.name);
                        _order1545.append(",");
                    }
                    base.own_method("structs", _s1539.name, ".#order", _order1545.to_string());
                }
            }
        }
        base.count("s merged", 0);
    } else {
        out.unsigned(1);
        base.count("s by place", 0);
        var _struct_hits1522 = HashSet<long>();
        var _slots1525 = HashMap<String, long>();
        for (var _i1528 in 0.._seq1523.count) {
            if (!_slots1525.contains(_seq1523[_i1528].name)) {
                _slots1525[_seq1523[_i1528].name] = _i1528 as long;
            }
        }
        out.unsigned(value.structs.count);
        for (var _i1528 in 0..value.structs.count) {
            var _item1521 = value.structs[_i1528];
            var _slot = _slots1525.try_get(_item1521.name);
            long named = _slot.is_value() ? _slot.value() : -1;
            long at = -1;
            if (named >= 0
                and _seq1523[named as ulong] === _item1521
                and !value.extended_checked.contains(_item1521.name)) {
                at = named;
            }
            ulong _before = out.values.count;
            if (at >= 0) {
                _struct_hits1522.insert(at);
                out.unsigned((at as ulong) * 2 + 1);
            } else if (named >= 0) {
                _struct_hits1522.insert(named);
                out.unsigned(2);
                out.unsigned(named as ulong);
                _patch_s_write(out, _item1521, base, named as ulong);
                base.count("s patched", out.values.count - _before);
            } else {
                out.unsigned(0);
                _m_StructDef_write(out, _item1521);
                base.count("s new", out.values.count - _before);
            }
        }
        base.missed("s", "s", _struct_hits1522.count);
    }
    base.stat("structs", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1560 = Array<String>();
    for (var _item1555 in value.traits) {
        var scratch = base.scratch();
        _m_TraitDef_write(scratch, _item1555);
        _hs1560.append(base.hash_of(scratch));
    }
    var _seq1561 = base.sequence("traits");
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
            _m_TraitDef_write(out, value.traits[_i1564]);
            {
                var _own1565 = RecordOut();
                _own1565.blank_bodies = false;
                _own1565.blank_locs = true;
                _own1565.pending_as_bytes = true;
                _m_TraitDef_write(_own1565, value.traits[_i1564]);
                base.own("traits", interface_text(_own1565));
            }
        }
        base.count("traits" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("traits" + " whole", 0);
        out.unsigned(value.traits.count);
        for (var _i1564 in 0..value.traits.count) {
            _m_TraitDef_write(out, value.traits[_i1564]);
            {
                var _own1566 = RecordOut();
                _own1566.blank_bodies = false;
                _own1566.blank_locs = true;
                _own1566.pending_as_bytes = true;
                _m_TraitDef_write(_own1566, value.traits[_i1564]);
                base.own("traits", interface_text(_own1566));
            }
        }
    }
    base.stat("traits", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1579 = Array<String>();
    for (var _item1574 in value.extensions) {
        var scratch = base.scratch();
        _m_ExtensionDef_write(scratch, _item1574);
        _hs1579.append(base.hash_of(scratch));
    }
    var _seq1580 = base.sequence("extensions");
    ulong _bj1581 = 0;
    var _news1582 = Array<ulong>();
    for (var _i1583 in 0.._hs1579.count) {
        if (_bj1581 < _seq1580.count and _hs1579[_i1583] == _seq1580[_bj1581]) {
            _bj1581 += 1;
        } else {
            _news1582.append(_i1583);
        }
    }
    if (_bj1581 == _seq1580.count) {
        out.unsigned(2);
        out.unsigned(_news1582.count);
        for (var _i1583 in _news1582) {
            out.unsigned(_i1583);
            _m_ExtensionDef_write(out, value.extensions[_i1583]);
            {
                var _own1584 = RecordOut();
                _own1584.blank_bodies = true;
                _own1584.blank_locs = true;
                _own1584.pending_as_bytes = true;
                _m_ExtensionDef_write(_own1584, value.extensions[_i1583]);
                base.own("extensions", interface_text(_own1584));
            }
        }
        base.count("extensions" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("extensions" + " whole", 0);
        out.unsigned(value.extensions.count);
        for (var _i1583 in 0..value.extensions.count) {
            _m_ExtensionDef_write(out, value.extensions[_i1583]);
            {
                var _own1585 = RecordOut();
                _own1585.blank_bodies = true;
                _own1585.blank_locs = true;
                _own1585.pending_as_bytes = true;
                _m_ExtensionDef_write(_own1585, value.extensions[_i1583]);
                base.own("extensions", interface_text(_own1585));
            }
        }
    }
    base.stat("extensions", out.values.count - _mark);
    _mark = out.values.count;
    var _seq1598 = base.ref_functions;
    ulong _bj1599 = 0;
    var _news1600 = Array<ulong>();
    var _changed1594 = Array<(ulong, ulong)>();
    for (var _i1601 in 0..value.functions.count) {
        if (_bj1599 < _seq1598.count and value.functions[_i1601] === _seq1598[_bj1599]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.functions[_i1601]);
                base.verify_same("functions", _bj1599, scratch);
            }
            _bj1599 += 1;
        } else if (_bj1599 < _seq1598.count and _same_m_FunctionDef(value.functions[_i1601], _seq1598[_bj1599], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.functions[_i1601]);
                base.verify_same("functions", _bj1599, scratch);
            }
            _bj1599 += 1;
        } else if (_bj1599 < _seq1598.count and value.functions[_i1601].name == _seq1598[_bj1599].name) {
            _changed1594.append((_i1601, _bj1599));
            _bj1599 += 1;
        } else {
            _news1600.append(_i1601);
        }
    }
    if (_bj1599 == _seq1598.count) {
        out.unsigned(2);
        out.unsigned(_changed1594.count);
        for (var (_i1601, _b) in _changed1594) {
            out.text(value.functions[_i1601].name);
            out.unsigned(_b);
            _m_FunctionDef_write(out, value.functions[_i1601]);
            {
                var _own1602 = RecordOut();
                _own1602.blank_bodies = true;
                _own1602.blank_locs = true;
                _own1602.pending_as_bytes = true;
                _m_FunctionDef_write(_own1602, value.functions[_i1601]);
                base.own_function("functions", value.functions[_i1601], interface_text(_own1602));
            }
        }
        base.count("functions" + " changed", _changed1594.count);
        out.unsigned(_news1600.count);
        for (var _i1601 in _news1600) {
            out.unsigned(_i1601);
            _m_FunctionDef_write(out, value.functions[_i1601]);
            {
                var _own1603 = RecordOut();
                _own1603.blank_bodies = true;
                _own1603.blank_locs = true;
                _own1603.pending_as_bytes = true;
                _m_FunctionDef_write(_own1603, value.functions[_i1601]);
                base.own_function("functions", value.functions[_i1601], interface_text(_own1603));
            }
        }
        base.count("functions" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("functions" + " whole", 0);
        out.unsigned(value.functions.count);
        for (var _i1601 in 0..value.functions.count) {
            _m_FunctionDef_write(out, value.functions[_i1601]);
            {
                var _own1604 = RecordOut();
                _own1604.blank_bodies = true;
                _own1604.blank_locs = true;
                _own1604.pending_as_bytes = true;
                _m_FunctionDef_write(_own1604, value.functions[_i1601]);
                base.own_function("functions", value.functions[_i1601], interface_text(_own1604));
            }
        }
    }
    base.stat("functions", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1617 = Array<String>();
    for (var _item1612 in value.externs) {
        var scratch = base.scratch();
        _m_ExternDef_write(scratch, _item1612);
        _hs1617.append(base.hash_of(scratch));
    }
    var _seq1618 = base.sequence("externs");
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
            _m_ExternDef_write(out, value.externs[_i1621]);
            {
                var _own1622 = RecordOut();
                _own1622.blank_bodies = true;
                _own1622.blank_locs = true;
                _own1622.pending_as_bytes = true;
                _m_ExternDef_write(_own1622, value.externs[_i1621]);
                base.own("externs", interface_text(_own1622));
            }
        }
        base.count("externs" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("externs" + " whole", 0);
        out.unsigned(value.externs.count);
        for (var _i1621 in 0..value.externs.count) {
            _m_ExternDef_write(out, value.externs[_i1621]);
            {
                var _own1623 = RecordOut();
                _own1623.blank_bodies = true;
                _own1623.blank_locs = true;
                _own1623.pending_as_bytes = true;
                _m_ExternDef_write(_own1623, value.externs[_i1621]);
                base.own("externs", interface_text(_own1623));
            }
        }
    }
    base.stat("externs", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1636 = Array<String>();
    for (var _item1631 in value.globals) {
        var scratch = base.scratch();
        _m_VariableDef_write(scratch, _item1631);
        _hs1636.append(base.hash_of(scratch));
    }
    var _seq1637 = base.sequence("globals");
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
            _m_VariableDef_write(out, value.globals[_i1640]);
            {
                var _own1641 = RecordOut();
                _own1641.blank_bodies = true;
                _own1641.blank_locs = true;
                _own1641.pending_as_bytes = true;
                _m_VariableDef_write(_own1641, value.globals[_i1640]);
                base.own("globals", interface_text(_own1641));
            }
        }
        base.count("globals" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("globals" + " whole", 0);
        out.unsigned(value.globals.count);
        for (var _i1640 in 0..value.globals.count) {
            _m_VariableDef_write(out, value.globals[_i1640]);
            {
                var _own1642 = RecordOut();
                _own1642.blank_bodies = true;
                _own1642.blank_locs = true;
                _own1642.pending_as_bytes = true;
                _m_VariableDef_write(_own1642, value.globals[_i1640]);
                base.own("globals", interface_text(_own1642));
            }
        }
    }
    base.stat("globals", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1655 = Array<String>();
    for (var _item1650 in value.static_blocks) {
        var scratch = base.scratch();
        _m_ModuleStaticBlock_write(scratch, _item1650);
        _hs1655.append(base.hash_of(scratch));
    }
    var _seq1656 = base.sequence("static_blocks");
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
            _m_ModuleStaticBlock_write(out, value.static_blocks[_i1659]);
            {
                var _own1660 = RecordOut();
                _own1660.blank_bodies = true;
                _own1660.blank_locs = true;
                _own1660.pending_as_bytes = true;
                _m_ModuleStaticBlock_write(_own1660, value.static_blocks[_i1659]);
                base.own("static_blocks", interface_text(_own1660));
            }
        }
        base.count("static_blocks" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("static_blocks" + " whole", 0);
        out.unsigned(value.static_blocks.count);
        for (var _i1659 in 0..value.static_blocks.count) {
            _m_ModuleStaticBlock_write(out, value.static_blocks[_i1659]);
            {
                var _own1661 = RecordOut();
                _own1661.blank_bodies = true;
                _own1661.blank_locs = true;
                _own1661.pending_as_bytes = true;
                _m_ModuleStaticBlock_write(_own1661, value.static_blocks[_i1659]);
                base.own("static_blocks", interface_text(_own1661));
            }
        }
    }
    base.stat("static_blocks", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1674 = Array<String>();
    for (var _item1669 in value.enums) {
        var scratch = base.scratch();
        _m_EnumDef_write(scratch, _item1669);
        _hs1674.append(base.hash_of(scratch));
    }
    var _seq1675 = base.sequence("enums");
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
            _m_EnumDef_write(out, value.enums[_i1678]);
            {
                var _own1679 = RecordOut();
                _own1679.blank_bodies = true;
                _own1679.blank_locs = true;
                _own1679.pending_as_bytes = true;
                _m_EnumDef_write(_own1679, value.enums[_i1678]);
                base.own_named("enums", value.enums[_i1678].name, interface_text(_own1679));
            }
        }
        base.count("enums" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("enums" + " whole", 0);
        out.unsigned(value.enums.count);
        for (var _i1678 in 0..value.enums.count) {
            _m_EnumDef_write(out, value.enums[_i1678]);
            {
                var _own1680 = RecordOut();
                _own1680.blank_bodies = true;
                _own1680.blank_locs = true;
                _own1680.pending_as_bytes = true;
                _m_EnumDef_write(_own1680, value.enums[_i1678]);
                base.own_named("enums", value.enums[_i1678].name, interface_text(_own1680));
            }
        }
    }
    base.stat("enums", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1693 = Array<String>();
    for (var _item1688 in value.struct_specs) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item1688);
        _hs1693.append(base.hash_of(scratch));
    }
    var _seq1694 = base.sequence("struct_specs");
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
            _m_TypeName_write(out, value.struct_specs[_i1697]);
            {
                var _own1698 = RecordOut();
                _own1698.blank_bodies = true;
                _own1698.blank_locs = true;
                _own1698.pending_as_bytes = true;
                _m_TypeName_write(_own1698, value.struct_specs[_i1697]);
                base.own("struct_specs", interface_text(_own1698));
            }
        }
        base.count("struct_specs" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("struct_specs" + " whole", 0);
        out.unsigned(value.struct_specs.count);
        for (var _i1697 in 0..value.struct_specs.count) {
            _m_TypeName_write(out, value.struct_specs[_i1697]);
            {
                var _own1699 = RecordOut();
                _own1699.blank_bodies = true;
                _own1699.blank_locs = true;
                _own1699.pending_as_bytes = true;
                _m_TypeName_write(_own1699, value.struct_specs[_i1697]);
                base.own("struct_specs", interface_text(_own1699));
            }
        }
    }
    base.stat("struct_specs", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1712 = Array<String>();
    for (var _item1707 in value.func_specs) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item1707);
        _hs1712.append(base.hash_of(scratch));
    }
    var _seq1713 = base.sequence("func_specs");
    ulong _bj1714 = 0;
    var _news1715 = Array<ulong>();
    for (var _i1716 in 0.._hs1712.count) {
        if (_bj1714 < _seq1713.count and _hs1712[_i1716] == _seq1713[_bj1714]) {
            _bj1714 += 1;
        } else {
            _news1715.append(_i1716);
        }
    }
    if (_bj1714 == _seq1713.count) {
        out.unsigned(2);
        out.unsigned(_news1715.count);
        for (var _i1716 in _news1715) {
            out.unsigned(_i1716);
            _m_TypeName_write(out, value.func_specs[_i1716]);
            {
                var _own1717 = RecordOut();
                _own1717.blank_bodies = true;
                _own1717.blank_locs = true;
                _own1717.pending_as_bytes = true;
                _m_TypeName_write(_own1717, value.func_specs[_i1716]);
                base.own("func_specs", interface_text(_own1717));
            }
        }
        base.count("func_specs" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("func_specs" + " whole", 0);
        out.unsigned(value.func_specs.count);
        for (var _i1716 in 0..value.func_specs.count) {
            _m_TypeName_write(out, value.func_specs[_i1716]);
            {
                var _own1718 = RecordOut();
                _own1718.blank_bodies = true;
                _own1718.blank_locs = true;
                _own1718.pending_as_bytes = true;
                _m_TypeName_write(_own1718, value.func_specs[_i1716]);
                base.own("func_specs", interface_text(_own1718));
            }
        }
    }
    base.stat("func_specs", out.values.count - _mark);
    _mark = out.values.count;
    var _hits1730 = HashSet<long>();
    out.unsigned(value.type_aliases.count);
    for (var _item1726 in value.type_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1726);
        var hash = base.hash_of(scratch);
        var at = base.find_hashed("type_aliases", hash);
        if (at >= 0) {
            _hits1730.insert(at);
            out.unsigned((at as ulong) * 2 + 1);
        } else {
            out.unsigned(0);
            _m_TypeAliasDef_write(out, _item1726);
        }
    }
    base.missed("type_aliases", "type_aliases", _hits1730.count);
    base.stat("type_aliases", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1740 = Array<String>();
    for (var _item1735 in value.withheld) {
        var scratch = base.scratch();
        _m_Withheld_write(scratch, _item1735);
        _hs1740.append(base.hash_of(scratch));
    }
    var _seq1741 = base.sequence("withheld");
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
            _m_Withheld_write(out, value.withheld[_i1744]);
            {
                var _own1745 = RecordOut();
                _own1745.blank_bodies = true;
                _own1745.blank_locs = true;
                _own1745.pending_as_bytes = true;
                _m_Withheld_write(_own1745, value.withheld[_i1744]);
                base.own("withheld", interface_text(_own1745));
            }
        }
        base.count("withheld" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("withheld" + " whole", 0);
        out.unsigned(value.withheld.count);
        for (var _i1744 in 0..value.withheld.count) {
            _m_Withheld_write(out, value.withheld[_i1744]);
            {
                var _own1746 = RecordOut();
                _own1746.blank_bodies = true;
                _own1746.blank_locs = true;
                _own1746.pending_as_bytes = true;
                _m_Withheld_write(_own1746, value.withheld[_i1744]);
                base.own("withheld", interface_text(_own1746));
            }
        }
    }
    base.stat("withheld", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1759 = Array<String>();
    for (var _item1754 in value.properties) {
        var scratch = base.scratch();
        _m_PropertyDef_write(scratch, _item1754);
        _hs1759.append(base.hash_of(scratch));
    }
    var _seq1760 = base.sequence("properties");
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
            _m_PropertyDef_write(out, value.properties[_i1763]);
            {
                var _own1764 = RecordOut();
                _own1764.blank_bodies = true;
                _own1764.blank_locs = true;
                _own1764.pending_as_bytes = true;
                _m_PropertyDef_write(_own1764, value.properties[_i1763]);
                base.own("properties", interface_text(_own1764));
            }
        }
        base.count("properties" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("properties" + " whole", 0);
        out.unsigned(value.properties.count);
        for (var _i1763 in 0..value.properties.count) {
            _m_PropertyDef_write(out, value.properties[_i1763]);
            {
                var _own1765 = RecordOut();
                _own1765.blank_bodies = true;
                _own1765.blank_locs = true;
                _own1765.pending_as_bytes = true;
                _m_PropertyDef_write(_own1765, value.properties[_i1763]);
                base.own("properties", interface_text(_own1765));
            }
        }
    }
    base.stat("properties", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1778 = Array<String>();
    for (var _item1773 in value.type_uses) {
        var scratch = base.scratch();
        _m_TypeUse_write(scratch, _item1773);
        _hs1778.append(base.hash_of(scratch));
    }
    var _seq1779 = base.sequence("type_uses");
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
            _m_TypeUse_write(out, value.type_uses[_i1782]);
            {
                var _own1783 = RecordOut();
                _own1783.blank_bodies = true;
                _own1783.blank_locs = true;
                _own1783.pending_as_bytes = true;
                _m_TypeUse_write(_own1783, value.type_uses[_i1782]);
                base.own("type_uses", interface_text(_own1783));
            }
        }
        base.count("type_uses" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("type_uses" + " whole", 0);
        out.unsigned(value.type_uses.count);
        for (var _i1782 in 0..value.type_uses.count) {
            _m_TypeUse_write(out, value.type_uses[_i1782]);
            {
                var _own1784 = RecordOut();
                _own1784.blank_bodies = true;
                _own1784.blank_locs = true;
                _own1784.pending_as_bytes = true;
                _m_TypeUse_write(_own1784, value.type_uses[_i1782]);
                base.own("type_uses", interface_text(_own1784));
            }
        }
    }
    base.stat("type_uses", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1797 = Array<String>();
    for (var _item1792 in value.use_contexts) {
        var scratch = base.scratch();
        _m_UseContext_write(scratch, _item1792);
        _hs1797.append(base.hash_of(scratch));
    }
    var _seq1798 = base.sequence("use_contexts");
    ulong _bj1799 = 0;
    var _news1800 = Array<ulong>();
    for (var _i1801 in 0.._hs1797.count) {
        if (_bj1799 < _seq1798.count and _hs1797[_i1801] == _seq1798[_bj1799]) {
            _bj1799 += 1;
        } else {
            _news1800.append(_i1801);
        }
    }
    if (_bj1799 == _seq1798.count) {
        out.unsigned(2);
        out.unsigned(_news1800.count);
        for (var _i1801 in _news1800) {
            out.unsigned(_i1801);
            _m_UseContext_write(out, value.use_contexts[_i1801]);
            {
                var _own1802 = RecordOut();
                _own1802.blank_bodies = true;
                _own1802.blank_locs = true;
                _own1802.pending_as_bytes = true;
                _m_UseContext_write(_own1802, value.use_contexts[_i1801]);
                base.own("use_contexts", interface_text(_own1802));
            }
        }
        base.count("use_contexts" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("use_contexts" + " whole", 0);
        out.unsigned(value.use_contexts.count);
        for (var _i1801 in 0..value.use_contexts.count) {
            _m_UseContext_write(out, value.use_contexts[_i1801]);
            {
                var _own1803 = RecordOut();
                _own1803.blank_bodies = true;
                _own1803.blank_locs = true;
                _own1803.pending_as_bytes = true;
                _m_UseContext_write(_own1803, value.use_contexts[_i1801]);
                base.own("use_contexts", interface_text(_own1803));
            }
        }
    }
    base.stat("use_contexts", out.values.count - _mark);
    _mark = out.values.count;
    var _n1813 = base.size("literal_args");
    var _scratch1812 = base.scratch();
    if (value.literal_args.count >= _n1813) {
        for (var _i1814 in 0.._n1813) {
            var (_t1815, _t1816, _t1817) = value.literal_args[_i1814];
            _scratch1812.loc(_t1815);
            _scratch1812.unsigned(_t1816);
            _scratch1812.loc(_t1817);
        }
    }
    if (value.literal_args.count >= _n1813 and base.same_list("literal_args", _scratch1812)) {
        out.unsigned(1);
        out.unsigned(_n1813);
        out.unsigned(value.literal_args.count - _n1813);
        for (var _i1814 in _n1813..value.literal_args.count) {
            var (_t1818, _t1819, _t1820) = value.literal_args[_i1814];
            out.loc(_t1818);
            out.unsigned(_t1819);
            out.loc(_t1820);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.literal_args.count);
        for (var _item1821 in value.literal_args) {
            var (_t1822, _t1823, _t1824) = _item1821;
            out.loc(_t1822);
            out.unsigned(_t1823);
            out.loc(_t1824);
        }
        base.count("literal_args whole", 0);
    }
    base.stat("literal_args", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1847 = Array<String>();
    for (var _item1842 in value.constrained_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1842);
        _hs1847.append(base.hash_of(scratch));
    }
    var _seq1848 = base.sequence("constrained_aliases");
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
            _m_TypeAliasDef_write(out, value.constrained_aliases[_i1851]);
            {
                var _own1852 = RecordOut();
                _own1852.blank_bodies = true;
                _own1852.blank_locs = true;
                _own1852.pending_as_bytes = true;
                _m_TypeAliasDef_write(_own1852, value.constrained_aliases[_i1851]);
                base.own("constrained_aliases", interface_text(_own1852));
            }
        }
        base.count("constrained_aliases" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("constrained_aliases" + " whole", 0);
        out.unsigned(value.constrained_aliases.count);
        for (var _i1851 in 0..value.constrained_aliases.count) {
            _m_TypeAliasDef_write(out, value.constrained_aliases[_i1851]);
            {
                var _own1853 = RecordOut();
                _own1853.blank_bodies = true;
                _own1853.blank_locs = true;
                _own1853.pending_as_bytes = true;
                _m_TypeAliasDef_write(_own1853, value.constrained_aliases[_i1851]);
                base.own("constrained_aliases", interface_text(_own1853));
            }
        }
    }
    base.stat("constrained_aliases", out.values.count - _mark);
    _mark = out.values.count;
    var _hs1866 = Array<String>();
    for (var _item1861 in value.trait_types) {
        var scratch = base.scratch();
        _m_TraitType_write(scratch, _item1861);
        _hs1866.append(base.hash_of(scratch));
    }
    var _seq1867 = base.sequence("trait_types");
    ulong _bj1868 = 0;
    var _news1869 = Array<ulong>();
    for (var _i1870 in 0.._hs1866.count) {
        if (_bj1868 < _seq1867.count and _hs1866[_i1870] == _seq1867[_bj1868]) {
            _bj1868 += 1;
        } else {
            _news1869.append(_i1870);
        }
    }
    if (_bj1868 == _seq1867.count) {
        out.unsigned(2);
        out.unsigned(_news1869.count);
        for (var _i1870 in _news1869) {
            out.unsigned(_i1870);
            _m_TraitType_write(out, value.trait_types[_i1870]);
            {
                var _own1871 = RecordOut();
                _own1871.blank_bodies = true;
                _own1871.blank_locs = true;
                _own1871.pending_as_bytes = true;
                _m_TraitType_write(_own1871, value.trait_types[_i1870]);
                base.own("trait_types", interface_text(_own1871));
            }
        }
        base.count("trait_types" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("trait_types" + " whole", 0);
        out.unsigned(value.trait_types.count);
        for (var _i1870 in 0..value.trait_types.count) {
            _m_TraitType_write(out, value.trait_types[_i1870]);
            {
                var _own1872 = RecordOut();
                _own1872.blank_bodies = true;
                _own1872.blank_locs = true;
                _own1872.pending_as_bytes = true;
                _m_TraitType_write(_own1872, value.trait_types[_i1870]);
                base.own("trait_types", interface_text(_own1872));
            }
        }
    }
    base.stat("trait_types", out.values.count - _mark);
    _mark = out.values.count;
    out.unsigned(value.conversions.count);
    for (var _item1880 in value.conversions) {
        _m_Conversion_write(out, _item1880);
    }
    for (var _conv1881 in value.conversions) {
        var _own1882 = RecordOut();
        _own1882.blank_locs = true;
        _m_Conversion_write(_own1882, _conv1881);
        var _h = interface_text(_own1882);
        if (base.find_hashed("conversions", _h) < 0) {
            base.own("conversions", _h);
        }
    }
    base.stat("conversions", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept1890 = 0;
    var _news1891 = Map<String, Array<String>>();
    for (var (_key1887, _) in value.overload_sets) {
        var _kscratch1888 = base.scratch();
        _kscratch1888.text(_key1887);
        var _vscratch1889 = base.scratch();
        _vscratch1889.unsigned(value.overload_sets[_key1887].count);
        for (var _item1892 in value.overload_sets[_key1887]) {
            _vscratch1889.text(_item1892);
        }
        var _had = base.entry("overload_sets", _kscratch1888, _vscratch1889);
        if (_had >= 0) {
            _kept1890 += 1;
        }
        if (_had != 1) {
            _news1891[_key1887] = value.overload_sets[_key1887];
        }
    }
    if (_kept1890 == base.size("overload_sets")) {
        out.unsigned(1);
        var _keys1894 = Array<(u8[], u8[], String)>();
        for (var (_key1893, _) in _news1891) {
            var _scratch1895 = out.scratch();
            _scratch1895.text(_key1893);
            var _vscratch1897 = out.scratch();
            _vscratch1897.unsigned(_news1891[_key1893].count);
            for (var _item1898 in _news1891[_key1893]) {
                _vscratch1897.text(_item1898);
            }
            _keys1894.append((_scratch1895.finish(), _vscratch1897.finish(), _key1893));
        }
        _keys1894.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1894.count);
        for (var (_bytes1896, _, _key1893) in _keys1894) {
            out.text(_key1893);
            out.unsigned(_news1891[_key1893].count);
            for (var _item1899 in _news1891[_key1893]) {
                out.text(_item1899);
            }
        }
        for (var (_okey1900, _) in _news1891) {
            var _own1901 = RecordOut();
            _own1901.blank_bodies = true;
            _own1901.blank_locs = true;
            _own1901.pending_as_bytes = true;
            _own1901.text(_okey1900);
            _own1901.unsigned(_news1891[_okey1900].count);
            for (var _item1902 in _news1891[_okey1900]) {
                _own1901.text(_item1902);
            }
            base.own("overload_sets", interface_text(_own1901));
        }
    } else {
        out.unsigned(0);
        var _keys1904 = Array<(u8[], u8[], String)>();
        for (var (_key1903, _) in value.overload_sets) {
            var _scratch1905 = out.scratch();
            _scratch1905.text(_key1903);
            var _vscratch1907 = out.scratch();
            _vscratch1907.unsigned(value.overload_sets[_key1903].count);
            for (var _item1908 in value.overload_sets[_key1903]) {
                _vscratch1907.text(_item1908);
            }
            _keys1904.append((_scratch1905.finish(), _vscratch1907.finish(), _key1903));
        }
        _keys1904.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1904.count);
        for (var (_bytes1906, _, _key1903) in _keys1904) {
            out.text(_key1903);
            out.unsigned(value.overload_sets[_key1903].count);
            for (var _item1909 in value.overload_sets[_key1903]) {
                out.text(_item1909);
            }
        }
        for (var (_okey1910, _) in value.overload_sets) {
            var _own1911 = RecordOut();
            _own1911.blank_bodies = true;
            _own1911.blank_locs = true;
            _own1911.pending_as_bytes = true;
            _own1911.text(_okey1910);
            _own1911.unsigned(value.overload_sets[_okey1910].count);
            for (var _item1912 in value.overload_sets[_okey1910]) {
                _own1911.text(_item1912);
            }
            base.own("overload_sets", interface_text(_own1911));
        }
        base.count("overload_sets whole", 0);
    }
    base.stat("overload_sets", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept1930 = 0;
    var _news1931 = Map<String, Array<Array<String>>>();
    for (var (_key1927, _) in value.overload_unions) {
        var _kscratch1928 = base.scratch();
        _kscratch1928.text(_key1927);
        var _vscratch1929 = base.scratch();
        _vscratch1929.unsigned(value.overload_unions[_key1927].count);
        for (var _item1932 in value.overload_unions[_key1927]) {
            _vscratch1929.unsigned(_item1932.count);
            for (var _item1933 in _item1932) {
                _vscratch1929.text(_item1933);
            }
        }
        var _had = base.entry("overload_unions", _kscratch1928, _vscratch1929);
        if (_had >= 0) {
            _kept1930 += 1;
        }
        if (_had != 1) {
            _news1931[_key1927] = value.overload_unions[_key1927];
        }
    }
    if (_kept1930 == base.size("overload_unions")) {
        out.unsigned(1);
        var _keys1935 = Array<(u8[], u8[], String)>();
        for (var (_key1934, _) in _news1931) {
            var _scratch1936 = out.scratch();
            _scratch1936.text(_key1934);
            var _vscratch1938 = out.scratch();
            _vscratch1938.unsigned(_news1931[_key1934].count);
            for (var _item1939 in _news1931[_key1934]) {
                _vscratch1938.unsigned(_item1939.count);
                for (var _item1940 in _item1939) {
                    _vscratch1938.text(_item1940);
                }
            }
            _keys1935.append((_scratch1936.finish(), _vscratch1938.finish(), _key1934));
        }
        _keys1935.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1935.count);
        for (var (_bytes1937, _, _key1934) in _keys1935) {
            out.text(_key1934);
            out.unsigned(_news1931[_key1934].count);
            for (var _item1941 in _news1931[_key1934]) {
                out.unsigned(_item1941.count);
                for (var _item1942 in _item1941) {
                    out.text(_item1942);
                }
            }
        }
        for (var (_okey1943, _) in _news1931) {
            var _own1944 = RecordOut();
            _own1944.blank_bodies = true;
            _own1944.blank_locs = true;
            _own1944.pending_as_bytes = true;
            _own1944.text(_okey1943);
            _own1944.unsigned(_news1931[_okey1943].count);
            for (var _item1945 in _news1931[_okey1943]) {
                _own1944.unsigned(_item1945.count);
                for (var _item1946 in _item1945) {
                    _own1944.text(_item1946);
                }
            }
            base.own("overload_unions", interface_text(_own1944));
        }
    } else {
        out.unsigned(0);
        var _keys1948 = Array<(u8[], u8[], String)>();
        for (var (_key1947, _) in value.overload_unions) {
            var _scratch1949 = out.scratch();
            _scratch1949.text(_key1947);
            var _vscratch1951 = out.scratch();
            _vscratch1951.unsigned(value.overload_unions[_key1947].count);
            for (var _item1952 in value.overload_unions[_key1947]) {
                _vscratch1951.unsigned(_item1952.count);
                for (var _item1953 in _item1952) {
                    _vscratch1951.text(_item1953);
                }
            }
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
            out.text(_key1947);
            out.unsigned(value.overload_unions[_key1947].count);
            for (var _item1954 in value.overload_unions[_key1947]) {
                out.unsigned(_item1954.count);
                for (var _item1955 in _item1954) {
                    out.text(_item1955);
                }
            }
        }
        for (var (_okey1956, _) in value.overload_unions) {
            var _own1957 = RecordOut();
            _own1957.blank_bodies = true;
            _own1957.blank_locs = true;
            _own1957.pending_as_bytes = true;
            _own1957.text(_okey1956);
            _own1957.unsigned(value.overload_unions[_okey1956].count);
            for (var _item1958 in value.overload_unions[_okey1956]) {
                _own1957.unsigned(_item1958.count);
                for (var _item1959 in _item1958) {
                    _own1957.text(_item1959);
                }
            }
            base.own("overload_unions", interface_text(_own1957));
        }
        base.count("overload_unions whole", 0);
    }
    base.stat("overload_unions", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept1982 = 0;
    var _news1983 = Map<String, Map<String, Array<String>>>();
    for (var (_key1979, _) in value.method_overload_sets) {
        var _kscratch1980 = base.scratch();
        _kscratch1980.text(_key1979);
        var _vscratch1981 = base.scratch();
        var _keys1985 = Array<(u8[], u8[], String)>();
        for (var (_key1984, _) in value.method_overload_sets[_key1979]) {
            var _scratch1986 = _vscratch1981.scratch();
            _scratch1986.text(_key1984);
            var _vscratch1988 = _vscratch1981.scratch();
            _vscratch1988.unsigned(value.method_overload_sets[_key1979][_key1984].count);
            for (var _item1989 in value.method_overload_sets[_key1979][_key1984]) {
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
        _vscratch1981.unsigned(_keys1985.count);
        for (var (_bytes1987, _, _key1984) in _keys1985) {
            _vscratch1981.text(_key1984);
            _vscratch1981.unsigned(value.method_overload_sets[_key1979][_key1984].count);
            for (var _item1990 in value.method_overload_sets[_key1979][_key1984]) {
                _vscratch1981.text(_item1990);
            }
        }
        var _had = base.entry("method_overload_sets", _kscratch1980, _vscratch1981);
        if (_had >= 0) {
            _kept1982 += 1;
        }
        if (_had != 1) {
            _news1983[_key1979] = value.method_overload_sets[_key1979];
        }
    }
    if (_kept1982 == base.size("method_overload_sets")) {
        out.unsigned(1);
        var _keys1992 = Array<(u8[], u8[], String)>();
        for (var (_key1991, _) in _news1983) {
            var _scratch1993 = out.scratch();
            _scratch1993.text(_key1991);
            var _vscratch1995 = out.scratch();
            var _keys1997 = Array<(u8[], u8[], String)>();
            for (var (_key1996, _) in _news1983[_key1991]) {
                var _scratch1998 = _vscratch1995.scratch();
                _scratch1998.text(_key1996);
                var _vscratch2000 = _vscratch1995.scratch();
                _vscratch2000.unsigned(_news1983[_key1991][_key1996].count);
                for (var _item2001 in _news1983[_key1991][_key1996]) {
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
            _vscratch1995.unsigned(_keys1997.count);
            for (var (_bytes1999, _, _key1996) in _keys1997) {
                _vscratch1995.text(_key1996);
                _vscratch1995.unsigned(_news1983[_key1991][_key1996].count);
                for (var _item2002 in _news1983[_key1991][_key1996]) {
                    _vscratch1995.text(_item2002);
                }
            }
            _keys1992.append((_scratch1993.finish(), _vscratch1995.finish(), _key1991));
        }
        _keys1992.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys1992.count);
        for (var (_bytes1994, _, _key1991) in _keys1992) {
            out.text(_key1991);
            var _keys2004 = Array<(u8[], u8[], String)>();
            for (var (_key2003, _) in _news1983[_key1991]) {
                var _scratch2005 = out.scratch();
                _scratch2005.text(_key2003);
                var _vscratch2007 = out.scratch();
                _vscratch2007.unsigned(_news1983[_key1991][_key2003].count);
                for (var _item2008 in _news1983[_key1991][_key2003]) {
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
            out.unsigned(_keys2004.count);
            for (var (_bytes2006, _, _key2003) in _keys2004) {
                out.text(_key2003);
                out.unsigned(_news1983[_key1991][_key2003].count);
                for (var _item2009 in _news1983[_key1991][_key2003]) {
                    out.text(_item2009);
                }
            }
        }
        for (var (_okey2010, _) in _news1983) {
            var _own2011 = RecordOut();
            _own2011.blank_bodies = true;
            _own2011.blank_locs = true;
            _own2011.pending_as_bytes = true;
            _own2011.text(_okey2010);
            var _keys2013 = Array<(u8[], u8[], String)>();
            for (var (_key2012, _) in _news1983[_okey2010]) {
                var _scratch2014 = _own2011.scratch();
                _scratch2014.text(_key2012);
                var _vscratch2016 = _own2011.scratch();
                _vscratch2016.unsigned(_news1983[_okey2010][_key2012].count);
                for (var _item2017 in _news1983[_okey2010][_key2012]) {
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
            _own2011.unsigned(_keys2013.count);
            for (var (_bytes2015, _, _key2012) in _keys2013) {
                _own2011.text(_key2012);
                _own2011.unsigned(_news1983[_okey2010][_key2012].count);
                for (var _item2018 in _news1983[_okey2010][_key2012]) {
                    _own2011.text(_item2018);
                }
            }
            base.own("method_overload_sets", interface_text(_own2011));
        }
    } else {
        out.unsigned(0);
        var _keys2020 = Array<(u8[], u8[], String)>();
        for (var (_key2019, _) in value.method_overload_sets) {
            var _scratch2021 = out.scratch();
            _scratch2021.text(_key2019);
            var _vscratch2023 = out.scratch();
            var _keys2025 = Array<(u8[], u8[], String)>();
            for (var (_key2024, _) in value.method_overload_sets[_key2019]) {
                var _scratch2026 = _vscratch2023.scratch();
                _scratch2026.text(_key2024);
                var _vscratch2028 = _vscratch2023.scratch();
                _vscratch2028.unsigned(value.method_overload_sets[_key2019][_key2024].count);
                for (var _item2029 in value.method_overload_sets[_key2019][_key2024]) {
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
            _vscratch2023.unsigned(_keys2025.count);
            for (var (_bytes2027, _, _key2024) in _keys2025) {
                _vscratch2023.text(_key2024);
                _vscratch2023.unsigned(value.method_overload_sets[_key2019][_key2024].count);
                for (var _item2030 in value.method_overload_sets[_key2019][_key2024]) {
                    _vscratch2023.text(_item2030);
                }
            }
            _keys2020.append((_scratch2021.finish(), _vscratch2023.finish(), _key2019));
        }
        _keys2020.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2020.count);
        for (var (_bytes2022, _, _key2019) in _keys2020) {
            out.text(_key2019);
            var _keys2032 = Array<(u8[], u8[], String)>();
            for (var (_key2031, _) in value.method_overload_sets[_key2019]) {
                var _scratch2033 = out.scratch();
                _scratch2033.text(_key2031);
                var _vscratch2035 = out.scratch();
                _vscratch2035.unsigned(value.method_overload_sets[_key2019][_key2031].count);
                for (var _item2036 in value.method_overload_sets[_key2019][_key2031]) {
                    _vscratch2035.text(_item2036);
                }
                _keys2032.append((_scratch2033.finish(), _vscratch2035.finish(), _key2031));
            }
            _keys2032.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            out.unsigned(_keys2032.count);
            for (var (_bytes2034, _, _key2031) in _keys2032) {
                out.text(_key2031);
                out.unsigned(value.method_overload_sets[_key2019][_key2031].count);
                for (var _item2037 in value.method_overload_sets[_key2019][_key2031]) {
                    out.text(_item2037);
                }
            }
        }
        for (var (_okey2038, _) in value.method_overload_sets) {
            var _own2039 = RecordOut();
            _own2039.blank_bodies = true;
            _own2039.blank_locs = true;
            _own2039.pending_as_bytes = true;
            _own2039.text(_okey2038);
            var _keys2041 = Array<(u8[], u8[], String)>();
            for (var (_key2040, _) in value.method_overload_sets[_okey2038]) {
                var _scratch2042 = _own2039.scratch();
                _scratch2042.text(_key2040);
                var _vscratch2044 = _own2039.scratch();
                _vscratch2044.unsigned(value.method_overload_sets[_okey2038][_key2040].count);
                for (var _item2045 in value.method_overload_sets[_okey2038][_key2040]) {
                    _vscratch2044.text(_item2045);
                }
                _keys2041.append((_scratch2042.finish(), _vscratch2044.finish(), _key2040));
            }
            _keys2041.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            _own2039.unsigned(_keys2041.count);
            for (var (_bytes2043, _, _key2040) in _keys2041) {
                _own2039.text(_key2040);
                _own2039.unsigned(value.method_overload_sets[_okey2038][_key2040].count);
                for (var _item2046 in value.method_overload_sets[_okey2038][_key2040]) {
                    _own2039.text(_item2046);
                }
            }
            base.own("method_overload_sets", interface_text(_own2039));
        }
        base.count("method_overload_sets whole", 0);
    }
    base.stat("method_overload_sets", out.values.count - _mark);
    _mark = out.values.count;
    _m_ExtensionScopes_write(out, value.extension_scopes);
    base.stat("extension_scopes", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2077 = 0;
    var _news2078 = HashSet<Loc>();
    for (var _key2074 in value.private_functions) {
        var _kscratch2075 = base.scratch();
        _kscratch2075.loc(_key2074);
        var _vscratch2076 = base.scratch();
        var _had = base.entry("private_functions", _kscratch2075, _vscratch2076);
        if (_had >= 0) {
            _kept2077 += 1;
        }
        if (_had != 1) {
            _news2078.insert(_key2074);
        }
    }
    if (_kept2077 == base.size("private_functions")) {
        out.unsigned(1);
        var _keys2080 = Array<(u8[], u8[], Loc)>();
        for (var _key2079 in _news2078) {
            var _scratch2081 = out.scratch();
            _scratch2081.loc(_key2079);
            var _vscratch2083 = out.scratch();
            _keys2080.append((_scratch2081.finish(), _vscratch2083.finish(), _key2079));
        }
        _keys2080.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2080.count);
        for (var (_bytes2082, _, _key2079) in _keys2080) {
            out.loc(_key2079);
        }
        for (var _okey2084 in _news2078) {
            var _own2085 = RecordOut();
            _own2085.blank_bodies = true;
            _own2085.blank_locs = true;
            _own2085.pending_as_bytes = true;
            _own2085.loc(_okey2084);
            base.own_at("private_functions", _okey2084, interface_text(_own2085));
        }
    } else {
        out.unsigned(0);
        var _keys2087 = Array<(u8[], u8[], Loc)>();
        for (var _key2086 in value.private_functions) {
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
        for (var _okey2091 in value.private_functions) {
            var _own2092 = RecordOut();
            _own2092.blank_bodies = true;
            _own2092.blank_locs = true;
            _own2092.pending_as_bytes = true;
            _own2092.loc(_okey2091);
            base.own_at("private_functions", _okey2091, interface_text(_own2092));
        }
        base.count("private_functions whole", 0);
    }
    base.stat("private_functions", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2103 = 0;
    var _news2104 = HashSet<Loc>();
    for (var _key2100 in value.file_private_functions) {
        var _kscratch2101 = base.scratch();
        _kscratch2101.loc(_key2100);
        var _vscratch2102 = base.scratch();
        var _had = base.entry("file_private_functions", _kscratch2101, _vscratch2102);
        if (_had >= 0) {
            _kept2103 += 1;
        }
        if (_had != 1) {
            _news2104.insert(_key2100);
        }
    }
    if (_kept2103 == base.size("file_private_functions")) {
        out.unsigned(1);
        var _keys2106 = Array<(u8[], u8[], Loc)>();
        for (var _key2105 in _news2104) {
            var _scratch2107 = out.scratch();
            _scratch2107.loc(_key2105);
            var _vscratch2109 = out.scratch();
            _keys2106.append((_scratch2107.finish(), _vscratch2109.finish(), _key2105));
        }
        _keys2106.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2106.count);
        for (var (_bytes2108, _, _key2105) in _keys2106) {
            out.loc(_key2105);
        }
        for (var _okey2110 in _news2104) {
            var _own2111 = RecordOut();
            _own2111.blank_bodies = true;
            _own2111.blank_locs = true;
            _own2111.pending_as_bytes = true;
            _own2111.loc(_okey2110);
            base.own_at("file_private_functions", _okey2110, interface_text(_own2111));
        }
    } else {
        out.unsigned(0);
        var _keys2113 = Array<(u8[], u8[], Loc)>();
        for (var _key2112 in value.file_private_functions) {
            var _scratch2114 = out.scratch();
            _scratch2114.loc(_key2112);
            var _vscratch2116 = out.scratch();
            _keys2113.append((_scratch2114.finish(), _vscratch2116.finish(), _key2112));
        }
        _keys2113.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2113.count);
        for (var (_bytes2115, _, _key2112) in _keys2113) {
            out.loc(_key2112);
        }
        for (var _okey2117 in value.file_private_functions) {
            var _own2118 = RecordOut();
            _own2118.blank_bodies = true;
            _own2118.blank_locs = true;
            _own2118.pending_as_bytes = true;
            _own2118.loc(_okey2117);
            base.own_at("file_private_functions", _okey2117, interface_text(_own2118));
        }
        base.count("file_private_functions whole", 0);
    }
    base.stat("file_private_functions", out.values.count - _mark);
    _mark = out.values.count;
    var _n2128 = base.size("call_targets");
    var _scratch2127 = base.scratch();
    if (value.call_targets.count >= _n2128) {
        for (var _i2129 in 0.._n2128) {
            var (_t2130, _t2131) = value.call_targets[_i2129];
            _scratch2127.loc(_t2130);
            _scratch2127.text(_t2131);
        }
    }
    if (value.call_targets.count >= _n2128 and base.same_list("call_targets", _scratch2127)) {
        out.unsigned(1);
        out.unsigned(_n2128);
        out.unsigned(value.call_targets.count - _n2128);
        for (var _i2129 in _n2128..value.call_targets.count) {
            var (_t2132, _t2133) = value.call_targets[_i2129];
            out.loc(_t2132);
            out.text(_t2133);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.call_targets.count);
        for (var _item2134 in value.call_targets) {
            var (_t2135, _t2136) = _item2134;
            out.loc(_t2135);
            out.text(_t2136);
        }
        base.count("call_targets whole", 0);
    }
    base.stat("call_targets", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2153 = 0;
    var _news2154 = Array<(Loc, String)>();
    for (var _item2151 in value.argument_names) {
        var _escratch2152 = base.scratch();
        var (_t2155, _t2156) = _item2151;
        _escratch2152.loc(_t2155);
        _escratch2152.text(_t2156);
        if (base.entry("argument_names", _escratch2152, base.scratch()) >= 0) {
            _kept2153 += 1;
        } else {
            _news2154.append(_item2151);
        }
    }
    if (_kept2153 == base.size("argument_names")) {
        out.unsigned(1);
        out.unsigned(_news2154.count);
        for (var _item2157 in _news2154) {
            var (_t2158, _t2159) = _item2157;
            out.loc(_t2158);
            out.text(_t2159);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.argument_names.count);
        for (var _item2160 in value.argument_names) {
            var (_t2161, _t2162) = _item2160;
            out.loc(_t2161);
            out.text(_t2162);
        }
        base.count("argument_names whole", 0);
    }
    base.stat("argument_names", out.values.count - _mark);
    _mark = out.values.count;
    var _n2177 = base.size("namespaces");
    var _scratch2176 = base.scratch();
    if (value.namespaces.count >= _n2177) {
        for (var _i2178 in 0.._n2177) {
            _scratch2176.text(value.namespaces[_i2178]);
        }
    }
    if (value.namespaces.count >= _n2177 and base.same_list("namespaces", _scratch2176)) {
        out.unsigned(1);
        out.unsigned(_n2177);
        out.unsigned(value.namespaces.count - _n2177);
        for (var _i2178 in _n2177..value.namespaces.count) {
            out.text(value.namespaces[_i2178]);
            {
                var _own2179 = RecordOut();
                _own2179.blank_bodies = true;
                _own2179.blank_locs = true;
                _own2179.pending_as_bytes = true;
                _own2179.text(value.namespaces[_i2178]);
                base.own("namespaces", interface_text(_own2179));
            }
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.namespaces.count);
        for (var _item2180 in value.namespaces) {
            out.text(_item2180);
        }
        for (var _i2178 in 0..value.namespaces.count) {
            {
                var _own2181 = RecordOut();
                _own2181.blank_bodies = true;
                _own2181.blank_locs = true;
                _own2181.pending_as_bytes = true;
                _own2181.text(value.namespaces[_i2178]);
                base.own("namespaces", interface_text(_own2181));
            }
        }
        base.count("namespaces whole", 0);
    }
    base.stat("namespaces", out.values.count - _mark);
    _mark = out.values.count;
    var _n2192 = base.size("cached_files");
    var _scratch2191 = base.scratch();
    if (value.cached_files.count >= _n2192) {
        for (var _i2193 in 0.._n2192) {
            _scratch2191.flag(value.cached_files[_i2193]);
        }
    }
    if (value.cached_files.count >= _n2192 and base.same_list("cached_files", _scratch2191)) {
        out.unsigned(1);
        out.unsigned(_n2192);
        out.unsigned(value.cached_files.count - _n2192);
        for (var _i2193 in _n2192..value.cached_files.count) {
            out.flag(value.cached_files[_i2193]);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.cached_files.count);
        for (var _item2194 in value.cached_files) {
            out.flag(_item2194);
        }
        base.count("cached_files whole", 0);
    }
    base.stat("cached_files", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2206 = 0;
    var _news2207 = HashMap<Loc, String>();
    for (var (_key2203, _) in value.recorded_summaries) {
        var _kscratch2204 = base.scratch();
        _kscratch2204.loc(_key2203);
        var _vscratch2205 = base.scratch();
        _vscratch2205.text(value.recorded_summaries[_key2203]);
        var _had = base.entry("recorded_summaries", _kscratch2204, _vscratch2205);
        if (_had >= 0) {
            _kept2206 += 1;
        }
        if (_had != 1) {
            _news2207[_key2203] = value.recorded_summaries[_key2203];
        }
    }
    if (_kept2206 == base.size("recorded_summaries")) {
        out.unsigned(1);
        var _keys2209 = Array<(u8[], u8[], Loc)>();
        for (var (_key2208, _) in _news2207) {
            var _scratch2210 = out.scratch();
            _scratch2210.loc(_key2208);
            var _vscratch2212 = out.scratch();
            _vscratch2212.text(_news2207[_key2208]);
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
            out.loc(_key2208);
            out.text(_news2207[_key2208]);
        }
    } else {
        out.unsigned(0);
        var _keys2214 = Array<(u8[], u8[], Loc)>();
        for (var (_key2213, _) in value.recorded_summaries) {
            var _scratch2215 = out.scratch();
            _scratch2215.loc(_key2213);
            var _vscratch2217 = out.scratch();
            _vscratch2217.text(value.recorded_summaries[_key2213]);
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
            out.text(value.recorded_summaries[_key2213]);
        }
        base.count("recorded_summaries whole", 0);
    }
    base.stat("recorded_summaries", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2230 = 0;
    var _news2231 = HashSet<Loc>();
    for (var _key2227 in value.stripped) {
        var _kscratch2228 = base.scratch();
        _kscratch2228.loc(_key2227);
        var _vscratch2229 = base.scratch();
        var _had = base.entry("stripped", _kscratch2228, _vscratch2229);
        if (_had >= 0) {
            _kept2230 += 1;
        }
        if (_had != 1) {
            _news2231.insert(_key2227);
        }
    }
    if (_kept2230 == base.size("stripped")) {
        out.unsigned(1);
        var _keys2233 = Array<(u8[], u8[], Loc)>();
        for (var _key2232 in _news2231) {
            var _scratch2234 = out.scratch();
            _scratch2234.loc(_key2232);
            var _vscratch2236 = out.scratch();
            _keys2233.append((_scratch2234.finish(), _vscratch2236.finish(), _key2232));
        }
        _keys2233.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2233.count);
        for (var (_bytes2235, _, _key2232) in _keys2233) {
            out.loc(_key2232);
        }
    } else {
        out.unsigned(0);
        var _keys2238 = Array<(u8[], u8[], Loc)>();
        for (var _key2237 in value.stripped) {
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
        base.count("stripped whole", 0);
    }
    base.stat("stripped", out.values.count - _mark);
    _mark = out.values.count;
    out.flag(value.templates.frozen);
    var _seq2251 = base.ref_templates;
    ulong _bj2252 = 0;
    var _news2254 = Array<ulong>();
    var _patches2255 = Array<(ulong, ulong)>();
    for (var _i2256 in 0..value.templates.structs.count) {
        if (_bj2252 < _seq2251.count
            and value.templates.structs[_i2256] === _seq2251[_bj2252]
            and !value.extended_checked.contains(value.templates.structs[_i2256].name)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_StructDef_write(scratch, value.templates.structs[_i2256]);
                base.verify_same("t", _bj2252, scratch, value.templates.structs[_i2256].name);
            }
            _bj2252 += 1;
        } else if (_bj2252 < _seq2251.count
            and !(value.templates.structs[_i2256] === _seq2251[_bj2252])
            and _same_m_StructDef(value.templates.structs[_i2256], _seq2251[_bj2252], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_StructDef_write(scratch, value.templates.structs[_i2256]);
                base.verify_same("t", _bj2252, scratch, value.templates.structs[_i2256].name);
            }
            _bj2252 += 1;
        } else if (_bj2252 < _seq2251.count and value.templates.structs[_i2256].name == _seq2251[_bj2252].name) {
            _patches2255.append((_i2256, _bj2252));
            _bj2252 += 1;
        } else {
            _news2254.append(_i2256);
        }
    }
    if (_bj2252 == _seq2251.count) {
        out.unsigned(2);
        out.unsigned(_patches2255.count);
        for (var (_i2256, _b) in _patches2255) {
            ulong _before = out.values.count;
            out.text(value.templates.structs[_i2256].name);
            out.unsigned(_b);
            _patch_t_write(out, value.templates.structs[_i2256], base, _b);
            base.count("t patched", out.values.count - _before);
            {
                var _own2257 = RecordOut();
                _own2257.blank_bodies = false;
                _own2257.blank_locs = true;
                _own2257.pending_as_bytes = true;
                _m_StructDef_write(_own2257, value.templates.structs[_i2256]);
                base.own("templates structs", interface_text(_own2257));
            }
        }
        out.unsigned(_news2254.count);
        for (var _i2256 in _news2254) {
            ulong _before = out.values.count;
            out.unsigned(_i2256);
            _m_StructDef_write(out, value.templates.structs[_i2256]);
            base.count("t new", out.values.count - _before);
            {
                var _own2258 = RecordOut();
                _own2258.blank_bodies = false;
                _own2258.blank_locs = true;
                _own2258.pending_as_bytes = true;
                _m_StructDef_write(_own2258, value.templates.structs[_i2256]);
                base.own("templates structs", interface_text(_own2258));
            }
        }
        base.count("t merged", 0);
    } else {
        out.unsigned(1);
        base.count("t by place", 0);
        var _struct_hits2250 = HashSet<long>();
        var _slots2253 = HashMap<String, long>();
        for (var _i2256 in 0.._seq2251.count) {
            if (!_slots2253.contains(_seq2251[_i2256].name)) {
                _slots2253[_seq2251[_i2256].name] = _i2256 as long;
            }
        }
        out.unsigned(value.templates.structs.count);
        for (var _i2256 in 0..value.templates.structs.count) {
            var _item2249 = value.templates.structs[_i2256];
            var _slot = _slots2253.try_get(_item2249.name);
            long named = _slot.is_value() ? _slot.value() : -1;
            long at = -1;
            if (named >= 0
                and _seq2251[named as ulong] === _item2249
                and !value.extended_checked.contains(_item2249.name)) {
                at = named;
            }
            ulong _before = out.values.count;
            if (at >= 0) {
                _struct_hits2250.insert(at);
                out.unsigned((at as ulong) * 2 + 1);
            } else if (named >= 0) {
                _struct_hits2250.insert(named);
                out.unsigned(2);
                out.unsigned(named as ulong);
                _patch_t_write(out, _item2249, base, named as ulong);
                base.count("t patched", out.values.count - _before);
            } else {
                out.unsigned(0);
                _m_StructDef_write(out, _item2249);
                base.count("t new", out.values.count - _before);
            }
        }
        base.missed("t", "t", _struct_hits2250.count);
    }
    var _seq2272 = base.ref_template_functions;
    ulong _bj2273 = 0;
    var _news2274 = Array<ulong>();
    var _changed2268 = Array<(ulong, ulong)>();
    for (var _i2275 in 0..value.templates.functions.count) {
        if (_bj2273 < _seq2272.count and value.templates.functions[_i2275] === _seq2272[_bj2273]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.templates.functions[_i2275]);
                base.verify_same("tf", _bj2273, scratch);
            }
            _bj2273 += 1;
        } else if (_bj2273 < _seq2272.count
            and _same_m_FunctionDef(value.templates.functions[_i2275], _seq2272[_bj2273], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.templates.functions[_i2275]);
                base.verify_same("tf", _bj2273, scratch);
            }
            _bj2273 += 1;
        } else if (_bj2273 < _seq2272.count and value.templates.functions[_i2275].name == _seq2272[_bj2273].name) {
            _changed2268.append((_i2275, _bj2273));
            _bj2273 += 1;
        } else {
            _news2274.append(_i2275);
        }
    }
    if (_bj2273 == _seq2272.count) {
        out.unsigned(2);
        out.unsigned(_changed2268.count);
        for (var (_i2275, _b) in _changed2268) {
            out.text(value.templates.functions[_i2275].name);
            out.unsigned(_b);
            _m_FunctionDef_write(out, value.templates.functions[_i2275]);
            {
                var _own2276 = RecordOut();
                _own2276.blank_bodies = false;
                _own2276.blank_locs = true;
                _own2276.pending_as_bytes = true;
                _m_FunctionDef_write(_own2276, value.templates.functions[_i2275]);
                base.own("templates functions", interface_text(_own2276));
            }
        }
        base.count("tf" + " changed", _changed2268.count);
        out.unsigned(_news2274.count);
        for (var _i2275 in _news2274) {
            out.unsigned(_i2275);
            _m_FunctionDef_write(out, value.templates.functions[_i2275]);
            {
                var _own2277 = RecordOut();
                _own2277.blank_bodies = false;
                _own2277.blank_locs = true;
                _own2277.pending_as_bytes = true;
                _m_FunctionDef_write(_own2277, value.templates.functions[_i2275]);
                base.own("templates functions", interface_text(_own2277));
            }
        }
        base.count("tf" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("tf" + " whole", 0);
        out.unsigned(value.templates.functions.count);
        for (var _i2275 in 0..value.templates.functions.count) {
            _m_FunctionDef_write(out, value.templates.functions[_i2275]);
            {
                var _own2278 = RecordOut();
                _own2278.blank_bodies = false;
                _own2278.blank_locs = true;
                _own2278.pending_as_bytes = true;
                _m_FunctionDef_write(_own2278, value.templates.functions[_i2275]);
                base.own("templates functions", interface_text(_own2278));
            }
        }
    }
    base.stat("templates", out.values.count - _mark);
    _mark = out.values.count;
    base.write_checked(out, value.checked);
    base.stat("checked", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2291 = 0;
    var _news2292 = HashMap<String, SpecRequest>();
    for (var (_key2288, _) in value.spec_requests) {
        var _kscratch2289 = base.scratch();
        _kscratch2289.text(_key2288);
        var _vscratch2290 = base.scratch();
        _m_SpecRequest_write(_vscratch2290, value.spec_requests[_key2288]);
        var _had = base.entry("spec_requests", _kscratch2289, _vscratch2290);
        if (_had >= 0) {
            _kept2291 += 1;
        }
        if (_had != 1) {
            _news2292[_key2288] = value.spec_requests[_key2288];
        }
    }
    if (_kept2291 == base.size("spec_requests")) {
        out.unsigned(1);
        var _keys2294 = Array<(u8[], u8[], String)>();
        for (var (_key2293, _) in _news2292) {
            var _scratch2295 = out.scratch();
            _scratch2295.text(_key2293);
            var _vscratch2297 = out.scratch();
            _m_SpecRequest_write(_vscratch2297, _news2292[_key2293]);
            _keys2294.append((_scratch2295.finish(), _vscratch2297.finish(), _key2293));
        }
        _keys2294.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2294.count);
        for (var (_bytes2296, _, _key2293) in _keys2294) {
            out.text(_key2293);
            _m_SpecRequest_write(out, _news2292[_key2293]);
        }
        for (var (_okey2298, _) in _news2292) {
            var _own2299 = RecordOut();
            _own2299.blank_bodies = true;
            _own2299.blank_locs = true;
            _own2299.pending_as_bytes = true;
            _own2299.text(_okey2298);
            _m_SpecRequest_write(_own2299, _news2292[_okey2298]);
            base.own("spec_requests", interface_text(_own2299));
        }
    } else {
        out.unsigned(0);
        var _keys2301 = Array<(u8[], u8[], String)>();
        for (var (_key2300, _) in value.spec_requests) {
            var _scratch2302 = out.scratch();
            _scratch2302.text(_key2300);
            var _vscratch2304 = out.scratch();
            _m_SpecRequest_write(_vscratch2304, value.spec_requests[_key2300]);
            _keys2301.append((_scratch2302.finish(), _vscratch2304.finish(), _key2300));
        }
        _keys2301.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2301.count);
        for (var (_bytes2303, _, _key2300) in _keys2301) {
            out.text(_key2300);
            _m_SpecRequest_write(out, value.spec_requests[_key2300]);
        }
        for (var (_okey2305, _) in value.spec_requests) {
            var _own2306 = RecordOut();
            _own2306.blank_bodies = true;
            _own2306.blank_locs = true;
            _own2306.pending_as_bytes = true;
            _own2306.text(_okey2305);
            _m_SpecRequest_write(_own2306, value.spec_requests[_okey2305]);
            base.own("spec_requests", interface_text(_own2306));
        }
        base.count("spec_requests whole", 0);
    }
    base.stat("spec_requests", out.values.count - _mark);
    _mark = out.values.count;
    out.flag(value.record_summaries);
    base.stat("record_summaries", out.values.count - _mark);
    _mark = out.values.count;
    var _n2319 = base.size("summaries_to_record");
    var _scratch2318 = base.scratch();
    if (value.summaries_to_record.count >= _n2319) {
        for (var _i2320 in 0.._n2319) {
            var (_t2321, _t2322) = value.summaries_to_record[_i2320];
            _scratch2318.loc(_t2321);
            _scratch2318.text(_t2322);
        }
    }
    if (value.summaries_to_record.count >= _n2319 and base.same_list("summaries_to_record", _scratch2318)) {
        out.unsigned(1);
        out.unsigned(_n2319);
        out.unsigned(value.summaries_to_record.count - _n2319);
        for (var _i2320 in _n2319..value.summaries_to_record.count) {
            var (_t2323, _t2324) = value.summaries_to_record[_i2320];
            out.loc(_t2323);
            out.text(_t2324);
        }
    } else {
        out.unsigned(0);
        out.unsigned(value.summaries_to_record.count);
        for (var _item2325 in value.summaries_to_record) {
            var (_t2326, _t2327) = _item2325;
            out.loc(_t2326);
            out.text(_t2327);
        }
        base.count("summaries_to_record whole", 0);
    }
    base.stat("summaries_to_record", out.values.count - _mark);
    _mark = out.values.count;
    ulong _kept2345 = 0;
    var _news2346 = HashMap<String, Array<bool>>();
    for (var (_key2342, _) in value.caller_copies) {
        var _kscratch2343 = base.scratch();
        _kscratch2343.text(_key2342);
        var _vscratch2344 = base.scratch();
        _vscratch2344.unsigned(value.caller_copies[_key2342].count);
        for (var _item2347 in value.caller_copies[_key2342]) {
            _vscratch2344.flag(_item2347);
        }
        var _had = base.entry("caller_copies", _kscratch2343, _vscratch2344);
        if (_had >= 0) {
            _kept2345 += 1;
        }
        if (_had != 1) {
            _news2346[_key2342] = value.caller_copies[_key2342];
        }
    }
    if (_kept2345 == base.size("caller_copies")) {
        out.unsigned(1);
        var _keys2349 = Array<(u8[], u8[], String)>();
        for (var (_key2348, _) in _news2346) {
            var _scratch2350 = out.scratch();
            _scratch2350.text(_key2348);
            var _vscratch2352 = out.scratch();
            _vscratch2352.unsigned(_news2346[_key2348].count);
            for (var _item2353 in _news2346[_key2348]) {
                _vscratch2352.flag(_item2353);
            }
            _keys2349.append((_scratch2350.finish(), _vscratch2352.finish(), _key2348));
        }
        _keys2349.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2349.count);
        for (var (_bytes2351, _, _key2348) in _keys2349) {
            out.text(_key2348);
            out.unsigned(_news2346[_key2348].count);
            for (var _item2354 in _news2346[_key2348]) {
                out.flag(_item2354);
            }
        }
        for (var (_okey2355, _) in _news2346) {
            var _own2356 = RecordOut();
            _own2356.blank_bodies = true;
            _own2356.blank_locs = true;
            _own2356.pending_as_bytes = true;
            _own2356.text(_okey2355);
            _own2356.unsigned(_news2346[_okey2355].count);
            for (var _item2357 in _news2346[_okey2355]) {
                _own2356.flag(_item2357);
            }
            base.own("caller_copies", interface_text(_own2356));
        }
    } else {
        out.unsigned(0);
        var _keys2359 = Array<(u8[], u8[], String)>();
        for (var (_key2358, _) in value.caller_copies) {
            var _scratch2360 = out.scratch();
            _scratch2360.text(_key2358);
            var _vscratch2362 = out.scratch();
            _vscratch2362.unsigned(value.caller_copies[_key2358].count);
            for (var _item2363 in value.caller_copies[_key2358]) {
                _vscratch2362.flag(_item2363);
            }
            _keys2359.append((_scratch2360.finish(), _vscratch2362.finish(), _key2358));
        }
        _keys2359.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2359.count);
        for (var (_bytes2361, _, _key2358) in _keys2359) {
            out.text(_key2358);
            out.unsigned(value.caller_copies[_key2358].count);
            for (var _item2364 in value.caller_copies[_key2358]) {
                out.flag(_item2364);
            }
        }
        for (var (_okey2365, _) in value.caller_copies) {
            var _own2366 = RecordOut();
            _own2366.blank_bodies = true;
            _own2366.blank_locs = true;
            _own2366.pending_as_bytes = true;
            _own2366.text(_okey2365);
            _own2366.unsigned(value.caller_copies[_okey2365].count);
            for (var _item2367 in value.caller_copies[_okey2365]) {
                _own2366.flag(_item2367);
            }
            base.own("caller_copies", interface_text(_own2366));
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
    var _f1514 = Array<ast.Import>();
    var _mode1517 = input.unsigned();
    if (_mode1517 == 2) {
        var _changed1503 = HashMap<ulong, ast.Import>();
        ulong _bi1518 = 0;
        var _n1515 = input.count();
        for (var _ in 0.._n1515) {
            var _at1519 = input.unsigned();
            while (_f1514.count < _at1519 or (input.merging and _bi1518 < base.imports.count)) {
                var _c = _changed1503.try_get(_bi1518);
                _f1514.append(_c.is_value() ? _c.value() : base.imports[_bi1518]);
                _bi1518 += 1;
            }
            _f1514.append(_a_Import_read(input));
        }
        while (_bi1518 < base.imports.count) {
            var _c = _changed1503.try_get(_bi1518);
            _f1514.append(_c.is_value() ? _c.value() : base.imports[_bi1518]);
            _bi1518 += 1;
        }
    } else if (_mode1517 == 3) {
        var _n1515 = input.count();
        for (var _ in 0.._n1515) {
            _f1514.append(_a_Import_read(input));
        }
    } else {
        var _n1515 = input.count();
        if (input.merging) {
            input.error = "imports" + " written by place";
        }
        for (var _ in 0.._n1515) {
            var _tag1516 = input.unsigned();
            if (_tag1516 & 1 == 1) {
                if (!input.merging) {
                    _f1514.append(base.imports[_tag1516 >> 1]);
                }
            } else {
                var _read = _a_Import_read(input);
                if (!input.merging or true) {
                    _f1514.append(_read);
                }
            }
        }
    }
    var _f1547 = Array<StructDef>();
    var _mode1550 = input.unsigned();
    if (_mode1550 == 2) {
        var _patched1553 = HashMap<ulong, StructDef>();
        var _n1548 = input.count();
        for (var _ in 0.._n1548) {
            var _name = input.text();
            var _slot = input.unsigned();
            if (input.merging) {
                _slot = struct_named(base.structs, _name);
            }
            if (_slot >= base.structs.count) {
                input.error = $"no struct {_name} to patch";
                break;
            }
            _patched1553[_slot] = _patch_s_read(input, base.structs[_slot]);
        }
        ulong _bi1551 = 0;
        var _added = input.count();
        for (var _ in 0.._added) {
            var _at1552 = input.unsigned();
            while (_f1547.count < _at1552 or (input.merging and _bi1551 < base.structs.count)) {
                var _p = _patched1553.try_get(_bi1551);
                _f1547.append(_p.is_value() ? _p.value() : base.structs[_bi1551]);
                _bi1551 += 1;
            }
            _f1547.append(_m_StructDef_read_lazy(input));
        }
        while (_bi1551 < base.structs.count) {
            var _p = _patched1553.try_get(_bi1551);
            _f1547.append(_p.is_value() ? _p.value() : base.structs[_bi1551]);
            _bi1551 += 1;
        }
    } else {
        if (input.merging) {
            input.error = "structs written by place";
        }
        var _n1548 = input.count();
        for (var _ in 0.._n1548) {
            var _tag1549 = input.unsigned();
            if (_tag1549 & 1 == 1) {
                _f1547.append(base.structs[(_tag1549 >> 1) < base.structs.count ? _tag1549 >> 1 : 0]);
            } else if (_tag1549 == 2) {
                var _was = base.structs[input.unsigned()];
                _f1547.append(_patch_s_read(input, _was));
            } else {
                _f1547.append(_m_StructDef_read_lazy(input));
            }
        }
    }
    var _f1567 = Array<TraitDef>();
    var _mode1570 = input.unsigned();
    if (_mode1570 == 2) {
        var _changed1556 = HashMap<ulong, TraitDef>();
        ulong _bi1571 = 0;
        var _n1568 = input.count();
        for (var _ in 0.._n1568) {
            var _at1572 = input.unsigned();
            while (_f1567.count < _at1572 or (input.merging and _bi1571 < base.traits.count)) {
                var _c = _changed1556.try_get(_bi1571);
                _f1567.append(_c.is_value() ? _c.value() : base.traits[_bi1571]);
                _bi1571 += 1;
            }
            _f1567.append(_m_TraitDef_read(input));
        }
        while (_bi1571 < base.traits.count) {
            var _c = _changed1556.try_get(_bi1571);
            _f1567.append(_c.is_value() ? _c.value() : base.traits[_bi1571]);
            _bi1571 += 1;
        }
    } else if (_mode1570 == 3) {
        var _n1568 = input.count();
        for (var _ in 0.._n1568) {
            _f1567.append(_m_TraitDef_read(input));
        }
    } else {
        var _n1568 = input.count();
        if (input.merging) {
            input.error = "traits" + " written by place";
        }
        for (var _ in 0.._n1568) {
            var _tag1569 = input.unsigned();
            if (_tag1569 & 1 == 1) {
                if (!input.merging) {
                    _f1567.append(base.traits[_tag1569 >> 1]);
                }
            } else {
                var _read = _m_TraitDef_read(input);
                if (!input.merging or true) {
                    _f1567.append(_read);
                }
            }
        }
    }
    var _f1586 = Array<ExtensionDef>();
    var _mode1589 = input.unsigned();
    if (_mode1589 == 2) {
        var _changed1575 = HashMap<ulong, ExtensionDef>();
        ulong _bi1590 = 0;
        var _n1587 = input.count();
        for (var _ in 0.._n1587) {
            var _at1591 = input.unsigned();
            while (_f1586.count < _at1591 or (input.merging and _bi1590 < base.extensions.count)) {
                var _c = _changed1575.try_get(_bi1590);
                _f1586.append(_c.is_value() ? _c.value() : base.extensions[_bi1590]);
                _bi1590 += 1;
            }
            _f1586.append(_m_ExtensionDef_read(input));
        }
        while (_bi1590 < base.extensions.count) {
            var _c = _changed1575.try_get(_bi1590);
            _f1586.append(_c.is_value() ? _c.value() : base.extensions[_bi1590]);
            _bi1590 += 1;
        }
    } else if (_mode1589 == 3) {
        var _n1587 = input.count();
        for (var _ in 0.._n1587) {
            _f1586.append(_m_ExtensionDef_read(input));
        }
    } else {
        var _n1587 = input.count();
        if (input.merging) {
            input.error = "extensions" + " written by place";
        }
        for (var _ in 0.._n1587) {
            var _tag1588 = input.unsigned();
            if (_tag1588 & 1 == 1) {
                if (!input.merging) {
                    _f1586.append(base.extensions[_tag1588 >> 1]);
                }
            } else {
                var _read = _m_ExtensionDef_read(input);
                if (!input.merging or true) {
                    _f1586.append(_read);
                }
            }
        }
    }
    var _f1605 = Array<FunctionDef>();
    var _mode1608 = input.unsigned();
    if (_mode1608 == 2) {
        var _changed1594 = HashMap<ulong, FunctionDef>();
        var _nc1596 = input.count();
        for (var _ in 0.._nc1596) {
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
                _changed1594[_slot] = _el;
            } else {
                input.error = $"no {_name} to change";
            }
        }
        ulong _bi1609 = 0;
        var _n1606 = input.count();
        for (var _ in 0.._n1606) {
            var _at1610 = input.unsigned();
            while (_f1605.count < _at1610 or (input.merging and _bi1609 < base.functions.count)) {
                var _c = _changed1594.try_get(_bi1609);
                _f1605.append(_c.is_value() ? _c.value() : base.functions[_bi1609]);
                _bi1609 += 1;
            }
            _f1605.append(_m_FunctionDef_read_lazy(input));
        }
        while (_bi1609 < base.functions.count) {
            var _c = _changed1594.try_get(_bi1609);
            _f1605.append(_c.is_value() ? _c.value() : base.functions[_bi1609]);
            _bi1609 += 1;
        }
    } else if (_mode1608 == 3) {
        var _n1606 = input.count();
        for (var _ in 0.._n1606) {
            _f1605.append(_m_FunctionDef_read_lazy(input));
        }
    } else {
        var _n1606 = input.count();
        if (input.merging) {
            input.error = "functions" + " written by place";
        }
        for (var _ in 0.._n1606) {
            var _tag1607 = input.unsigned();
            if (_tag1607 & 1 == 1) {
                if (!input.merging) {
                    _f1605.append(base.functions[_tag1607 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read_lazy(input);
                if (!input.merging or true) {
                    _f1605.append(_read);
                }
            }
        }
    }
    var _f1624 = Array<ExternDef>();
    var _mode1627 = input.unsigned();
    if (_mode1627 == 2) {
        var _changed1613 = HashMap<ulong, ExternDef>();
        ulong _bi1628 = 0;
        var _n1625 = input.count();
        for (var _ in 0.._n1625) {
            var _at1629 = input.unsigned();
            while (_f1624.count < _at1629 or (input.merging and _bi1628 < base.externs.count)) {
                var _c = _changed1613.try_get(_bi1628);
                _f1624.append(_c.is_value() ? _c.value() : base.externs[_bi1628]);
                _bi1628 += 1;
            }
            _f1624.append(_m_ExternDef_read(input));
        }
        while (_bi1628 < base.externs.count) {
            var _c = _changed1613.try_get(_bi1628);
            _f1624.append(_c.is_value() ? _c.value() : base.externs[_bi1628]);
            _bi1628 += 1;
        }
    } else if (_mode1627 == 3) {
        var _n1625 = input.count();
        for (var _ in 0.._n1625) {
            _f1624.append(_m_ExternDef_read(input));
        }
    } else {
        var _n1625 = input.count();
        if (input.merging) {
            input.error = "externs" + " written by place";
        }
        for (var _ in 0.._n1625) {
            var _tag1626 = input.unsigned();
            if (_tag1626 & 1 == 1) {
                if (!input.merging) {
                    _f1624.append(base.externs[_tag1626 >> 1]);
                }
            } else {
                var _read = _m_ExternDef_read(input);
                if (!input.merging or true) {
                    _f1624.append(_read);
                }
            }
        }
    }
    var _f1643 = Array<VariableDef>();
    var _mode1646 = input.unsigned();
    if (_mode1646 == 2) {
        var _changed1632 = HashMap<ulong, VariableDef>();
        ulong _bi1647 = 0;
        var _n1644 = input.count();
        for (var _ in 0.._n1644) {
            var _at1648 = input.unsigned();
            while (_f1643.count < _at1648 or (input.merging and _bi1647 < base.globals.count)) {
                var _c = _changed1632.try_get(_bi1647);
                _f1643.append(_c.is_value() ? _c.value() : base.globals[_bi1647]);
                _bi1647 += 1;
            }
            _f1643.append(_m_VariableDef_read(input));
        }
        while (_bi1647 < base.globals.count) {
            var _c = _changed1632.try_get(_bi1647);
            _f1643.append(_c.is_value() ? _c.value() : base.globals[_bi1647]);
            _bi1647 += 1;
        }
    } else if (_mode1646 == 3) {
        var _n1644 = input.count();
        for (var _ in 0.._n1644) {
            _f1643.append(_m_VariableDef_read(input));
        }
    } else {
        var _n1644 = input.count();
        if (input.merging) {
            input.error = "globals" + " written by place";
        }
        for (var _ in 0.._n1644) {
            var _tag1645 = input.unsigned();
            if (_tag1645 & 1 == 1) {
                if (!input.merging) {
                    _f1643.append(base.globals[_tag1645 >> 1]);
                }
            } else {
                var _read = _m_VariableDef_read(input);
                if (!input.merging or true) {
                    _f1643.append(_read);
                }
            }
        }
    }
    var _f1662 = Array<ModuleStaticBlock>();
    var _mode1665 = input.unsigned();
    if (_mode1665 == 2) {
        var _changed1651 = HashMap<ulong, ModuleStaticBlock>();
        ulong _bi1666 = 0;
        var _n1663 = input.count();
        for (var _ in 0.._n1663) {
            var _at1667 = input.unsigned();
            while (_f1662.count < _at1667 or (input.merging and _bi1666 < base.static_blocks.count)) {
                var _c = _changed1651.try_get(_bi1666);
                _f1662.append(_c.is_value() ? _c.value() : base.static_blocks[_bi1666]);
                _bi1666 += 1;
            }
            _f1662.append(_m_ModuleStaticBlock_read(input));
        }
        while (_bi1666 < base.static_blocks.count) {
            var _c = _changed1651.try_get(_bi1666);
            _f1662.append(_c.is_value() ? _c.value() : base.static_blocks[_bi1666]);
            _bi1666 += 1;
        }
    } else if (_mode1665 == 3) {
        var _n1663 = input.count();
        for (var _ in 0.._n1663) {
            _f1662.append(_m_ModuleStaticBlock_read(input));
        }
    } else {
        var _n1663 = input.count();
        if (input.merging) {
            input.error = "static_blocks" + " written by place";
        }
        for (var _ in 0.._n1663) {
            var _tag1664 = input.unsigned();
            if (_tag1664 & 1 == 1) {
                if (!input.merging) {
                    _f1662.append(base.static_blocks[_tag1664 >> 1]);
                }
            } else {
                var _read = _m_ModuleStaticBlock_read(input);
                if (!input.merging or true) {
                    _f1662.append(_read);
                }
            }
        }
    }
    var _f1681 = Array<EnumDef>();
    var _mode1684 = input.unsigned();
    if (_mode1684 == 2) {
        var _changed1670 = HashMap<ulong, EnumDef>();
        ulong _bi1685 = 0;
        var _n1682 = input.count();
        for (var _ in 0.._n1682) {
            var _at1686 = input.unsigned();
            while (_f1681.count < _at1686 or (input.merging and _bi1685 < base.enums.count)) {
                var _c = _changed1670.try_get(_bi1685);
                _f1681.append(_c.is_value() ? _c.value() : base.enums[_bi1685]);
                _bi1685 += 1;
            }
            _f1681.append(_m_EnumDef_read(input));
        }
        while (_bi1685 < base.enums.count) {
            var _c = _changed1670.try_get(_bi1685);
            _f1681.append(_c.is_value() ? _c.value() : base.enums[_bi1685]);
            _bi1685 += 1;
        }
    } else if (_mode1684 == 3) {
        var _n1682 = input.count();
        for (var _ in 0.._n1682) {
            _f1681.append(_m_EnumDef_read(input));
        }
    } else {
        var _n1682 = input.count();
        if (input.merging) {
            input.error = "enums" + " written by place";
        }
        for (var _ in 0.._n1682) {
            var _tag1683 = input.unsigned();
            if (_tag1683 & 1 == 1) {
                if (!input.merging) {
                    _f1681.append(base.enums[_tag1683 >> 1]);
                }
            } else {
                var _read = _m_EnumDef_read(input);
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
            while (_f1700.count < _at1705 or (input.merging and _bi1704 < base.struct_specs.count)) {
                var _c = _changed1689.try_get(_bi1704);
                _f1700.append(_c.is_value() ? _c.value() : base.struct_specs[_bi1704]);
                _bi1704 += 1;
            }
            _f1700.append(_m_TypeName_read(input));
        }
        while (_bi1704 < base.struct_specs.count) {
            var _c = _changed1689.try_get(_bi1704);
            _f1700.append(_c.is_value() ? _c.value() : base.struct_specs[_bi1704]);
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
            input.error = "struct_specs" + " written by place";
        }
        for (var _ in 0.._n1701) {
            var _tag1702 = input.unsigned();
            if (_tag1702 & 1 == 1) {
                if (!input.merging) {
                    _f1700.append(base.struct_specs[_tag1702 >> 1]);
                }
            } else {
                var _read = _m_TypeName_read(input);
                if (!input.merging or true) {
                    _f1700.append(_read);
                }
            }
        }
    }
    var _f1719 = Array<TypeName>();
    var _mode1722 = input.unsigned();
    if (_mode1722 == 2) {
        var _changed1708 = HashMap<ulong, TypeName>();
        ulong _bi1723 = 0;
        var _n1720 = input.count();
        for (var _ in 0.._n1720) {
            var _at1724 = input.unsigned();
            while (_f1719.count < _at1724 or (input.merging and _bi1723 < base.func_specs.count)) {
                var _c = _changed1708.try_get(_bi1723);
                _f1719.append(_c.is_value() ? _c.value() : base.func_specs[_bi1723]);
                _bi1723 += 1;
            }
            _f1719.append(_m_TypeName_read(input));
        }
        while (_bi1723 < base.func_specs.count) {
            var _c = _changed1708.try_get(_bi1723);
            _f1719.append(_c.is_value() ? _c.value() : base.func_specs[_bi1723]);
            _bi1723 += 1;
        }
    } else if (_mode1722 == 3) {
        var _n1720 = input.count();
        for (var _ in 0.._n1720) {
            _f1719.append(_m_TypeName_read(input));
        }
    } else {
        var _n1720 = input.count();
        if (input.merging) {
            input.error = "func_specs" + " written by place";
        }
        for (var _ in 0.._n1720) {
            var _tag1721 = input.unsigned();
            if (_tag1721 & 1 == 1) {
                if (!input.merging) {
                    _f1719.append(base.func_specs[_tag1721 >> 1]);
                }
            } else {
                var _read = _m_TypeName_read(input);
                if (!input.merging or true) {
                    _f1719.append(_read);
                }
            }
        }
    }
    var _f1731 = Array<TypeAliasDef>();
    var _n1732 = input.count();
    if (input.merging) {
        for (var _b in base.type_aliases) {
            _f1731.append(_b);
        }
    }
    for (var _ in 0.._n1732) {
        var _tag1733 = input.unsigned();
        if (_tag1733 & 1 == 1) {
            if (!input.merging) {
                _f1731.append(base.type_aliases[_tag1733 >> 1]);
            }
        } else {
            var _read = _m_TypeAliasDef_read(input);
            if (!input.merging or false) {
                _f1731.append(_read);
            }
        }
    }
    var _f1747 = Array<Withheld>();
    var _mode1750 = input.unsigned();
    if (_mode1750 == 2) {
        var _changed1736 = HashMap<ulong, Withheld>();
        ulong _bi1751 = 0;
        var _n1748 = input.count();
        for (var _ in 0.._n1748) {
            var _at1752 = input.unsigned();
            while (_f1747.count < _at1752 or (input.merging and _bi1751 < base.withheld.count)) {
                var _c = _changed1736.try_get(_bi1751);
                _f1747.append(_c.is_value() ? _c.value() : base.withheld[_bi1751]);
                _bi1751 += 1;
            }
            _f1747.append(_m_Withheld_read(input));
        }
        while (_bi1751 < base.withheld.count) {
            var _c = _changed1736.try_get(_bi1751);
            _f1747.append(_c.is_value() ? _c.value() : base.withheld[_bi1751]);
            _bi1751 += 1;
        }
    } else if (_mode1750 == 3) {
        var _n1748 = input.count();
        for (var _ in 0.._n1748) {
            _f1747.append(_m_Withheld_read(input));
        }
    } else {
        var _n1748 = input.count();
        if (input.merging) {
            input.error = "withheld" + " written by place";
        }
        for (var _ in 0.._n1748) {
            var _tag1749 = input.unsigned();
            if (_tag1749 & 1 == 1) {
                if (!input.merging) {
                    _f1747.append(base.withheld[_tag1749 >> 1]);
                }
            } else {
                var _read = _m_Withheld_read(input);
                if (!input.merging or true) {
                    _f1747.append(_read);
                }
            }
        }
    }
    var _f1766 = Array<PropertyDef>();
    var _mode1769 = input.unsigned();
    if (_mode1769 == 2) {
        var _changed1755 = HashMap<ulong, PropertyDef>();
        ulong _bi1770 = 0;
        var _n1767 = input.count();
        for (var _ in 0.._n1767) {
            var _at1771 = input.unsigned();
            while (_f1766.count < _at1771 or (input.merging and _bi1770 < base.properties.count)) {
                var _c = _changed1755.try_get(_bi1770);
                _f1766.append(_c.is_value() ? _c.value() : base.properties[_bi1770]);
                _bi1770 += 1;
            }
            _f1766.append(_m_PropertyDef_read(input));
        }
        while (_bi1770 < base.properties.count) {
            var _c = _changed1755.try_get(_bi1770);
            _f1766.append(_c.is_value() ? _c.value() : base.properties[_bi1770]);
            _bi1770 += 1;
        }
    } else if (_mode1769 == 3) {
        var _n1767 = input.count();
        for (var _ in 0.._n1767) {
            _f1766.append(_m_PropertyDef_read(input));
        }
    } else {
        var _n1767 = input.count();
        if (input.merging) {
            input.error = "properties" + " written by place";
        }
        for (var _ in 0.._n1767) {
            var _tag1768 = input.unsigned();
            if (_tag1768 & 1 == 1) {
                if (!input.merging) {
                    _f1766.append(base.properties[_tag1768 >> 1]);
                }
            } else {
                var _read = _m_PropertyDef_read(input);
                if (!input.merging or true) {
                    _f1766.append(_read);
                }
            }
        }
    }
    var _f1785 = Array<TypeUse>();
    var _mode1788 = input.unsigned();
    if (_mode1788 == 2) {
        var _changed1774 = HashMap<ulong, TypeUse>();
        ulong _bi1789 = 0;
        var _n1786 = input.count();
        for (var _ in 0.._n1786) {
            var _at1790 = input.unsigned();
            while (_f1785.count < _at1790 or (input.merging and _bi1789 < base.type_uses.count)) {
                var _c = _changed1774.try_get(_bi1789);
                _f1785.append(_c.is_value() ? _c.value() : base.type_uses[_bi1789]);
                _bi1789 += 1;
            }
            _f1785.append(_m_TypeUse_read(input));
        }
        while (_bi1789 < base.type_uses.count) {
            var _c = _changed1774.try_get(_bi1789);
            _f1785.append(_c.is_value() ? _c.value() : base.type_uses[_bi1789]);
            _bi1789 += 1;
        }
    } else if (_mode1788 == 3) {
        var _n1786 = input.count();
        for (var _ in 0.._n1786) {
            _f1785.append(_m_TypeUse_read(input));
        }
    } else {
        var _n1786 = input.count();
        if (input.merging) {
            input.error = "type_uses" + " written by place";
        }
        for (var _ in 0.._n1786) {
            var _tag1787 = input.unsigned();
            if (_tag1787 & 1 == 1) {
                if (!input.merging) {
                    _f1785.append(base.type_uses[_tag1787 >> 1]);
                }
            } else {
                var _read = _m_TypeUse_read(input);
                if (!input.merging or true) {
                    _f1785.append(_read);
                }
            }
        }
    }
    var _f1804 = Array<UseContext>();
    var _mode1807 = input.unsigned();
    if (_mode1807 == 2) {
        var _changed1793 = HashMap<ulong, UseContext>();
        ulong _bi1808 = 0;
        var _n1805 = input.count();
        for (var _ in 0.._n1805) {
            var _at1809 = input.unsigned();
            while (_f1804.count < _at1809 or (input.merging and _bi1808 < base.use_contexts.count)) {
                var _c = _changed1793.try_get(_bi1808);
                _f1804.append(_c.is_value() ? _c.value() : base.use_contexts[_bi1808]);
                _bi1808 += 1;
            }
            _f1804.append(_m_UseContext_read(input));
        }
        while (_bi1808 < base.use_contexts.count) {
            var _c = _changed1793.try_get(_bi1808);
            _f1804.append(_c.is_value() ? _c.value() : base.use_contexts[_bi1808]);
            _bi1808 += 1;
        }
    } else if (_mode1807 == 3) {
        var _n1805 = input.count();
        for (var _ in 0.._n1805) {
            _f1804.append(_m_UseContext_read(input));
        }
    } else {
        var _n1805 = input.count();
        if (input.merging) {
            input.error = "use_contexts" + " written by place";
        }
        for (var _ in 0.._n1805) {
            var _tag1806 = input.unsigned();
            if (_tag1806 & 1 == 1) {
                if (!input.merging) {
                    _f1804.append(base.use_contexts[_tag1806 >> 1]);
                }
            } else {
                var _read = _m_UseContext_read(input);
                if (!input.merging or true) {
                    _f1804.append(_read);
                }
            }
        }
    }
    var _f1825 = Array<(Loc, ulong, Loc)>();
    var _tag1826 = input.unsigned();
    if (_tag1826 == 1) {
        input.unsigned();
        for (var _i1814 in 0..base.literal_args.count) {
            _f1825.append(base.literal_args[_i1814]);
        }
        var _more1828 = input.count();
        for (var _ in 0.._more1828) {
            var _t1829 = input.loc();
            var _t1830 = input.unsigned();
            var _t1831 = input.loc();
            _f1825.append((_t1829, _t1830, _t1831));
        }
    } else {
        var _v1832 = Array<(Loc, ulong, Loc)>();
        var _n1833 = input.count();
        for (var _ in 0.._n1833) {
            var _t1834 = input.loc();
            var _t1835 = input.unsigned();
            var _t1836 = input.loc();
            _v1832.append((_t1834, _t1835, _t1836));
        }
        _f1825 = _v1832;
    }
    var _f1854 = Array<TypeAliasDef>();
    var _mode1857 = input.unsigned();
    if (_mode1857 == 2) {
        var _changed1843 = HashMap<ulong, TypeAliasDef>();
        ulong _bi1858 = 0;
        var _n1855 = input.count();
        for (var _ in 0.._n1855) {
            var _at1859 = input.unsigned();
            while (_f1854.count < _at1859 or (input.merging and _bi1858 < base.constrained_aliases.count)) {
                var _c = _changed1843.try_get(_bi1858);
                _f1854.append(_c.is_value() ? _c.value() : base.constrained_aliases[_bi1858]);
                _bi1858 += 1;
            }
            _f1854.append(_m_TypeAliasDef_read(input));
        }
        while (_bi1858 < base.constrained_aliases.count) {
            var _c = _changed1843.try_get(_bi1858);
            _f1854.append(_c.is_value() ? _c.value() : base.constrained_aliases[_bi1858]);
            _bi1858 += 1;
        }
    } else if (_mode1857 == 3) {
        var _n1855 = input.count();
        for (var _ in 0.._n1855) {
            _f1854.append(_m_TypeAliasDef_read(input));
        }
    } else {
        var _n1855 = input.count();
        if (input.merging) {
            input.error = "constrained_aliases" + " written by place";
        }
        for (var _ in 0.._n1855) {
            var _tag1856 = input.unsigned();
            if (_tag1856 & 1 == 1) {
                if (!input.merging) {
                    _f1854.append(base.constrained_aliases[_tag1856 >> 1]);
                }
            } else {
                var _read = _m_TypeAliasDef_read(input);
                if (!input.merging or true) {
                    _f1854.append(_read);
                }
            }
        }
    }
    var _f1873 = Array<TraitType>();
    var _mode1876 = input.unsigned();
    if (_mode1876 == 2) {
        var _changed1862 = HashMap<ulong, TraitType>();
        ulong _bi1877 = 0;
        var _n1874 = input.count();
        for (var _ in 0.._n1874) {
            var _at1878 = input.unsigned();
            while (_f1873.count < _at1878 or (input.merging and _bi1877 < base.trait_types.count)) {
                var _c = _changed1862.try_get(_bi1877);
                _f1873.append(_c.is_value() ? _c.value() : base.trait_types[_bi1877]);
                _bi1877 += 1;
            }
            _f1873.append(_m_TraitType_read(input));
        }
        while (_bi1877 < base.trait_types.count) {
            var _c = _changed1862.try_get(_bi1877);
            _f1873.append(_c.is_value() ? _c.value() : base.trait_types[_bi1877]);
            _bi1877 += 1;
        }
    } else if (_mode1876 == 3) {
        var _n1874 = input.count();
        for (var _ in 0.._n1874) {
            _f1873.append(_m_TraitType_read(input));
        }
    } else {
        var _n1874 = input.count();
        if (input.merging) {
            input.error = "trait_types" + " written by place";
        }
        for (var _ in 0.._n1874) {
            var _tag1875 = input.unsigned();
            if (_tag1875 & 1 == 1) {
                if (!input.merging) {
                    _f1873.append(base.trait_types[_tag1875 >> 1]);
                }
            } else {
                var _read = _m_TraitType_read(input);
                if (!input.merging or true) {
                    _f1873.append(_read);
                }
            }
        }
    }
    var _v1884 = Array<Conversion>();
    var _n1885 = input.count();
    for (var _ in 0.._n1885) {
        _v1884.append(_m_Conversion_read(input));
    }
    var _f1886 = _v1884;
    var _f1913 = Map<String, Array<String>>();
    var _tag1914 = input.unsigned();
    if (_tag1914 == 1) {
        for (var (_bk1915, _bv) in base.overload_sets) {
            _f1913[_bk1915] = _bv;
        }
        var _v1916 = Map<String, Array<String>>();
        var _n1917 = input.count();
        for (var _ in 0.._n1917) {
            var _k1918 = input.text();
            var _v1919 = Array<String>();
            var _n1920 = input.count();
            for (var _ in 0.._n1920) {
                _v1919.append(input.text());
            }
            _v1916[_k1918] = _v1919;
        }
        for (var (_bk1915, _av) in _v1916) {
            _f1913[_bk1915] = _av;
        }
    } else {
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
        _f1913 = _v1921;
    }
    var _f1960 = Map<String, Array<Array<String>>>();
    var _tag1961 = input.unsigned();
    if (_tag1961 == 1) {
        for (var (_bk1962, _bv) in base.overload_unions) {
            _f1960[_bk1962] = _bv;
        }
        var _v1963 = Map<String, Array<Array<String>>>();
        var _n1964 = input.count();
        for (var _ in 0.._n1964) {
            var _k1965 = input.text();
            var _v1966 = Array<Array<String>>();
            var _n1967 = input.count();
            for (var _ in 0.._n1967) {
                var _v1968 = Array<String>();
                var _n1969 = input.count();
                for (var _ in 0.._n1969) {
                    _v1968.append(input.text());
                }
                _v1966.append(_v1968);
            }
            _v1963[_k1965] = _v1966;
        }
        for (var (_bk1962, _av) in _v1963) {
            _f1960[_bk1962] = _av;
        }
    } else {
        var _v1970 = Map<String, Array<Array<String>>>();
        var _n1971 = input.count();
        for (var _ in 0.._n1971) {
            var _k1972 = input.text();
            var _v1973 = Array<Array<String>>();
            var _n1974 = input.count();
            for (var _ in 0.._n1974) {
                var _v1975 = Array<String>();
                var _n1976 = input.count();
                for (var _ in 0.._n1976) {
                    _v1975.append(input.text());
                }
                _v1973.append(_v1975);
            }
            _v1970[_k1972] = _v1973;
        }
        _f1960 = _v1970;
    }
    var _f2047 = Map<String, Map<String, Array<String>>>();
    var _tag2048 = input.unsigned();
    if (_tag2048 == 1) {
        for (var (_bk2049, _bv) in base.method_overload_sets) {
            _f2047[_bk2049] = _bv;
        }
        var _v2050 = Map<String, Map<String, Array<String>>>();
        var _n2051 = input.count();
        for (var _ in 0.._n2051) {
            var _k2052 = input.text();
            var _v2053 = Map<String, Array<String>>();
            var _n2054 = input.count();
            for (var _ in 0.._n2054) {
                var _k2055 = input.text();
                var _v2056 = Array<String>();
                var _n2057 = input.count();
                for (var _ in 0.._n2057) {
                    _v2056.append(input.text());
                }
                _v2053[_k2055] = _v2056;
            }
            _v2050[_k2052] = _v2053;
        }
        for (var (_bk2049, _av) in _v2050) {
            _f2047[_bk2049] = _av;
        }
    } else {
        var _v2058 = Map<String, Map<String, Array<String>>>();
        var _n2059 = input.count();
        for (var _ in 0.._n2059) {
            var _k2060 = input.text();
            var _v2061 = Map<String, Array<String>>();
            var _n2062 = input.count();
            for (var _ in 0.._n2062) {
                var _k2063 = input.text();
                var _v2064 = Array<String>();
                var _n2065 = input.count();
                for (var _ in 0.._n2065) {
                    _v2064.append(input.text());
                }
                _v2061[_k2063] = _v2064;
            }
            _v2058[_k2060] = _v2061;
        }
        _f2047 = _v2058;
    }
    var _f2073 = _m_ExtensionScopes_read(input);
    var _f2093 = HashSet<Loc>();
    var _tag2094 = input.unsigned();
    if (_tag2094 == 1) {
        for (var _bk2095 in base.private_functions) {
            _f2093.insert(_bk2095);
        }
        var _v2096 = HashSet<Loc>();
        var _n2097 = input.count();
        for (var _ in 0.._n2097) {
            _v2096.insert(input.loc());
        }
        for (var _bk2095 in _v2096) {
            _f2093.insert(_bk2095);
        }
    } else {
        var _v2098 = HashSet<Loc>();
        var _n2099 = input.count();
        for (var _ in 0.._n2099) {
            _v2098.insert(input.loc());
        }
        _f2093 = _v2098;
    }
    var _f2119 = HashSet<Loc>();
    var _tag2120 = input.unsigned();
    if (_tag2120 == 1) {
        for (var _bk2121 in base.file_private_functions) {
            _f2119.insert(_bk2121);
        }
        var _v2122 = HashSet<Loc>();
        var _n2123 = input.count();
        for (var _ in 0.._n2123) {
            _v2122.insert(input.loc());
        }
        for (var _bk2121 in _v2122) {
            _f2119.insert(_bk2121);
        }
    } else {
        var _v2124 = HashSet<Loc>();
        var _n2125 = input.count();
        for (var _ in 0.._n2125) {
            _v2124.insert(input.loc());
        }
        _f2119 = _v2124;
    }
    var _f2137 = Array<(Loc, String)>();
    var _tag2138 = input.unsigned();
    if (_tag2138 == 1) {
        input.unsigned();
        for (var _i2129 in 0..base.call_targets.count) {
            _f2137.append(base.call_targets[_i2129]);
        }
        var _more2140 = input.count();
        for (var _ in 0.._more2140) {
            var _t2141 = input.loc();
            var _t2142 = input.text();
            _f2137.append((_t2141, _t2142));
        }
    } else {
        var _v2143 = Array<(Loc, String)>();
        var _n2144 = input.count();
        for (var _ in 0.._n2144) {
            var _t2145 = input.loc();
            var _t2146 = input.text();
            _v2143.append((_t2145, _t2146));
        }
        _f2137 = _v2143;
    }
    var _f2163 = Array<(Loc, String)>();
    var _tag2164 = input.unsigned();
    if (_tag2164 == 1) {
        var _v2165 = Array<(Loc, String)>();
        var _n2166 = input.count();
        for (var _ in 0.._n2166) {
            var _t2167 = input.loc();
            var _t2168 = input.text();
            _v2165.append((_t2167, _t2168));
        }
        _f2163 = merge_by_place(base.argument_names, _v2165);
    } else {
        var _v2169 = Array<(Loc, String)>();
        var _n2170 = input.count();
        for (var _ in 0.._n2170) {
            var _t2171 = input.loc();
            var _t2172 = input.text();
            _v2169.append((_t2171, _t2172));
        }
        _f2163 = _v2169;
    }
    var _f2182 = Array<String>();
    var _tag2183 = input.unsigned();
    if (_tag2183 == 1) {
        input.unsigned();
        for (var _i2178 in 0..base.namespaces.count) {
            _f2182.append(base.namespaces[_i2178]);
        }
        var _more2185 = input.count();
        for (var _ in 0.._more2185) {
            _f2182.append(input.text());
        }
    } else {
        var _v2186 = Array<String>();
        var _n2187 = input.count();
        for (var _ in 0.._n2187) {
            _v2186.append(input.text());
        }
        _f2182 = _v2186;
    }
    var _f2195 = Array<bool>();
    var _tag2196 = input.unsigned();
    if (_tag2196 == 1) {
        input.unsigned();
        for (var _i2193 in 0..base.cached_files.count) {
            _f2195.append(base.cached_files[_i2193]);
        }
        var _more2198 = input.count();
        for (var _ in 0.._more2198) {
            _f2195.append(input.flag());
        }
    } else {
        var _v2199 = Array<bool>();
        var _n2200 = input.count();
        for (var _ in 0.._n2200) {
            _v2199.append(input.flag());
        }
        _f2195 = _v2199;
    }
    var _f2218 = HashMap<Loc, String>();
    var _tag2219 = input.unsigned();
    if (_tag2219 == 1) {
        for (var (_bk2220, _bv) in base.recorded_summaries) {
            _f2218[_bk2220] = _bv;
        }
        var _v2221 = HashMap<Loc, String>();
        var _n2222 = input.count();
        for (var _ in 0.._n2222) {
            var _k2223 = input.loc();
            _v2221[_k2223] = input.text();
        }
        for (var (_bk2220, _av) in _v2221) {
            _f2218[_bk2220] = _av;
        }
    } else {
        var _v2224 = HashMap<Loc, String>();
        var _n2225 = input.count();
        for (var _ in 0.._n2225) {
            var _k2226 = input.loc();
            _v2224[_k2226] = input.text();
        }
        _f2218 = _v2224;
    }
    var _f2242 = HashSet<Loc>();
    var _tag2243 = input.unsigned();
    if (_tag2243 == 1) {
        for (var _bk2244 in base.stripped) {
            _f2242.insert(_bk2244);
        }
        var _v2245 = HashSet<Loc>();
        var _n2246 = input.count();
        for (var _ in 0.._n2246) {
            _v2245.insert(input.loc());
        }
        for (var _bk2244 in _v2245) {
            _f2242.insert(_bk2244);
        }
    } else {
        var _v2247 = HashSet<Loc>();
        var _n2248 = input.count();
        for (var _ in 0.._n2248) {
            _v2247.insert(input.loc());
        }
        _f2242 = _v2247;
    }
    var _frozen = input.flag();
    var _f2259 = Array<StructDef>();
    var _mode2262 = input.unsigned();
    if (_mode2262 == 2) {
        var _patched2265 = HashMap<ulong, StructDef>();
        var _n2260 = input.count();
        for (var _ in 0.._n2260) {
            var _name = input.text();
            var _slot = input.unsigned();
            if (input.merging) {
                _slot = struct_named(base.templates.structs, _name);
            }
            if (_slot >= base.templates.structs.count) {
                input.error = $"no struct {_name} to patch";
                break;
            }
            _patched2265[_slot] = _patch_t_read(input, base.templates.structs[_slot]);
        }
        ulong _bi2263 = 0;
        var _added = input.count();
        for (var _ in 0.._added) {
            var _at2264 = input.unsigned();
            while (_f2259.count < _at2264 or (input.merging and _bi2263 < base.templates.structs.count)) {
                var _p = _patched2265.try_get(_bi2263);
                _f2259.append(_p.is_value() ? _p.value() : base.templates.structs[_bi2263]);
                _bi2263 += 1;
            }
            _f2259.append(_m_StructDef_read(input));
        }
        while (_bi2263 < base.templates.structs.count) {
            var _p = _patched2265.try_get(_bi2263);
            _f2259.append(_p.is_value() ? _p.value() : base.templates.structs[_bi2263]);
            _bi2263 += 1;
        }
    } else {
        if (input.merging) {
            input.error = "structs written by place";
        }
        var _n2260 = input.count();
        for (var _ in 0.._n2260) {
            var _tag2261 = input.unsigned();
            if (_tag2261 & 1 == 1) {
                _f2259.append(
                    base.templates.structs[(_tag2261 >> 1) < base.templates.structs.count ? _tag2261 >> 1 : 0]
                );
            } else if (_tag2261 == 2) {
                var _was = base.templates.structs[input.unsigned()];
                _f2259.append(_patch_t_read(input, _was));
            } else {
                _f2259.append(_m_StructDef_read(input));
            }
        }
    }
    var _f2279 = Array<FunctionDef>();
    var _mode2282 = input.unsigned();
    if (_mode2282 == 2) {
        var _changed2268 = HashMap<ulong, FunctionDef>();
        var _nc2270 = input.count();
        for (var _ in 0.._nc2270) {
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
                _changed2268[_slot] = _el;
            } else {
                input.error = $"no {_name} to change";
            }
        }
        ulong _bi2283 = 0;
        var _n2280 = input.count();
        for (var _ in 0.._n2280) {
            var _at2284 = input.unsigned();
            while (_f2279.count < _at2284 or (input.merging and _bi2283 < base.templates.functions.count)) {
                var _c = _changed2268.try_get(_bi2283);
                _f2279.append(_c.is_value() ? _c.value() : base.templates.functions[_bi2283]);
                _bi2283 += 1;
            }
            _f2279.append(_m_FunctionDef_read(input));
        }
        while (_bi2283 < base.templates.functions.count) {
            var _c = _changed2268.try_get(_bi2283);
            _f2279.append(_c.is_value() ? _c.value() : base.templates.functions[_bi2283]);
            _bi2283 += 1;
        }
    } else if (_mode2282 == 3) {
        var _n2280 = input.count();
        for (var _ in 0.._n2280) {
            _f2279.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2280 = input.count();
        if (input.merging) {
            input.error = "tf" + " written by place";
        }
        for (var _ in 0.._n2280) {
            var _tag2281 = input.unsigned();
            if (_tag2281 & 1 == 1) {
                if (!input.merging) {
                    _f2279.append(base.templates.functions[_tag2281 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2279.append(_read);
                }
            }
        }
    }
    var _f2286 = Templates(_frozen, _f2259, _f2279);
    var _f2287 = DeltaBase.read_checked(input, base.checked);
    var _f2307 = HashMap<String, SpecRequest>();
    var _tag2308 = input.unsigned();
    if (_tag2308 == 1) {
        for (var (_bk2309, _bv) in base.spec_requests) {
            _f2307[_bk2309] = _bv;
        }
        var _v2310 = HashMap<String, SpecRequest>();
        var _n2311 = input.count();
        for (var _ in 0.._n2311) {
            var _k2312 = input.text();
            _v2310[_k2312] = _m_SpecRequest_read(input);
        }
        for (var (_bk2309, _av) in _v2310) {
            _f2307[_bk2309] = _av;
        }
    } else {
        var _v2313 = HashMap<String, SpecRequest>();
        var _n2314 = input.count();
        for (var _ in 0.._n2314) {
            var _k2315 = input.text();
            _v2313[_k2315] = _m_SpecRequest_read(input);
        }
        _f2307 = _v2313;
    }
    var _f2316 = input.flag();
    var _f2328 = Array<(Loc, String)>();
    var _tag2329 = input.unsigned();
    if (_tag2329 == 1) {
        input.unsigned();
        for (var _i2320 in 0..base.summaries_to_record.count) {
            _f2328.append(base.summaries_to_record[_i2320]);
        }
        var _more2331 = input.count();
        for (var _ in 0.._more2331) {
            var _t2332 = input.loc();
            var _t2333 = input.text();
            _f2328.append((_t2332, _t2333));
        }
    } else {
        var _v2334 = Array<(Loc, String)>();
        var _n2335 = input.count();
        for (var _ in 0.._n2335) {
            var _t2336 = input.loc();
            var _t2337 = input.text();
            _v2334.append((_t2336, _t2337));
        }
        _f2328 = _v2334;
    }
    var _f2368 = HashMap<String, Array<bool>>();
    var _tag2369 = input.unsigned();
    if (_tag2369 == 1) {
        for (var (_bk2370, _bv) in base.caller_copies) {
            _f2368[_bk2370] = _bv;
        }
        var _v2371 = HashMap<String, Array<bool>>();
        var _n2372 = input.count();
        for (var _ in 0.._n2372) {
            var _k2373 = input.text();
            var _v2374 = Array<bool>();
            var _n2375 = input.count();
            for (var _ in 0.._n2375) {
                _v2374.append(input.flag());
            }
            _v2371[_k2373] = _v2374;
        }
        for (var (_bk2370, _av) in _v2371) {
            _f2368[_bk2370] = _av;
        }
    } else {
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
        _f2368 = _v2376;
    }
    var _f2382 = input.flag();
    return Module(
        _f1514,
        _f1547,
        _f1567,
        _f1586,
        _f1605,
        _f1624,
        _f1643,
        _f1662,
        _f1681,
        _f1700,
        _f1719,
        _f1731,
        _f1747,
        _f1766,
        _f1785,
        _f1804,
        _f1825,
        _f1854,
        _f1873,
        _f1886,
        _f1913,
        _f1960,
        _f2047,
        _f2073,
        _f2093,
        _f2119,
        _f2137,
        _f2163,
        _f2182,
        _f2195,
        _f2218,
        _f2242,
        _f2286,
        _f2287,
        _f2307,
        _f2316,
        _f2328,
        _f2368,
        _f2382
    );
}

_m_Module_index(value: Module, base: DeltaBase) {
    ulong _j1520 = 0;
    for (var _item1502 in value.imports) {
        var scratch = base.scratch();
        _a_Import_write(scratch, _item1502);
        base.add("imports", scratch, _j1520);
        _j1520 += 1;
    }
    if (base.verifying) {
        ulong _j1554 = 0;
        for (var _item1521 in value.structs) {
            var scratch = base.scratch();
            _m_StructDef_write(scratch, _item1521);
            base.add("s", scratch, _j1554);
            base.name("s", _item1521.name, _j1554);
            _patch_s_index(_item1521, base, _j1554);
            _j1554 += 1;
        }
    }
    base.ref_structs = value.structs.clone();
    base.ref_struct_parts = Array<StructDef>();
    for (var _item1521 in value.structs) {
        base.ref_struct_parts.append(_m_StructDef_shallow(_item1521));
    }
    ulong _j1573 = 0;
    for (var _item1555 in value.traits) {
        var scratch = base.scratch();
        _m_TraitDef_write(scratch, _item1555);
        base.add("traits", scratch, _j1573);
        _j1573 += 1;
    }
    ulong _j1592 = 0;
    for (var _item1574 in value.extensions) {
        var scratch = base.scratch();
        _m_ExtensionDef_write(scratch, _item1574);
        base.add("extensions", scratch, _j1592);
        _j1592 += 1;
    }
    if (base.verifying) {
        ulong _j1611 = 0;
        for (var _item1593 in value.functions) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item1593);
            base.add("functions", scratch, _j1611);
            base.name("functions", _item1593.name, _j1611);
            _j1611 += 1;
        }
    }
    base.ref_functions = value.functions.clone();
    ulong _j1630 = 0;
    for (var _item1612 in value.externs) {
        var scratch = base.scratch();
        _m_ExternDef_write(scratch, _item1612);
        base.add("externs", scratch, _j1630);
        _j1630 += 1;
    }
    ulong _j1649 = 0;
    for (var _item1631 in value.globals) {
        var scratch = base.scratch();
        _m_VariableDef_write(scratch, _item1631);
        base.add("globals", scratch, _j1649);
        _j1649 += 1;
    }
    ulong _j1668 = 0;
    for (var _item1650 in value.static_blocks) {
        var scratch = base.scratch();
        _m_ModuleStaticBlock_write(scratch, _item1650);
        base.add("static_blocks", scratch, _j1668);
        _j1668 += 1;
    }
    ulong _j1687 = 0;
    for (var _item1669 in value.enums) {
        var scratch = base.scratch();
        _m_EnumDef_write(scratch, _item1669);
        base.add("enums", scratch, _j1687);
        _j1687 += 1;
    }
    ulong _j1706 = 0;
    for (var _item1688 in value.struct_specs) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item1688);
        base.add("struct_specs", scratch, _j1706);
        _j1706 += 1;
    }
    ulong _j1725 = 0;
    for (var _item1707 in value.func_specs) {
        var scratch = base.scratch();
        _m_TypeName_write(scratch, _item1707);
        base.add("func_specs", scratch, _j1725);
        _j1725 += 1;
    }
    ulong _j1734 = 0;
    for (var _item1726 in value.type_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1726);
        base.add("type_aliases", scratch, _j1734);
        _j1734 += 1;
    }
    ulong _j1753 = 0;
    for (var _item1735 in value.withheld) {
        var scratch = base.scratch();
        _m_Withheld_write(scratch, _item1735);
        base.add("withheld", scratch, _j1753);
        _j1753 += 1;
    }
    ulong _j1772 = 0;
    for (var _item1754 in value.properties) {
        var scratch = base.scratch();
        _m_PropertyDef_write(scratch, _item1754);
        base.add("properties", scratch, _j1772);
        _j1772 += 1;
    }
    ulong _j1791 = 0;
    for (var _item1773 in value.type_uses) {
        var scratch = base.scratch();
        _m_TypeUse_write(scratch, _item1773);
        base.add("type_uses", scratch, _j1791);
        _j1791 += 1;
    }
    ulong _j1810 = 0;
    for (var _item1792 in value.use_contexts) {
        var scratch = base.scratch();
        _m_UseContext_write(scratch, _item1792);
        base.add("use_contexts", scratch, _j1810);
        _j1810 += 1;
    }
    var _xscratch1837 = base.scratch();
    for (var _xitem1838 in value.literal_args) {
        var (_t1839, _t1840, _t1841) = _xitem1838;
        _xscratch1837.loc(_t1839);
        _xscratch1837.unsigned(_t1840);
        _xscratch1837.loc(_t1841);
    }
    base.keep_list("literal_args", value.literal_args.count, _xscratch1837);
    ulong _j1860 = 0;
    for (var _item1842 in value.constrained_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1842);
        base.add("constrained_aliases", scratch, _j1860);
        _j1860 += 1;
    }
    ulong _j1879 = 0;
    for (var _item1861 in value.trait_types) {
        var scratch = base.scratch();
        _m_TraitType_write(scratch, _item1861);
        base.add("trait_types", scratch, _j1879);
        _j1879 += 1;
    }
    ulong _cj1883 = 0;
    for (var _conv1881 in value.conversions) {
        var _own1882 = RecordOut();
        _own1882.blank_locs = true;
        _m_Conversion_write(_own1882, _conv1881);
        base.add_hashed("conversions", interface_text(_own1882), _cj1883);
        _cj1883 += 1;
    }
    for (var (_key1887, _) in value.overload_sets) {
        var _kscratch1888 = base.scratch();
        _kscratch1888.text(_key1887);
        var _vscratch1889 = base.scratch();
        _vscratch1889.unsigned(value.overload_sets[_key1887].count);
        for (var _item1926 in value.overload_sets[_key1887]) {
            _vscratch1889.text(_item1926);
        }
        base.keep_entry("overload_sets", _kscratch1888, _vscratch1889);
    }
    for (var (_key1927, _) in value.overload_unions) {
        var _kscratch1928 = base.scratch();
        _kscratch1928.text(_key1927);
        var _vscratch1929 = base.scratch();
        _vscratch1929.unsigned(value.overload_unions[_key1927].count);
        for (var _item1977 in value.overload_unions[_key1927]) {
            _vscratch1929.unsigned(_item1977.count);
            for (var _item1978 in _item1977) {
                _vscratch1929.text(_item1978);
            }
        }
        base.keep_entry("overload_unions", _kscratch1928, _vscratch1929);
    }
    for (var (_key1979, _) in value.method_overload_sets) {
        var _kscratch1980 = base.scratch();
        _kscratch1980.text(_key1979);
        var _vscratch1981 = base.scratch();
        var _keys2067 = Array<(u8[], u8[], String)>();
        for (var (_key2066, _) in value.method_overload_sets[_key1979]) {
            var _scratch2068 = _vscratch1981.scratch();
            _scratch2068.text(_key2066);
            var _vscratch2070 = _vscratch1981.scratch();
            _vscratch2070.unsigned(value.method_overload_sets[_key1979][_key2066].count);
            for (var _item2071 in value.method_overload_sets[_key1979][_key2066]) {
                _vscratch2070.text(_item2071);
            }
            _keys2067.append((_scratch2068.finish(), _vscratch2070.finish(), _key2066));
        }
        _keys2067.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        _vscratch1981.unsigned(_keys2067.count);
        for (var (_bytes2069, _, _key2066) in _keys2067) {
            _vscratch1981.text(_key2066);
            _vscratch1981.unsigned(value.method_overload_sets[_key1979][_key2066].count);
            for (var _item2072 in value.method_overload_sets[_key1979][_key2066]) {
                _vscratch1981.text(_item2072);
            }
        }
        base.keep_entry("method_overload_sets", _kscratch1980, _vscratch1981);
    }
    for (var _key2074 in value.private_functions) {
        var _kscratch2075 = base.scratch();
        _kscratch2075.loc(_key2074);
        var _vscratch2076 = base.scratch();
        base.keep_entry("private_functions", _kscratch2075, _vscratch2076);
    }
    for (var _key2100 in value.file_private_functions) {
        var _kscratch2101 = base.scratch();
        _kscratch2101.loc(_key2100);
        var _vscratch2102 = base.scratch();
        base.keep_entry("file_private_functions", _kscratch2101, _vscratch2102);
    }
    var _xscratch2147 = base.scratch();
    for (var _xitem2148 in value.call_targets) {
        var (_t2149, _t2150) = _xitem2148;
        _xscratch2147.loc(_t2149);
        _xscratch2147.text(_t2150);
    }
    base.keep_list("call_targets", value.call_targets.count, _xscratch2147);
    for (var _item2151 in value.argument_names) {
        var _escratch2152 = base.scratch();
        var (_t2173, _t2174) = _item2151;
        _escratch2152.loc(_t2173);
        _escratch2152.text(_t2174);
        base.keep_entry("argument_names", _escratch2152, base.scratch());
    }
    var _xscratch2188 = base.scratch();
    for (var _xitem2189 in value.namespaces) {
        _xscratch2188.text(_xitem2189);
    }
    base.keep_list("namespaces", value.namespaces.count, _xscratch2188);
    var _xscratch2201 = base.scratch();
    for (var _xitem2202 in value.cached_files) {
        _xscratch2201.flag(_xitem2202);
    }
    base.keep_list("cached_files", value.cached_files.count, _xscratch2201);
    for (var (_key2203, _) in value.recorded_summaries) {
        var _kscratch2204 = base.scratch();
        _kscratch2204.loc(_key2203);
        var _vscratch2205 = base.scratch();
        _vscratch2205.text(value.recorded_summaries[_key2203]);
        base.keep_entry("recorded_summaries", _kscratch2204, _vscratch2205);
    }
    for (var _key2227 in value.stripped) {
        var _kscratch2228 = base.scratch();
        _kscratch2228.loc(_key2227);
        var _vscratch2229 = base.scratch();
        base.keep_entry("stripped", _kscratch2228, _vscratch2229);
    }
    if (base.verifying) {
        ulong _j2266 = 0;
        for (var _item2249 in value.templates.structs) {
            var scratch = base.scratch();
            _m_StructDef_write(scratch, _item2249);
            base.add("t", scratch, _j2266);
            base.name("t", _item2249.name, _j2266);
            _patch_t_index(_item2249, base, _j2266);
            _j2266 += 1;
        }
    }
    base.ref_templates = value.templates.structs.clone();
    base.ref_template_parts = Array<StructDef>();
    for (var _item2249 in value.templates.structs) {
        base.ref_template_parts.append(_m_StructDef_shallow(_item2249));
    }
    if (base.verifying) {
        ulong _j2285 = 0;
        for (var _item2267 in value.templates.functions) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2267);
            base.add("tf", scratch, _j2285);
            base.name("tf", _item2267.name, _j2285);
            _j2285 += 1;
        }
    }
    base.ref_template_functions = value.templates.functions.clone();
    base.keep_checked(value.checked);
    for (var (_key2288, _) in value.spec_requests) {
        var _kscratch2289 = base.scratch();
        _kscratch2289.text(_key2288);
        var _vscratch2290 = base.scratch();
        _m_SpecRequest_write(_vscratch2290, value.spec_requests[_key2288]);
        base.keep_entry("spec_requests", _kscratch2289, _vscratch2290);
    }
    var _xscratch2338 = base.scratch();
    for (var _xitem2339 in value.summaries_to_record) {
        var (_t2340, _t2341) = _xitem2339;
        _xscratch2338.loc(_t2340);
        _xscratch2338.text(_t2341);
    }
    base.keep_list("summaries_to_record", value.summaries_to_record.count, _xscratch2338);
    for (var (_key2342, _) in value.caller_copies) {
        var _kscratch2343 = base.scratch();
        _kscratch2343.text(_key2342);
        var _vscratch2344 = base.scratch();
        _vscratch2344.unsigned(value.caller_copies[_key2342].count);
        for (var _item2381 in value.caller_copies[_key2342]) {
            _vscratch2344.flag(_item2381);
        }
        base.keep_entry("caller_copies", _kscratch2343, _vscratch2344);
    }
}

_m_Module_index_resumed(value: Module, base: DeltaBase) {
    ulong _j1734 = 0;
    for (var _item1726 in value.type_aliases) {
        var scratch = base.scratch();
        _m_TypeAliasDef_write(scratch, _item1726);
        base.add("type_aliases", scratch, _j1734);
        _j1734 += 1;
    }
    for (var (_key2203, _) in value.recorded_summaries) {
        var _kscratch2204 = base.scratch();
        _kscratch2204.loc(_key2203);
        var _vscratch2205 = base.scratch();
        _vscratch2205.text(value.recorded_summaries[_key2203]);
        base.keep_entry("recorded_summaries", _kscratch2204, _vscratch2205);
    }
    var _xscratch2338 = base.scratch();
    for (var _xitem2339 in value.summaries_to_record) {
        var (_t2340, _t2341) = _xitem2339;
        _xscratch2338.loc(_t2340);
        _xscratch2338.text(_t2341);
    }
    base.keep_list("summaries_to_record", value.summaries_to_record.count, _xscratch2338);
}

_patch_s_write(out: RecordOut, value: StructDef, base: DeltaBase, slot: ulong) {
    out.text(value.name);
    _m_TypeName_write(out, value.ty);
    var _seq2390 = base.ref_struct_parts[slot].generic_params;
    ulong _bj2391 = 0;
    var _news2392 = Array<ulong>();
    for (var _i2393 in 0..value.generic_params.count) {
        if (_bj2391 < _seq2390.count and value.generic_params[_i2393] === _seq2390[_bj2391]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_GenericParam_write(scratch, value.generic_params[_i2393]);
                base.verify_same($"s.{slot}.generic_params", _bj2391, scratch);
            }
            _bj2391 += 1;
        } else if (_bj2391 < _seq2390.count
            and _same_m_GenericParam(value.generic_params[_i2393], _seq2390[_bj2391], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_GenericParam_write(scratch, value.generic_params[_i2393]);
                base.verify_same($"s.{slot}.generic_params", _bj2391, scratch);
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
            _m_GenericParam_write(out, value.generic_params[_i2393]);
        }
        base.count("s.*.generic_params" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.generic_params" + " whole", 0);
        out.unsigned(value.generic_params.count);
        for (var _i2393 in 0..value.generic_params.count) {
            _m_GenericParam_write(out, value.generic_params[_i2393]);
        }
    }
    var _seq2406 = base.ref_struct_parts[slot].field_members;
    ulong _bj2407 = 0;
    var _news2408 = Array<ulong>();
    for (var _i2409 in 0..value.field_members.count) {
        if (_bj2407 < _seq2406.count and value.field_members[_i2409] === _seq2406[_bj2407]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_VariableDef_write(scratch, value.field_members[_i2409]);
                base.verify_same($"s.{slot}.field_members", _bj2407, scratch);
            }
            _bj2407 += 1;
        } else if (_bj2407 < _seq2406.count
            and _same_m_VariableDef(value.field_members[_i2409], _seq2406[_bj2407], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_VariableDef_write(scratch, value.field_members[_i2409]);
                base.verify_same($"s.{slot}.field_members", _bj2407, scratch);
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
            _m_VariableDef_write(out, value.field_members[_i2409]);
        }
        base.count("s.*.field_members" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.field_members" + " whole", 0);
        out.unsigned(value.field_members.count);
        for (var _i2409 in 0..value.field_members.count) {
            _m_VariableDef_write(out, value.field_members[_i2409]);
        }
    }
    var _seq2422 = base.ref_struct_parts[slot].method_members;
    ulong _bj2423 = 0;
    var _news2424 = Array<ulong>();
    for (var _i2425 in 0..value.method_members.count) {
        if (_bj2423 < _seq2422.count and value.method_members[_i2425] === _seq2422[_bj2423]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.method_members[_i2425]);
                base.verify_same($"s.{slot}.method_members", _bj2423, scratch);
            }
            _bj2423 += 1;
        } else if (_bj2423 < _seq2422.count
            and _same_m_FunctionDef(value.method_members[_i2425], _seq2422[_bj2423], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.method_members[_i2425]);
                base.verify_same($"s.{slot}.method_members", _bj2423, scratch);
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
            _m_FunctionDef_write(out, value.method_members[_i2425]);
        }
        base.count("s.*.method_members" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.method_members" + " whole", 0);
        out.unsigned(value.method_members.count);
        for (var _i2425 in 0..value.method_members.count) {
            _m_FunctionDef_write(out, value.method_members[_i2425]);
        }
    }
    var _seq2438 = base.ref_struct_parts[slot].generic_methods;
    ulong _bj2439 = 0;
    var _news2440 = Array<ulong>();
    for (var _i2441 in 0..value.generic_methods.count) {
        if (_bj2439 < _seq2438.count and value.generic_methods[_i2441] === _seq2438[_bj2439]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.generic_methods[_i2441]);
                base.verify_same($"s.{slot}.generic_methods", _bj2439, scratch);
            }
            _bj2439 += 1;
        } else if (_bj2439 < _seq2438.count
            and _same_m_FunctionDef(value.generic_methods[_i2441], _seq2438[_bj2439], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.generic_methods[_i2441]);
                base.verify_same($"s.{slot}.generic_methods", _bj2439, scratch);
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
            _m_FunctionDef_write(out, value.generic_methods[_i2441]);
        }
        base.count("s.*.generic_methods" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.generic_methods" + " whole", 0);
        out.unsigned(value.generic_methods.count);
        for (var _i2441 in 0..value.generic_methods.count) {
            _m_FunctionDef_write(out, value.generic_methods[_i2441]);
        }
    }
    var _seq2454 = base.ref_struct_parts[slot].constructors;
    ulong _bj2455 = 0;
    var _news2456 = Array<ulong>();
    for (var _i2457 in 0..value.constructors.count) {
        if (_bj2455 < _seq2454.count and value.constructors[_i2457] === _seq2454[_bj2455]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.constructors[_i2457]);
                base.verify_same($"s.{slot}.constructors", _bj2455, scratch);
            }
            _bj2455 += 1;
        } else if (_bj2455 < _seq2454.count
            and _same_m_FunctionDef(value.constructors[_i2457], _seq2454[_bj2455], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.constructors[_i2457]);
                base.verify_same($"s.{slot}.constructors", _bj2455, scratch);
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
            _m_FunctionDef_write(out, value.constructors[_i2457]);
        }
        base.count("s.*.constructors" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.constructors" + " whole", 0);
        out.unsigned(value.constructors.count);
        for (var _i2457 in 0..value.constructors.count) {
            _m_FunctionDef_write(out, value.constructors[_i2457]);
        }
    }
    _m_FunctionDef_write(out, value.destructor);
    _m_FunctionDef_write(out, value.acquire);
    _m_FunctionDef_write(out, value.release);
    var _seq2473 = base.ref_struct_parts[slot].traits;
    ulong _bj2474 = 0;
    var _news2475 = Array<ulong>();
    for (var _i2476 in 0..value.traits.count) {
        if (_bj2474 < _seq2473.count and value.traits[_i2476] === _seq2473[_bj2474]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_TypeName_write(scratch, value.traits[_i2476]);
                base.verify_same($"s.{slot}.traits", _bj2474, scratch);
            }
            _bj2474 += 1;
        } else if (_bj2474 < _seq2473.count and _same_m_TypeName(value.traits[_i2476], _seq2473[_bj2474], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_TypeName_write(scratch, value.traits[_i2476]);
                base.verify_same($"s.{slot}.traits", _bj2474, scratch);
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
            _m_TypeName_write(out, value.traits[_i2476]);
        }
        base.count("s.*.traits" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.traits" + " whole", 0);
        out.unsigned(value.traits.count);
        for (var _i2476 in 0..value.traits.count) {
            _m_TypeName_write(out, value.traits[_i2476]);
        }
    }
    var _seq2489 = base.ref_struct_parts[slot].attributes;
    ulong _bj2490 = 0;
    var _news2491 = Array<ulong>();
    for (var _i2492 in 0..value.attributes.count) {
        if (_bj2490 < _seq2489.count and value.attributes[_i2492] === _seq2489[_bj2490]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _a_Attribute_write(scratch, value.attributes[_i2492]);
                base.verify_same($"s.{slot}.attributes", _bj2490, scratch);
            }
            _bj2490 += 1;
        } else if (_bj2490 < _seq2489.count and _same_a_Attribute(value.attributes[_i2492], _seq2489[_bj2490], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _a_Attribute_write(scratch, value.attributes[_i2492]);
                base.verify_same($"s.{slot}.attributes", _bj2490, scratch);
            }
            _bj2490 += 1;
        } else {
            _news2491.append(_i2492);
        }
    }
    if (_bj2490 == _seq2489.count) {
        out.unsigned(2);
        out.unsigned(_news2491.count);
        for (var _i2492 in _news2491) {
            out.unsigned(_i2492);
            _a_Attribute_write(out, value.attributes[_i2492]);
        }
        base.count("s.*.attributes" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("s.*.attributes" + " whole", 0);
        out.unsigned(value.attributes.count);
        for (var _i2492 in 0..value.attributes.count) {
            _a_Attribute_write(out, value.attributes[_i2492]);
        }
    }
    out.loc(value.loc);
    if (value.enum_cases.is_value()) {
        out.unsigned(1);
        out.unsigned(value.enum_cases.value().count);
        for (var _item2501 in value.enum_cases.value()) {
            _m_EnumCaseDef_write(out, _item2501);
        }
    } else {
        out.unsigned(0);
    }
}

_patch_s_read(input: RecordIn, was: StructDef): StructDef {
    var _f2383 = input.text();
    var _f2384 = _m_TypeName_read(input);
    var _f2394 = Array<GenericParam>();
    var _mode2397 = input.unsigned();
    if (_mode2397 == 2) {
        var _changed2386 = HashMap<ulong, GenericParam>();
        ulong _bi2398 = 0;
        var _n2395 = input.count();
        for (var _ in 0.._n2395) {
            var _at2399 = input.unsigned();
            while (_f2394.count < _at2399 or (input.merging and _bi2398 < was.generic_params.count)) {
                var _c = _changed2386.try_get(_bi2398);
                _f2394.append(_c.is_value() ? _c.value() : was.generic_params[_bi2398]);
                _bi2398 += 1;
            }
            _f2394.append(_m_GenericParam_read(input));
        }
        while (_bi2398 < was.generic_params.count) {
            var _c = _changed2386.try_get(_bi2398);
            _f2394.append(_c.is_value() ? _c.value() : was.generic_params[_bi2398]);
            _bi2398 += 1;
        }
    } else if (_mode2397 == 3) {
        var _n2395 = input.count();
        for (var _ in 0.._n2395) {
            _f2394.append(_m_GenericParam_read(input));
        }
    } else {
        var _n2395 = input.count();
        if (input.merging) {
            input.error = "s.*.generic_params" + " written by place";
        }
        for (var _ in 0.._n2395) {
            var _tag2396 = input.unsigned();
            if (_tag2396 & 1 == 1) {
                if (!input.merging) {
                    _f2394.append(was.generic_params[_tag2396 >> 1]);
                }
            } else {
                var _read = _m_GenericParam_read(input);
                if (!input.merging or true) {
                    _f2394.append(_read);
                }
            }
        }
    }
    var _f2410 = Array<VariableDef>();
    var _mode2413 = input.unsigned();
    if (_mode2413 == 2) {
        var _changed2402 = HashMap<ulong, VariableDef>();
        ulong _bi2414 = 0;
        var _n2411 = input.count();
        for (var _ in 0.._n2411) {
            var _at2415 = input.unsigned();
            while (_f2410.count < _at2415 or (input.merging and _bi2414 < was.field_members.count)) {
                var _c = _changed2402.try_get(_bi2414);
                _f2410.append(_c.is_value() ? _c.value() : was.field_members[_bi2414]);
                _bi2414 += 1;
            }
            _f2410.append(_m_VariableDef_read(input));
        }
        while (_bi2414 < was.field_members.count) {
            var _c = _changed2402.try_get(_bi2414);
            _f2410.append(_c.is_value() ? _c.value() : was.field_members[_bi2414]);
            _bi2414 += 1;
        }
    } else if (_mode2413 == 3) {
        var _n2411 = input.count();
        for (var _ in 0.._n2411) {
            _f2410.append(_m_VariableDef_read(input));
        }
    } else {
        var _n2411 = input.count();
        if (input.merging) {
            input.error = "s.*.field_members" + " written by place";
        }
        for (var _ in 0.._n2411) {
            var _tag2412 = input.unsigned();
            if (_tag2412 & 1 == 1) {
                if (!input.merging) {
                    _f2410.append(was.field_members[_tag2412 >> 1]);
                }
            } else {
                var _read = _m_VariableDef_read(input);
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
            while (_f2426.count < _at2431 or (input.merging and _bi2430 < was.method_members.count)) {
                var _c = _changed2418.try_get(_bi2430);
                _f2426.append(_c.is_value() ? _c.value() : was.method_members[_bi2430]);
                _bi2430 += 1;
            }
            _f2426.append(_m_FunctionDef_read(input));
        }
        while (_bi2430 < was.method_members.count) {
            var _c = _changed2418.try_get(_bi2430);
            _f2426.append(_c.is_value() ? _c.value() : was.method_members[_bi2430]);
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
            input.error = "s.*.method_members" + " written by place";
        }
        for (var _ in 0.._n2427) {
            var _tag2428 = input.unsigned();
            if (_tag2428 & 1 == 1) {
                if (!input.merging) {
                    _f2426.append(was.method_members[_tag2428 >> 1]);
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
            while (_f2442.count < _at2447 or (input.merging and _bi2446 < was.generic_methods.count)) {
                var _c = _changed2434.try_get(_bi2446);
                _f2442.append(_c.is_value() ? _c.value() : was.generic_methods[_bi2446]);
                _bi2446 += 1;
            }
            _f2442.append(_m_FunctionDef_read(input));
        }
        while (_bi2446 < was.generic_methods.count) {
            var _c = _changed2434.try_get(_bi2446);
            _f2442.append(_c.is_value() ? _c.value() : was.generic_methods[_bi2446]);
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
            input.error = "s.*.generic_methods" + " written by place";
        }
        for (var _ in 0.._n2443) {
            var _tag2444 = input.unsigned();
            if (_tag2444 & 1 == 1) {
                if (!input.merging) {
                    _f2442.append(was.generic_methods[_tag2444 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2442.append(_read);
                }
            }
        }
    }
    var _f2458 = Array<FunctionDef>();
    var _mode2461 = input.unsigned();
    if (_mode2461 == 2) {
        var _changed2450 = HashMap<ulong, FunctionDef>();
        ulong _bi2462 = 0;
        var _n2459 = input.count();
        for (var _ in 0.._n2459) {
            var _at2463 = input.unsigned();
            while (_f2458.count < _at2463 or (input.merging and _bi2462 < was.constructors.count)) {
                var _c = _changed2450.try_get(_bi2462);
                _f2458.append(_c.is_value() ? _c.value() : was.constructors[_bi2462]);
                _bi2462 += 1;
            }
            _f2458.append(_m_FunctionDef_read(input));
        }
        while (_bi2462 < was.constructors.count) {
            var _c = _changed2450.try_get(_bi2462);
            _f2458.append(_c.is_value() ? _c.value() : was.constructors[_bi2462]);
            _bi2462 += 1;
        }
    } else if (_mode2461 == 3) {
        var _n2459 = input.count();
        for (var _ in 0.._n2459) {
            _f2458.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2459 = input.count();
        if (input.merging) {
            input.error = "s.*.constructors" + " written by place";
        }
        for (var _ in 0.._n2459) {
            var _tag2460 = input.unsigned();
            if (_tag2460 & 1 == 1) {
                if (!input.merging) {
                    _f2458.append(was.constructors[_tag2460 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2458.append(_read);
                }
            }
        }
    }
    var _f2465 = _m_FunctionDef_read(input);
    var _f2466 = _m_FunctionDef_read(input);
    var _f2467 = _m_FunctionDef_read(input);
    var _f2477 = Array<TypeName>();
    var _mode2480 = input.unsigned();
    if (_mode2480 == 2) {
        var _changed2469 = HashMap<ulong, TypeName>();
        ulong _bi2481 = 0;
        var _n2478 = input.count();
        for (var _ in 0.._n2478) {
            var _at2482 = input.unsigned();
            while (_f2477.count < _at2482 or (input.merging and _bi2481 < was.traits.count)) {
                var _c = _changed2469.try_get(_bi2481);
                _f2477.append(_c.is_value() ? _c.value() : was.traits[_bi2481]);
                _bi2481 += 1;
            }
            _f2477.append(_m_TypeName_read(input));
        }
        while (_bi2481 < was.traits.count) {
            var _c = _changed2469.try_get(_bi2481);
            _f2477.append(_c.is_value() ? _c.value() : was.traits[_bi2481]);
            _bi2481 += 1;
        }
    } else if (_mode2480 == 3) {
        var _n2478 = input.count();
        for (var _ in 0.._n2478) {
            _f2477.append(_m_TypeName_read(input));
        }
    } else {
        var _n2478 = input.count();
        if (input.merging) {
            input.error = "s.*.traits" + " written by place";
        }
        for (var _ in 0.._n2478) {
            var _tag2479 = input.unsigned();
            if (_tag2479 & 1 == 1) {
                if (!input.merging) {
                    _f2477.append(was.traits[_tag2479 >> 1]);
                }
            } else {
                var _read = _m_TypeName_read(input);
                if (!input.merging or true) {
                    _f2477.append(_read);
                }
            }
        }
    }
    var _f2493 = Array<ast.Attribute>();
    var _mode2496 = input.unsigned();
    if (_mode2496 == 2) {
        var _changed2485 = HashMap<ulong, ast.Attribute>();
        ulong _bi2497 = 0;
        var _n2494 = input.count();
        for (var _ in 0.._n2494) {
            var _at2498 = input.unsigned();
            while (_f2493.count < _at2498 or (input.merging and _bi2497 < was.attributes.count)) {
                var _c = _changed2485.try_get(_bi2497);
                _f2493.append(_c.is_value() ? _c.value() : was.attributes[_bi2497]);
                _bi2497 += 1;
            }
            _f2493.append(_a_Attribute_read(input));
        }
        while (_bi2497 < was.attributes.count) {
            var _c = _changed2485.try_get(_bi2497);
            _f2493.append(_c.is_value() ? _c.value() : was.attributes[_bi2497]);
            _bi2497 += 1;
        }
    } else if (_mode2496 == 3) {
        var _n2494 = input.count();
        for (var _ in 0.._n2494) {
            _f2493.append(_a_Attribute_read(input));
        }
    } else {
        var _n2494 = input.count();
        if (input.merging) {
            input.error = "s.*.attributes" + " written by place";
        }
        for (var _ in 0.._n2494) {
            var _tag2495 = input.unsigned();
            if (_tag2495 & 1 == 1) {
                if (!input.merging) {
                    _f2493.append(was.attributes[_tag2495 >> 1]);
                }
            } else {
                var _read = _a_Attribute_read(input);
                if (!input.merging or true) {
                    _f2493.append(_read);
                }
            }
        }
    }
    var _f2500 = input.loc();
    var _o2502 = Optional<Array<EnumCaseDef>>.Empty;
    if (input.unsigned() == 1) {
        var _v2503 = Array<EnumCaseDef>();
        var _n2504 = input.count();
        for (var _ in 0.._n2504) {
            _v2503.append(_m_EnumCaseDef_read(input));
        }
        _o2502 = Optional<Array<EnumCaseDef>>.Value(_v2503);
    }
    var _f2505 = _o2502;
    return StructDef(
        _f2383, _f2384, _f2394, _f2410, _f2426, _f2442, _f2458, _f2465, _f2466, _f2467, _f2477, _f2493, _f2500, _f2505
    );
}

_patch_s_index(value: StructDef, base: DeltaBase, slot: ulong) {
    if (base.verifying) {
        ulong _j2400 = 0;
        for (var _item2385 in value.generic_params) {
            var scratch = base.scratch();
            _m_GenericParam_write(scratch, _item2385);
            base.add($"s.{slot}.generic_params", scratch, _j2400);
            _j2400 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2416 = 0;
        for (var _item2401 in value.field_members) {
            var scratch = base.scratch();
            _m_VariableDef_write(scratch, _item2401);
            base.add($"s.{slot}.field_members", scratch, _j2416);
            _j2416 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2432 = 0;
        for (var _item2417 in value.method_members) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2417);
            base.add($"s.{slot}.method_members", scratch, _j2432);
            _j2432 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2448 = 0;
        for (var _item2433 in value.generic_methods) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2433);
            base.add($"s.{slot}.generic_methods", scratch, _j2448);
            _j2448 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2464 = 0;
        for (var _item2449 in value.constructors) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2449);
            base.add($"s.{slot}.constructors", scratch, _j2464);
            _j2464 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2483 = 0;
        for (var _item2468 in value.traits) {
            var scratch = base.scratch();
            _m_TypeName_write(scratch, _item2468);
            base.add($"s.{slot}.traits", scratch, _j2483);
            _j2483 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2499 = 0;
        for (var _item2484 in value.attributes) {
            var scratch = base.scratch();
            _a_Attribute_write(scratch, _item2484);
            base.add($"s.{slot}.attributes", scratch, _j2499);
            _j2499 += 1;
        }
    }
}

_patch_t_write(out: RecordOut, value: StructDef, base: DeltaBase, slot: ulong) {
    out.text(value.name);
    _m_TypeName_write(out, value.ty);
    var _seq2513 = base.ref_template_parts[slot].generic_params;
    ulong _bj2514 = 0;
    var _news2515 = Array<ulong>();
    for (var _i2516 in 0..value.generic_params.count) {
        if (_bj2514 < _seq2513.count and value.generic_params[_i2516] === _seq2513[_bj2514]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_GenericParam_write(scratch, value.generic_params[_i2516]);
                base.verify_same($"t.{slot}.generic_params", _bj2514, scratch);
            }
            _bj2514 += 1;
        } else if (_bj2514 < _seq2513.count
            and _same_m_GenericParam(value.generic_params[_i2516], _seq2513[_bj2514], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_GenericParam_write(scratch, value.generic_params[_i2516]);
                base.verify_same($"t.{slot}.generic_params", _bj2514, scratch);
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
            _m_GenericParam_write(out, value.generic_params[_i2516]);
        }
        base.count("t.*.generic_params" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.generic_params" + " whole", 0);
        out.unsigned(value.generic_params.count);
        for (var _i2516 in 0..value.generic_params.count) {
            _m_GenericParam_write(out, value.generic_params[_i2516]);
        }
    }
    var _seq2529 = base.ref_template_parts[slot].field_members;
    ulong _bj2530 = 0;
    var _news2531 = Array<ulong>();
    for (var _i2532 in 0..value.field_members.count) {
        if (_bj2530 < _seq2529.count and value.field_members[_i2532] === _seq2529[_bj2530]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_VariableDef_write(scratch, value.field_members[_i2532]);
                base.verify_same($"t.{slot}.field_members", _bj2530, scratch);
            }
            _bj2530 += 1;
        } else if (_bj2530 < _seq2529.count
            and _same_m_VariableDef(value.field_members[_i2532], _seq2529[_bj2530], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_VariableDef_write(scratch, value.field_members[_i2532]);
                base.verify_same($"t.{slot}.field_members", _bj2530, scratch);
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
            _m_VariableDef_write(out, value.field_members[_i2532]);
        }
        base.count("t.*.field_members" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.field_members" + " whole", 0);
        out.unsigned(value.field_members.count);
        for (var _i2532 in 0..value.field_members.count) {
            _m_VariableDef_write(out, value.field_members[_i2532]);
        }
    }
    var _seq2545 = base.ref_template_parts[slot].method_members;
    ulong _bj2546 = 0;
    var _news2547 = Array<ulong>();
    for (var _i2548 in 0..value.method_members.count) {
        if (_bj2546 < _seq2545.count and value.method_members[_i2548] === _seq2545[_bj2546]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.method_members[_i2548]);
                base.verify_same($"t.{slot}.method_members", _bj2546, scratch);
            }
            _bj2546 += 1;
        } else if (_bj2546 < _seq2545.count
            and _same_m_FunctionDef(value.method_members[_i2548], _seq2545[_bj2546], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.method_members[_i2548]);
                base.verify_same($"t.{slot}.method_members", _bj2546, scratch);
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
            _m_FunctionDef_write(out, value.method_members[_i2548]);
        }
        base.count("t.*.method_members" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.method_members" + " whole", 0);
        out.unsigned(value.method_members.count);
        for (var _i2548 in 0..value.method_members.count) {
            _m_FunctionDef_write(out, value.method_members[_i2548]);
        }
    }
    var _seq2561 = base.ref_template_parts[slot].generic_methods;
    ulong _bj2562 = 0;
    var _news2563 = Array<ulong>();
    for (var _i2564 in 0..value.generic_methods.count) {
        if (_bj2562 < _seq2561.count and value.generic_methods[_i2564] === _seq2561[_bj2562]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.generic_methods[_i2564]);
                base.verify_same($"t.{slot}.generic_methods", _bj2562, scratch);
            }
            _bj2562 += 1;
        } else if (_bj2562 < _seq2561.count
            and _same_m_FunctionDef(value.generic_methods[_i2564], _seq2561[_bj2562], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.generic_methods[_i2564]);
                base.verify_same($"t.{slot}.generic_methods", _bj2562, scratch);
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
            _m_FunctionDef_write(out, value.generic_methods[_i2564]);
        }
        base.count("t.*.generic_methods" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.generic_methods" + " whole", 0);
        out.unsigned(value.generic_methods.count);
        for (var _i2564 in 0..value.generic_methods.count) {
            _m_FunctionDef_write(out, value.generic_methods[_i2564]);
        }
    }
    var _seq2577 = base.ref_template_parts[slot].constructors;
    ulong _bj2578 = 0;
    var _news2579 = Array<ulong>();
    for (var _i2580 in 0..value.constructors.count) {
        if (_bj2578 < _seq2577.count and value.constructors[_i2580] === _seq2577[_bj2578]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.constructors[_i2580]);
                base.verify_same($"t.{slot}.constructors", _bj2578, scratch);
            }
            _bj2578 += 1;
        } else if (_bj2578 < _seq2577.count
            and _same_m_FunctionDef(value.constructors[_i2580], _seq2577[_bj2578], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_FunctionDef_write(scratch, value.constructors[_i2580]);
                base.verify_same($"t.{slot}.constructors", _bj2578, scratch);
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
            _m_FunctionDef_write(out, value.constructors[_i2580]);
        }
        base.count("t.*.constructors" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.constructors" + " whole", 0);
        out.unsigned(value.constructors.count);
        for (var _i2580 in 0..value.constructors.count) {
            _m_FunctionDef_write(out, value.constructors[_i2580]);
        }
    }
    _m_FunctionDef_write(out, value.destructor);
    _m_FunctionDef_write(out, value.acquire);
    _m_FunctionDef_write(out, value.release);
    var _seq2596 = base.ref_template_parts[slot].traits;
    ulong _bj2597 = 0;
    var _news2598 = Array<ulong>();
    for (var _i2599 in 0..value.traits.count) {
        if (_bj2597 < _seq2596.count and value.traits[_i2599] === _seq2596[_bj2597]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_TypeName_write(scratch, value.traits[_i2599]);
                base.verify_same($"t.{slot}.traits", _bj2597, scratch);
            }
            _bj2597 += 1;
        } else if (_bj2597 < _seq2596.count and _same_m_TypeName(value.traits[_i2599], _seq2596[_bj2597], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _m_TypeName_write(scratch, value.traits[_i2599]);
                base.verify_same($"t.{slot}.traits", _bj2597, scratch);
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
            _m_TypeName_write(out, value.traits[_i2599]);
        }
        base.count("t.*.traits" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.traits" + " whole", 0);
        out.unsigned(value.traits.count);
        for (var _i2599 in 0..value.traits.count) {
            _m_TypeName_write(out, value.traits[_i2599]);
        }
    }
    var _seq2612 = base.ref_template_parts[slot].attributes;
    ulong _bj2613 = 0;
    var _news2614 = Array<ulong>();
    for (var _i2615 in 0..value.attributes.count) {
        if (_bj2613 < _seq2612.count and value.attributes[_i2615] === _seq2612[_bj2613]) {
            if (base.verifying) {
                var scratch = base.scratch();
                _a_Attribute_write(scratch, value.attributes[_i2615]);
                base.verify_same($"t.{slot}.attributes", _bj2613, scratch);
            }
            _bj2613 += 1;
        } else if (_bj2613 < _seq2612.count and _same_a_Attribute(value.attributes[_i2615], _seq2612[_bj2613], base)) {
            if (base.verifying) {
                var scratch = base.scratch();
                _a_Attribute_write(scratch, value.attributes[_i2615]);
                base.verify_same($"t.{slot}.attributes", _bj2613, scratch);
            }
            _bj2613 += 1;
        } else {
            _news2614.append(_i2615);
        }
    }
    if (_bj2613 == _seq2612.count) {
        out.unsigned(2);
        out.unsigned(_news2614.count);
        for (var _i2615 in _news2614) {
            out.unsigned(_i2615);
            _a_Attribute_write(out, value.attributes[_i2615]);
        }
        base.count("t.*.attributes" + " merged", 0);
    } else {
        # Not the base's elements in order: whole, which reading takes
        # in place of the base's, whatever the base.
        out.unsigned(3);
        base.count("t.*.attributes" + " whole", 0);
        out.unsigned(value.attributes.count);
        for (var _i2615 in 0..value.attributes.count) {
            _a_Attribute_write(out, value.attributes[_i2615]);
        }
    }
    out.loc(value.loc);
    if (value.enum_cases.is_value()) {
        out.unsigned(1);
        out.unsigned(value.enum_cases.value().count);
        for (var _item2624 in value.enum_cases.value()) {
            _m_EnumCaseDef_write(out, _item2624);
        }
    } else {
        out.unsigned(0);
    }
}

_patch_t_read(input: RecordIn, was: StructDef): StructDef {
    var _f2506 = input.text();
    var _f2507 = _m_TypeName_read(input);
    var _f2517 = Array<GenericParam>();
    var _mode2520 = input.unsigned();
    if (_mode2520 == 2) {
        var _changed2509 = HashMap<ulong, GenericParam>();
        ulong _bi2521 = 0;
        var _n2518 = input.count();
        for (var _ in 0.._n2518) {
            var _at2522 = input.unsigned();
            while (_f2517.count < _at2522 or (input.merging and _bi2521 < was.generic_params.count)) {
                var _c = _changed2509.try_get(_bi2521);
                _f2517.append(_c.is_value() ? _c.value() : was.generic_params[_bi2521]);
                _bi2521 += 1;
            }
            _f2517.append(_m_GenericParam_read(input));
        }
        while (_bi2521 < was.generic_params.count) {
            var _c = _changed2509.try_get(_bi2521);
            _f2517.append(_c.is_value() ? _c.value() : was.generic_params[_bi2521]);
            _bi2521 += 1;
        }
    } else if (_mode2520 == 3) {
        var _n2518 = input.count();
        for (var _ in 0.._n2518) {
            _f2517.append(_m_GenericParam_read(input));
        }
    } else {
        var _n2518 = input.count();
        if (input.merging) {
            input.error = "t.*.generic_params" + " written by place";
        }
        for (var _ in 0.._n2518) {
            var _tag2519 = input.unsigned();
            if (_tag2519 & 1 == 1) {
                if (!input.merging) {
                    _f2517.append(was.generic_params[_tag2519 >> 1]);
                }
            } else {
                var _read = _m_GenericParam_read(input);
                if (!input.merging or true) {
                    _f2517.append(_read);
                }
            }
        }
    }
    var _f2533 = Array<VariableDef>();
    var _mode2536 = input.unsigned();
    if (_mode2536 == 2) {
        var _changed2525 = HashMap<ulong, VariableDef>();
        ulong _bi2537 = 0;
        var _n2534 = input.count();
        for (var _ in 0.._n2534) {
            var _at2538 = input.unsigned();
            while (_f2533.count < _at2538 or (input.merging and _bi2537 < was.field_members.count)) {
                var _c = _changed2525.try_get(_bi2537);
                _f2533.append(_c.is_value() ? _c.value() : was.field_members[_bi2537]);
                _bi2537 += 1;
            }
            _f2533.append(_m_VariableDef_read(input));
        }
        while (_bi2537 < was.field_members.count) {
            var _c = _changed2525.try_get(_bi2537);
            _f2533.append(_c.is_value() ? _c.value() : was.field_members[_bi2537]);
            _bi2537 += 1;
        }
    } else if (_mode2536 == 3) {
        var _n2534 = input.count();
        for (var _ in 0.._n2534) {
            _f2533.append(_m_VariableDef_read(input));
        }
    } else {
        var _n2534 = input.count();
        if (input.merging) {
            input.error = "t.*.field_members" + " written by place";
        }
        for (var _ in 0.._n2534) {
            var _tag2535 = input.unsigned();
            if (_tag2535 & 1 == 1) {
                if (!input.merging) {
                    _f2533.append(was.field_members[_tag2535 >> 1]);
                }
            } else {
                var _read = _m_VariableDef_read(input);
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
            while (_f2549.count < _at2554 or (input.merging and _bi2553 < was.method_members.count)) {
                var _c = _changed2541.try_get(_bi2553);
                _f2549.append(_c.is_value() ? _c.value() : was.method_members[_bi2553]);
                _bi2553 += 1;
            }
            _f2549.append(_m_FunctionDef_read(input));
        }
        while (_bi2553 < was.method_members.count) {
            var _c = _changed2541.try_get(_bi2553);
            _f2549.append(_c.is_value() ? _c.value() : was.method_members[_bi2553]);
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
            input.error = "t.*.method_members" + " written by place";
        }
        for (var _ in 0.._n2550) {
            var _tag2551 = input.unsigned();
            if (_tag2551 & 1 == 1) {
                if (!input.merging) {
                    _f2549.append(was.method_members[_tag2551 >> 1]);
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
            while (_f2565.count < _at2570 or (input.merging and _bi2569 < was.generic_methods.count)) {
                var _c = _changed2557.try_get(_bi2569);
                _f2565.append(_c.is_value() ? _c.value() : was.generic_methods[_bi2569]);
                _bi2569 += 1;
            }
            _f2565.append(_m_FunctionDef_read(input));
        }
        while (_bi2569 < was.generic_methods.count) {
            var _c = _changed2557.try_get(_bi2569);
            _f2565.append(_c.is_value() ? _c.value() : was.generic_methods[_bi2569]);
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
            input.error = "t.*.generic_methods" + " written by place";
        }
        for (var _ in 0.._n2566) {
            var _tag2567 = input.unsigned();
            if (_tag2567 & 1 == 1) {
                if (!input.merging) {
                    _f2565.append(was.generic_methods[_tag2567 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2565.append(_read);
                }
            }
        }
    }
    var _f2581 = Array<FunctionDef>();
    var _mode2584 = input.unsigned();
    if (_mode2584 == 2) {
        var _changed2573 = HashMap<ulong, FunctionDef>();
        ulong _bi2585 = 0;
        var _n2582 = input.count();
        for (var _ in 0.._n2582) {
            var _at2586 = input.unsigned();
            while (_f2581.count < _at2586 or (input.merging and _bi2585 < was.constructors.count)) {
                var _c = _changed2573.try_get(_bi2585);
                _f2581.append(_c.is_value() ? _c.value() : was.constructors[_bi2585]);
                _bi2585 += 1;
            }
            _f2581.append(_m_FunctionDef_read(input));
        }
        while (_bi2585 < was.constructors.count) {
            var _c = _changed2573.try_get(_bi2585);
            _f2581.append(_c.is_value() ? _c.value() : was.constructors[_bi2585]);
            _bi2585 += 1;
        }
    } else if (_mode2584 == 3) {
        var _n2582 = input.count();
        for (var _ in 0.._n2582) {
            _f2581.append(_m_FunctionDef_read(input));
        }
    } else {
        var _n2582 = input.count();
        if (input.merging) {
            input.error = "t.*.constructors" + " written by place";
        }
        for (var _ in 0.._n2582) {
            var _tag2583 = input.unsigned();
            if (_tag2583 & 1 == 1) {
                if (!input.merging) {
                    _f2581.append(was.constructors[_tag2583 >> 1]);
                }
            } else {
                var _read = _m_FunctionDef_read(input);
                if (!input.merging or true) {
                    _f2581.append(_read);
                }
            }
        }
    }
    var _f2588 = _m_FunctionDef_read(input);
    var _f2589 = _m_FunctionDef_read(input);
    var _f2590 = _m_FunctionDef_read(input);
    var _f2600 = Array<TypeName>();
    var _mode2603 = input.unsigned();
    if (_mode2603 == 2) {
        var _changed2592 = HashMap<ulong, TypeName>();
        ulong _bi2604 = 0;
        var _n2601 = input.count();
        for (var _ in 0.._n2601) {
            var _at2605 = input.unsigned();
            while (_f2600.count < _at2605 or (input.merging and _bi2604 < was.traits.count)) {
                var _c = _changed2592.try_get(_bi2604);
                _f2600.append(_c.is_value() ? _c.value() : was.traits[_bi2604]);
                _bi2604 += 1;
            }
            _f2600.append(_m_TypeName_read(input));
        }
        while (_bi2604 < was.traits.count) {
            var _c = _changed2592.try_get(_bi2604);
            _f2600.append(_c.is_value() ? _c.value() : was.traits[_bi2604]);
            _bi2604 += 1;
        }
    } else if (_mode2603 == 3) {
        var _n2601 = input.count();
        for (var _ in 0.._n2601) {
            _f2600.append(_m_TypeName_read(input));
        }
    } else {
        var _n2601 = input.count();
        if (input.merging) {
            input.error = "t.*.traits" + " written by place";
        }
        for (var _ in 0.._n2601) {
            var _tag2602 = input.unsigned();
            if (_tag2602 & 1 == 1) {
                if (!input.merging) {
                    _f2600.append(was.traits[_tag2602 >> 1]);
                }
            } else {
                var _read = _m_TypeName_read(input);
                if (!input.merging or true) {
                    _f2600.append(_read);
                }
            }
        }
    }
    var _f2616 = Array<ast.Attribute>();
    var _mode2619 = input.unsigned();
    if (_mode2619 == 2) {
        var _changed2608 = HashMap<ulong, ast.Attribute>();
        ulong _bi2620 = 0;
        var _n2617 = input.count();
        for (var _ in 0.._n2617) {
            var _at2621 = input.unsigned();
            while (_f2616.count < _at2621 or (input.merging and _bi2620 < was.attributes.count)) {
                var _c = _changed2608.try_get(_bi2620);
                _f2616.append(_c.is_value() ? _c.value() : was.attributes[_bi2620]);
                _bi2620 += 1;
            }
            _f2616.append(_a_Attribute_read(input));
        }
        while (_bi2620 < was.attributes.count) {
            var _c = _changed2608.try_get(_bi2620);
            _f2616.append(_c.is_value() ? _c.value() : was.attributes[_bi2620]);
            _bi2620 += 1;
        }
    } else if (_mode2619 == 3) {
        var _n2617 = input.count();
        for (var _ in 0.._n2617) {
            _f2616.append(_a_Attribute_read(input));
        }
    } else {
        var _n2617 = input.count();
        if (input.merging) {
            input.error = "t.*.attributes" + " written by place";
        }
        for (var _ in 0.._n2617) {
            var _tag2618 = input.unsigned();
            if (_tag2618 & 1 == 1) {
                if (!input.merging) {
                    _f2616.append(was.attributes[_tag2618 >> 1]);
                }
            } else {
                var _read = _a_Attribute_read(input);
                if (!input.merging or true) {
                    _f2616.append(_read);
                }
            }
        }
    }
    var _f2623 = input.loc();
    var _o2625 = Optional<Array<EnumCaseDef>>.Empty;
    if (input.unsigned() == 1) {
        var _v2626 = Array<EnumCaseDef>();
        var _n2627 = input.count();
        for (var _ in 0.._n2627) {
            _v2626.append(_m_EnumCaseDef_read(input));
        }
        _o2625 = Optional<Array<EnumCaseDef>>.Value(_v2626);
    }
    var _f2628 = _o2625;
    return StructDef(
        _f2506, _f2507, _f2517, _f2533, _f2549, _f2565, _f2581, _f2588, _f2589, _f2590, _f2600, _f2616, _f2623, _f2628
    );
}

_patch_t_index(value: StructDef, base: DeltaBase, slot: ulong) {
    if (base.verifying) {
        ulong _j2523 = 0;
        for (var _item2508 in value.generic_params) {
            var scratch = base.scratch();
            _m_GenericParam_write(scratch, _item2508);
            base.add($"t.{slot}.generic_params", scratch, _j2523);
            _j2523 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2539 = 0;
        for (var _item2524 in value.field_members) {
            var scratch = base.scratch();
            _m_VariableDef_write(scratch, _item2524);
            base.add($"t.{slot}.field_members", scratch, _j2539);
            _j2539 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2555 = 0;
        for (var _item2540 in value.method_members) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2540);
            base.add($"t.{slot}.method_members", scratch, _j2555);
            _j2555 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2571 = 0;
        for (var _item2556 in value.generic_methods) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2556);
            base.add($"t.{slot}.generic_methods", scratch, _j2571);
            _j2571 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2587 = 0;
        for (var _item2572 in value.constructors) {
            var scratch = base.scratch();
            _m_FunctionDef_write(scratch, _item2572);
            base.add($"t.{slot}.constructors", scratch, _j2587);
            _j2587 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2606 = 0;
        for (var _item2591 in value.traits) {
            var scratch = base.scratch();
            _m_TypeName_write(scratch, _item2591);
            base.add($"t.{slot}.traits", scratch, _j2606);
            _j2606 += 1;
        }
    }
    if (base.verifying) {
        ulong _j2622 = 0;
        for (var _item2607 in value.attributes) {
            var scratch = base.scratch();
            _a_Attribute_write(scratch, _item2607);
            base.add($"t.{slot}.attributes", scratch, _j2622);
            _j2622 += 1;
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
        for (var _item2629 in value.imports) {
            _a_Import_write(out, _item2629);
        }
        found.append(("imports", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.structs.count);
        for (var _item2630 in value.structs) {
            _m_StructDef_write(out, _item2630);
        }
        found.append(("structs", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.blank_bodies = false;
        out.unsigned(value.traits.count);
        for (var _item2631 in value.traits) {
            _m_TraitDef_write(out, _item2631);
        }
        found.append(("traits", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.extensions.count);
        for (var _item2632 in value.extensions) {
            _m_ExtensionDef_write(out, _item2632);
        }
        found.append(("extensions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.functions.count);
        for (var _item2633 in value.functions) {
            _m_FunctionDef_write(out, _item2633);
        }
        found.append(("functions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.externs.count);
        for (var _item2634 in value.externs) {
            _m_ExternDef_write(out, _item2634);
        }
        found.append(("externs", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.globals.count);
        for (var _item2635 in value.globals) {
            _m_VariableDef_write(out, _item2635);
        }
        found.append(("globals", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.static_blocks.count);
        for (var _item2636 in value.static_blocks) {
            _m_ModuleStaticBlock_write(out, _item2636);
        }
        found.append(("static_blocks", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.enums.count);
        for (var _item2637 in value.enums) {
            _m_EnumDef_write(out, _item2637);
        }
        found.append(("enums", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.struct_specs.count);
        for (var _item2638 in value.struct_specs) {
            _m_TypeName_write(out, _item2638);
        }
        found.append(("struct_specs", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.func_specs.count);
        for (var _item2639 in value.func_specs) {
            _m_TypeName_write(out, _item2639);
        }
        found.append(("func_specs", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.type_aliases.count);
        for (var _item2640 in value.type_aliases) {
            _m_TypeAliasDef_write(out, _item2640);
        }
        found.append(("type_aliases", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.withheld.count);
        for (var _item2641 in value.withheld) {
            _m_Withheld_write(out, _item2641);
        }
        found.append(("withheld", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.properties.count);
        for (var _item2642 in value.properties) {
            _m_PropertyDef_write(out, _item2642);
        }
        found.append(("properties", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.type_uses.count);
        for (var _item2643 in value.type_uses) {
            _m_TypeUse_write(out, _item2643);
        }
        found.append(("type_uses", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.use_contexts.count);
        for (var _item2644 in value.use_contexts) {
            _m_UseContext_write(out, _item2644);
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
            for (var _item2645 in value.literal_args) {
                var (_t2646, _t2647, _t2648) = _item2645;
                out.loc(_t2646);
                out.unsigned(_t2647);
                out.loc(_t2648);
            }
        }
        found.append(("literal_args", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.constrained_aliases.count);
        for (var _item2649 in value.constrained_aliases) {
            _m_TypeAliasDef_write(out, _item2649);
        }
        found.append(("constrained_aliases", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.trait_types.count);
        for (var _item2650 in value.trait_types) {
            _m_TraitType_write(out, _item2650);
        }
        found.append(("trait_types", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.conversions.count);
        for (var _item2651 in value.conversions) {
            _m_Conversion_write(out, _item2651);
        }
        found.append(("conversions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2653 = Array<(u8[], u8[], String)>();
        for (var (_key2652, _) in value.overload_sets) {
            var _scratch2654 = out.scratch();
            _scratch2654.text(_key2652);
            var _vscratch2656 = out.scratch();
            _vscratch2656.unsigned(value.overload_sets[_key2652].count);
            for (var _item2657 in value.overload_sets[_key2652]) {
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
        out.unsigned(_keys2653.count);
        for (var (_bytes2655, _, _key2652) in _keys2653) {
            out.text(_key2652);
            out.unsigned(value.overload_sets[_key2652].count);
            for (var _item2658 in value.overload_sets[_key2652]) {
                out.text(_item2658);
            }
        }
        found.append(("overload_sets", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2660 = Array<(u8[], u8[], String)>();
        for (var (_key2659, _) in value.overload_unions) {
            var _scratch2661 = out.scratch();
            _scratch2661.text(_key2659);
            var _vscratch2663 = out.scratch();
            _vscratch2663.unsigned(value.overload_unions[_key2659].count);
            for (var _item2664 in value.overload_unions[_key2659]) {
                _vscratch2663.unsigned(_item2664.count);
                for (var _item2665 in _item2664) {
                    _vscratch2663.text(_item2665);
                }
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
            out.unsigned(value.overload_unions[_key2659].count);
            for (var _item2666 in value.overload_unions[_key2659]) {
                out.unsigned(_item2666.count);
                for (var _item2667 in _item2666) {
                    out.text(_item2667);
                }
            }
        }
        found.append(("overload_unions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2669 = Array<(u8[], u8[], String)>();
        for (var (_key2668, _) in value.method_overload_sets) {
            var _scratch2670 = out.scratch();
            _scratch2670.text(_key2668);
            var _vscratch2672 = out.scratch();
            var _keys2674 = Array<(u8[], u8[], String)>();
            for (var (_key2673, _) in value.method_overload_sets[_key2668]) {
                var _scratch2675 = _vscratch2672.scratch();
                _scratch2675.text(_key2673);
                var _vscratch2677 = _vscratch2672.scratch();
                _vscratch2677.unsigned(value.method_overload_sets[_key2668][_key2673].count);
                for (var _item2678 in value.method_overload_sets[_key2668][_key2673]) {
                    _vscratch2677.text(_item2678);
                }
                _keys2674.append((_scratch2675.finish(), _vscratch2677.finish(), _key2673));
            }
            _keys2674.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            _vscratch2672.unsigned(_keys2674.count);
            for (var (_bytes2676, _, _key2673) in _keys2674) {
                _vscratch2672.text(_key2673);
                _vscratch2672.unsigned(value.method_overload_sets[_key2668][_key2673].count);
                for (var _item2679 in value.method_overload_sets[_key2668][_key2673]) {
                    _vscratch2672.text(_item2679);
                }
            }
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
            out.text(_key2668);
            var _keys2681 = Array<(u8[], u8[], String)>();
            for (var (_key2680, _) in value.method_overload_sets[_key2668]) {
                var _scratch2682 = out.scratch();
                _scratch2682.text(_key2680);
                var _vscratch2684 = out.scratch();
                _vscratch2684.unsigned(value.method_overload_sets[_key2668][_key2680].count);
                for (var _item2685 in value.method_overload_sets[_key2668][_key2680]) {
                    _vscratch2684.text(_item2685);
                }
                _keys2681.append((_scratch2682.finish(), _vscratch2684.finish(), _key2680));
            }
            _keys2681.sort((a, b) => {
                var (x, xv, _) = a;
                var (y, yv, _) = b;
                var by_key = compare_bytes(x, y);
                return by_key != 0 ? by_key : compare_bytes(xv, yv);
            });
            out.unsigned(_keys2681.count);
            for (var (_bytes2683, _, _key2680) in _keys2681) {
                out.text(_key2680);
                out.unsigned(value.method_overload_sets[_key2668][_key2680].count);
                for (var _item2686 in value.method_overload_sets[_key2668][_key2680]) {
                    out.text(_item2686);
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
        var _keys2688 = Array<(u8[], u8[], Loc)>();
        for (var _key2687 in value.private_functions) {
            var _scratch2689 = out.scratch();
            _scratch2689.loc(_key2687);
            var _vscratch2691 = out.scratch();
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
        }
        found.append(("private_functions", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2693 = Array<(u8[], u8[], Loc)>();
        for (var _key2692 in value.file_private_functions) {
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
            for (var _item2697 in value.call_targets) {
                var (_t2698, _t2699) = _item2697;
                out.loc(_t2698);
                out.text(_t2699);
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
            for (var _item2700 in value.argument_names) {
                var (_t2701, _t2702) = _item2700;
                out.loc(_t2701);
                out.text(_t2702);
            }
        }
        found.append(("argument_names", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        out.unsigned(value.namespaces.count);
        for (var _item2703 in value.namespaces) {
            out.text(_item2703);
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
            for (var _item2704 in value.cached_files) {
                out.flag(_item2704);
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
            var _keys2706 = Array<(u8[], u8[], Loc)>();
            for (var (_key2705, _) in value.recorded_summaries) {
                var _scratch2707 = out.scratch();
                _scratch2707.loc(_key2705);
                var _vscratch2709 = out.scratch();
                _vscratch2709.text(value.recorded_summaries[_key2705]);
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
                out.loc(_key2705);
                out.text(value.recorded_summaries[_key2705]);
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
            var _keys2711 = Array<(u8[], u8[], Loc)>();
            for (var _key2710 in value.stripped) {
                var _scratch2712 = out.scratch();
                _scratch2712.loc(_key2710);
                var _vscratch2714 = out.scratch();
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
        var _keys2716 = Array<(u8[], u8[], String)>();
        for (var (_key2715, _) in value.spec_requests) {
            var _scratch2717 = out.scratch();
            _scratch2717.text(_key2715);
            var _vscratch2719 = out.scratch();
            _m_SpecRequest_write(_vscratch2719, value.spec_requests[_key2715]);
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
            out.text(_key2715);
            _m_SpecRequest_write(out, value.spec_requests[_key2715]);
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
            for (var _item2720 in value.summaries_to_record) {
                var (_t2721, _t2722) = _item2720;
                out.loc(_t2721);
                out.text(_t2722);
            }
        }
        found.append(("summaries_to_record", interface_text(out)));
    }
    {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        var _keys2724 = Array<(u8[], u8[], String)>();
        for (var (_key2723, _) in value.caller_copies) {
            var _scratch2725 = out.scratch();
            _scratch2725.text(_key2723);
            var _vscratch2727 = out.scratch();
            _vscratch2727.unsigned(value.caller_copies[_key2723].count);
            for (var _item2728 in value.caller_copies[_key2723]) {
                _vscratch2727.flag(_item2728);
            }
            _keys2724.append((_scratch2725.finish(), _vscratch2727.finish(), _key2723));
        }
        _keys2724.sort((a, b) => {
            var (x, xv, _) = a;
            var (y, yv, _) = b;
            var by_key = compare_bytes(x, y);
            return by_key != 0 ? by_key : compare_bytes(xv, yv);
        });
        out.unsigned(_keys2724.count);
        for (var (_bytes2726, _, _key2723) in _keys2724) {
            out.text(_key2723);
            out.unsigned(value.caller_copies[_key2723].count);
            for (var _item2729 in value.caller_copies[_key2723]) {
                out.flag(_item2729);
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
    for (var _item2730 in value.structs) {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        _m_StructDef_write(out, _item2730);
        found.append(("structs " + _item2730.name, interface_text(out)));
    }
    for (var _item2731 in value.functions) {
        var out = RecordOut();
        out.blank_bodies = interface;
        out.blank_locs = interface;
        _m_FunctionDef_write(out, _item2731);
        found.append(("functions " + _item2731.name, interface_text(out)));
    }
    return found;
}
