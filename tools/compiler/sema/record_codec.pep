## Saving and loading a checked module: a binary writer and reader for
## every type `Module` reaches, the AST nodes it holds included. Generated
## by `scripts/gen-sema-record.py`; do not edit.

import compiler.ast;
import [Loc] from "loc";
import [RecordIn, RecordOut] from "record";

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
    out.unsigned(value.literal_args.count);
    for (var _item17 in value.literal_args) {
        var (_t18, _t19, _t20) = _item17;
        out.loc(_t18);
        out.unsigned(_t19);
        out.loc(_t20);
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
    out.unsigned(value.overload_sets.count);
    for (var (_key24, _item25) in value.overload_sets) {
        out.text(_key24);
        out.unsigned(_item25.count);
        for (var _item26 in _item25) {
            out.text(_item26);
        }
    }
    out.unsigned(value.overload_unions.count);
    for (var (_key27, _item28) in value.overload_unions) {
        out.text(_key27);
        out.unsigned(_item28.count);
        for (var _item29 in _item28) {
            out.unsigned(_item29.count);
            for (var _item30 in _item29) {
                out.text(_item30);
            }
        }
    }
    out.unsigned(value.method_overload_sets.count);
    for (var (_key31, _item32) in value.method_overload_sets) {
        out.text(_key31);
        out.unsigned(_item32.count);
        for (var (_key33, _item34) in _item32) {
            out.text(_key33);
            out.unsigned(_item34.count);
            for (var _item35 in _item34) {
                out.text(_item35);
            }
        }
    }
    _m_ExtensionScopes_write(out, value.extension_scopes);
    out.unsigned(value.private_functions.count);
    for (var _item36 in value.private_functions) {
        out.loc(_item36);
    }
    out.unsigned(value.file_private_functions.count);
    for (var _item37 in value.file_private_functions) {
        out.loc(_item37);
    }
    out.unsigned(value.call_targets.count);
    for (var _item38 in value.call_targets) {
        var (_t39, _t40) = _item38;
        out.loc(_t39);
        out.text(_t40);
    }
    out.unsigned(value.argument_names.count);
    for (var _item41 in value.argument_names) {
        var (_t42, _t43) = _item41;
        out.loc(_t42);
        out.text(_t43);
    }
    out.unsigned(value.namespaces.count);
    for (var _item44 in value.namespaces) {
        out.text(_item44);
    }
    out.unsigned(value.cached_files.count);
    for (var _item45 in value.cached_files) {
        out.flag(_item45);
    }
    out.unsigned(value.recorded_summaries.count);
    for (var (_key46, _item47) in value.recorded_summaries) {
        out.loc(_key46);
        out.text(_item47);
    }
    out.unsigned(value.stripped.count);
    for (var _item48 in value.stripped) {
        out.loc(_item48);
    }
    _m_Templates_write(out, value.templates);
    _m_Checked_write(out, value.checked);
    out.unsigned(value.spec_requests.count);
    for (var (_key49, _item50) in value.spec_requests) {
        out.text(_key49);
        _m_SpecRequest_write(out, _item50);
    }
    out.flag(value.record_summaries);
    out.unsigned(value.summaries_to_record.count);
    for (var _item51 in value.summaries_to_record) {
        var (_t52, _t53) = _item51;
        out.loc(_t52);
        out.text(_t53);
    }
    out.unsigned(value.caller_copies.count);
    for (var (_key54, _item55) in value.caller_copies) {
        out.text(_key54);
        out.unsigned(_item55.count);
        for (var _item56 in _item55) {
            out.flag(_item56);
        }
    }
    out.flag(value.linked);
}

_m_Module_read(input: RecordIn): Module {
    var _v57 = Array<ast.Import>();
    var _n58 = input.count();
    for (var _ in 0.._n58) {
        _v57.append(_a_Import_read(input));
    }
    var _f59 = _v57;
    var _v60 = Array<StructDef>();
    var _n61 = input.count();
    for (var _ in 0.._n61) {
        _v60.append(_m_StructDef_read(input));
    }
    var _f62 = _v60;
    var _v63 = Array<TraitDef>();
    var _n64 = input.count();
    for (var _ in 0.._n64) {
        _v63.append(_m_TraitDef_read(input));
    }
    var _f65 = _v63;
    var _v66 = Array<ExtensionDef>();
    var _n67 = input.count();
    for (var _ in 0.._n67) {
        _v66.append(_m_ExtensionDef_read(input));
    }
    var _f68 = _v66;
    var _v69 = Array<FunctionDef>();
    var _n70 = input.count();
    for (var _ in 0.._n70) {
        _v69.append(_m_FunctionDef_read(input));
    }
    var _f71 = _v69;
    var _v72 = Array<ExternDef>();
    var _n73 = input.count();
    for (var _ in 0.._n73) {
        _v72.append(_m_ExternDef_read(input));
    }
    var _f74 = _v72;
    var _v75 = Array<VariableDef>();
    var _n76 = input.count();
    for (var _ in 0.._n76) {
        _v75.append(_m_VariableDef_read(input));
    }
    var _f77 = _v75;
    var _v78 = Array<ModuleStaticBlock>();
    var _n79 = input.count();
    for (var _ in 0.._n79) {
        _v78.append(_m_ModuleStaticBlock_read(input));
    }
    var _f80 = _v78;
    var _v81 = Array<EnumDef>();
    var _n82 = input.count();
    for (var _ in 0.._n82) {
        _v81.append(_m_EnumDef_read(input));
    }
    var _f83 = _v81;
    var _v84 = Array<TypeName>();
    var _n85 = input.count();
    for (var _ in 0.._n85) {
        _v84.append(_m_TypeName_read(input));
    }
    var _f86 = _v84;
    var _v87 = Array<TypeName>();
    var _n88 = input.count();
    for (var _ in 0.._n88) {
        _v87.append(_m_TypeName_read(input));
    }
    var _f89 = _v87;
    var _v90 = Array<TypeAliasDef>();
    var _n91 = input.count();
    for (var _ in 0.._n91) {
        _v90.append(_m_TypeAliasDef_read(input));
    }
    var _f92 = _v90;
    var _v93 = Array<Withheld>();
    var _n94 = input.count();
    for (var _ in 0.._n94) {
        _v93.append(_m_Withheld_read(input));
    }
    var _f95 = _v93;
    var _v96 = Array<PropertyDef>();
    var _n97 = input.count();
    for (var _ in 0.._n97) {
        _v96.append(_m_PropertyDef_read(input));
    }
    var _f98 = _v96;
    var _v99 = Array<TypeUse>();
    var _n100 = input.count();
    for (var _ in 0.._n100) {
        _v99.append(_m_TypeUse_read(input));
    }
    var _f101 = _v99;
    var _v102 = Array<UseContext>();
    var _n103 = input.count();
    for (var _ in 0.._n103) {
        _v102.append(_m_UseContext_read(input));
    }
    var _f104 = _v102;
    var _v105 = Array<(Loc, ulong, Loc)>();
    var _n106 = input.count();
    for (var _ in 0.._n106) {
        var _t107 = input.loc();
        var _t108 = input.unsigned();
        var _t109 = input.loc();
        _v105.append((_t107, _t108, _t109));
    }
    var _f110 = _v105;
    var _v111 = Array<TypeAliasDef>();
    var _n112 = input.count();
    for (var _ in 0.._n112) {
        _v111.append(_m_TypeAliasDef_read(input));
    }
    var _f113 = _v111;
    var _v114 = Array<TraitType>();
    var _n115 = input.count();
    for (var _ in 0.._n115) {
        _v114.append(_m_TraitType_read(input));
    }
    var _f116 = _v114;
    var _v117 = Array<Conversion>();
    var _n118 = input.count();
    for (var _ in 0.._n118) {
        _v117.append(_m_Conversion_read(input));
    }
    var _f119 = _v117;
    var _v120 = Map<String, Array<String>>();
    var _n121 = input.count();
    for (var _ in 0.._n121) {
        var _k122 = input.text();
        var _v123 = Array<String>();
        var _n124 = input.count();
        for (var _ in 0.._n124) {
            _v123.append(input.text());
        }
        _v120[_k122] = _v123;
    }
    var _f125 = _v120;
    var _v126 = Map<String, Array<Array<String>>>();
    var _n127 = input.count();
    for (var _ in 0.._n127) {
        var _k128 = input.text();
        var _v129 = Array<Array<String>>();
        var _n130 = input.count();
        for (var _ in 0.._n130) {
            var _v131 = Array<String>();
            var _n132 = input.count();
            for (var _ in 0.._n132) {
                _v131.append(input.text());
            }
            _v129.append(_v131);
        }
        _v126[_k128] = _v129;
    }
    var _f133 = _v126;
    var _v134 = Map<String, Map<String, Array<String>>>();
    var _n135 = input.count();
    for (var _ in 0.._n135) {
        var _k136 = input.text();
        var _v137 = Map<String, Array<String>>();
        var _n138 = input.count();
        for (var _ in 0.._n138) {
            var _k139 = input.text();
            var _v140 = Array<String>();
            var _n141 = input.count();
            for (var _ in 0.._n141) {
                _v140.append(input.text());
            }
            _v137[_k139] = _v140;
        }
        _v134[_k136] = _v137;
    }
    var _f142 = _v134;
    var _f143 = _m_ExtensionScopes_read(input);
    var _v144 = HashSet<Loc>();
    var _n145 = input.count();
    for (var _ in 0.._n145) {
        _v144.insert(input.loc());
    }
    var _f146 = _v144;
    var _v147 = HashSet<Loc>();
    var _n148 = input.count();
    for (var _ in 0.._n148) {
        _v147.insert(input.loc());
    }
    var _f149 = _v147;
    var _v150 = Array<(Loc, String)>();
    var _n151 = input.count();
    for (var _ in 0.._n151) {
        var _t152 = input.loc();
        var _t153 = input.text();
        _v150.append((_t152, _t153));
    }
    var _f154 = _v150;
    var _v155 = Array<(Loc, String)>();
    var _n156 = input.count();
    for (var _ in 0.._n156) {
        var _t157 = input.loc();
        var _t158 = input.text();
        _v155.append((_t157, _t158));
    }
    var _f159 = _v155;
    var _v160 = Array<String>();
    var _n161 = input.count();
    for (var _ in 0.._n161) {
        _v160.append(input.text());
    }
    var _f162 = _v160;
    var _v163 = Array<bool>();
    var _n164 = input.count();
    for (var _ in 0.._n164) {
        _v163.append(input.flag());
    }
    var _f165 = _v163;
    var _v166 = HashMap<Loc, String>();
    var _n167 = input.count();
    for (var _ in 0.._n167) {
        var _k168 = input.loc();
        _v166[_k168] = input.text();
    }
    var _f169 = _v166;
    var _v170 = HashSet<Loc>();
    var _n171 = input.count();
    for (var _ in 0.._n171) {
        _v170.insert(input.loc());
    }
    var _f172 = _v170;
    var _f173 = _m_Templates_read(input);
    var _f174 = _m_Checked_read(input);
    var _v175 = HashMap<String, SpecRequest>();
    var _n176 = input.count();
    for (var _ in 0.._n176) {
        var _k177 = input.text();
        _v175[_k177] = _m_SpecRequest_read(input);
    }
    var _f178 = _v175;
    var _f179 = input.flag();
    var _v180 = Array<(Loc, String)>();
    var _n181 = input.count();
    for (var _ in 0.._n181) {
        var _t182 = input.loc();
        var _t183 = input.text();
        _v180.append((_t182, _t183));
    }
    var _f184 = _v180;
    var _v185 = HashMap<String, Array<bool>>();
    var _n186 = input.count();
    for (var _ in 0.._n186) {
        var _k187 = input.text();
        var _v188 = Array<bool>();
        var _n189 = input.count();
        for (var _ in 0.._n189) {
            _v188.append(input.flag());
        }
        _v185[_k187] = _v188;
    }
    var _f190 = _v185;
    var _f191 = input.flag();
    return Module(
        _f59,
        _f62,
        _f65,
        _f68,
        _f71,
        _f74,
        _f77,
        _f80,
        _f83,
        _f86,
        _f89,
        _f92,
        _f95,
        _f98,
        _f101,
        _f104,
        _f110,
        _f113,
        _f116,
        _f119,
        _f125,
        _f133,
        _f142,
        _f143,
        _f146,
        _f149,
        _f154,
        _f159,
        _f162,
        _f165,
        _f169,
        _f172,
        _f173,
        _f174,
        _f178,
        _f179,
        _f184,
        _f190,
        _f191
    );
}

_m_SpecRequest_write(out: RecordOut, value: SpecRequest) {
    out.text(value.by);
    out.loc(value.loc);
}

_m_SpecRequest_read(input: RecordIn): SpecRequest {
    var _f192 = input.text();
    var _f193 = input.loc();
    return SpecRequest(_f192, _f193);
}

_m_Checked_write(out: RecordOut, value: Checked) {
    out.unsigned(value.structs.count);
    for (var _item194 in value.structs) {
        out.text(_item194);
    }
    out.unsigned(value.functions.count);
    for (var _item195 in value.functions) {
        out.text(_item195);
    }
    out.unsigned(value.globals.count);
    for (var _item196 in value.globals) {
        out.text(_item196);
    }
    out.unsigned(value.extensions);
    out.unsigned(value.summaries.count);
    for (var (_key197, _item198) in value.summaries) {
        out.text(_key197);
        var (_t199, _t200) = _item198;
        out.loc(_t199);
        out.text(_t200);
    }
}

_m_Checked_read(input: RecordIn): Checked {
    var _v201 = HashSet<String>();
    var _n202 = input.count();
    for (var _ in 0.._n202) {
        _v201.insert(input.text());
    }
    var _f203 = _v201;
    var _v204 = HashSet<String>();
    var _n205 = input.count();
    for (var _ in 0.._n205) {
        _v204.insert(input.text());
    }
    var _f206 = _v204;
    var _v207 = HashSet<String>();
    var _n208 = input.count();
    for (var _ in 0.._n208) {
        _v207.insert(input.text());
    }
    var _f209 = _v207;
    var _f210 = input.unsigned();
    var _v211 = HashMap<String, (Loc, String)>();
    var _n212 = input.count();
    for (var _ in 0.._n212) {
        var _k213 = input.text();
        var _t214 = input.loc();
        var _t215 = input.text();
        _v211[_k213] = (_t214, _t215);
    }
    var _f216 = _v211;
    return Checked(_f203, _f206, _f209, _f210, _f216);
}

_m_Templates_write(out: RecordOut, value: Templates) {
    out.flag(value.frozen);
    out.unsigned(value.structs.count);
    for (var _item217 in value.structs) {
        _m_StructDef_write(out, _item217);
    }
    out.unsigned(value.functions.count);
    for (var _item218 in value.functions) {
        _m_FunctionDef_write(out, _item218);
    }
}

_m_Templates_read(input: RecordIn): Templates {
    var _f219 = input.flag();
    var _v220 = Array<StructDef>();
    var _n221 = input.count();
    for (var _ in 0.._n221) {
        _v220.append(_m_StructDef_read(input));
    }
    var _f222 = _v220;
    var _v223 = Array<FunctionDef>();
    var _n224 = input.count();
    for (var _ in 0.._n224) {
        _v223.append(_m_FunctionDef_read(input));
    }
    var _f225 = _v223;
    return Templates(_f219, _f222, _f225);
}

_m_FunctionDef_write(out: RecordOut, value: FunctionDef) {
    out.text(value.name);
    _m_TypeName_write(out, value.ty);
    out.unsigned(value.generic_params.count);
    for (var _item226 in value.generic_params) {
        _m_GenericParam_write(out, _item226);
    }
    out.unsigned(value.parameters.count);
    for (var _item227 in value.parameters) {
        _m_VariableDef_write(out, _item227);
    }
    if (value.body.is_value()) {
        out.unsigned(1);
        _m_Block_write(out, value.body.value());
    } else {
        out.unsigned(0);
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
    for (var _item228 in value.attributes) {
        _a_Attribute_write(out, _item228);
    }
    out.loc(value.loc);
    if (value.trait_default.is_value()) {
        out.unsigned(1);
        out.unsigned(value.trait_default.value().count);
        for (var _item229 in value.trait_default.value()) {
            out.text(_item229);
        }
    } else {
        out.unsigned(0);
    }
    out.loc(value.owner);
}

_m_FunctionDef_read(input: RecordIn): FunctionDef {
    var _f230 = input.text();
    var _f231 = _m_TypeName_read(input);
    var _v232 = Array<GenericParam>();
    var _n233 = input.count();
    for (var _ in 0.._n233) {
        _v232.append(_m_GenericParam_read(input));
    }
    var _f234 = _v232;
    var _v235 = Array<VariableDef>();
    var _n236 = input.count();
    for (var _ in 0.._n236) {
        _v235.append(_m_VariableDef_read(input));
    }
    var _f237 = _v235;
    var _o238 = Optional<Block>.Empty;
    if (input.unsigned() == 1) {
        _o238 = Optional<Block>.Value(_m_Block_read(input));
    }
    var _f239 = _o238;
    var _o240 = Optional<String>.Empty;
    if (input.unsigned() == 1) {
        _o240 = Optional<String>.Value(input.text());
    }
    var _f241 = _o240;
    var _f242 = input.flag();
    var _f243 = input.flag();
    var _f244 = input.flag();
    var _v245 = Array<ast.Attribute>();
    var _n246 = input.count();
    for (var _ in 0.._n246) {
        _v245.append(_a_Attribute_read(input));
    }
    var _f247 = _v245;
    var _f248 = input.loc();
    var _o249 = Optional<Array<String>>.Empty;
    if (input.unsigned() == 1) {
        var _v250 = Array<String>();
        var _n251 = input.count();
        for (var _ in 0.._n251) {
            _v250.append(input.text());
        }
        _o249 = Optional<Array<String>>.Value(_v250);
    }
    var _f252 = _o249;
    var _f253 = input.loc();
    return FunctionDef(_f230, _f231, _f234, _f237, _f239, _f241, _f242, _f243, _f244, _f247, _f248, _f252, _f253);
}

_a_Attribute_write(out: RecordOut, value: ast.Attribute) {
    _a_Expression_write(out, value.body);
    out.unsigned(value.span.start);
    out.unsigned(value.span.end);
}

_a_Attribute_read(input: RecordIn): ast.Attribute {
    var _f254 = _a_Expression_read(input);
    var _s255 = input.unsigned();
    var _f256 = ast.Span(_s255, input.unsigned());
    var value = ast.Attribute(_f254, _f256);
    value.body = _f254;
    value.span = _f256;
    return value;
}

_a_Expression_write(out: RecordOut, value: ast.Expression) {
    match (value) {
        Literal(p0, p1) => {
            out.unsigned(0);
            _a_Literal_write(out, p0);
            out.unsigned(p1.start);
            out.unsigned(p1.end);
        }
        SymbolRef(p0, p1) => {
            out.unsigned(1);
            out.text(p0);
            out.unsigned(p1.start);
            out.unsigned(p1.end);
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
            out.unsigned(p3.start);
            out.unsigned(p3.end);
        }
        Cast(p0, p1, p2, p3, p4) => {
            out.unsigned(5);
            _a_Expression_write(out, p0);
            _a_TypeName_write(out, p1);
            out.unsigned(p2.start);
            out.unsigned(p2.end);
            out.unsigned(p3.start);
            out.unsigned(p3.end);
            out.flag(p4);
        }
        Binary(p0, p1, p2, p3) => {
            out.unsigned(6);
            _a_Expression_write(out, p0);
            out.text(p1);
            _a_Expression_write(out, p2);
            out.unsigned(p3.start);
            out.unsigned(p3.end);
        }
        Ternary(p0, p1, p2, p3) => {
            out.unsigned(7);
            _a_Expression_write(out, p0);
            _a_Expression_write(out, p1);
            _a_Expression_write(out, p2);
            out.unsigned(p3.start);
            out.unsigned(p3.end);
        }
        Index(p0, p1, p2) => {
            out.unsigned(8);
            _a_Expression_write(out, p0);
            _a_Expression_write(out, p1);
            out.unsigned(p2.start);
            out.unsigned(p2.end);
        }
        MemberAccess(p0, p1, p2, p3) => {
            out.unsigned(9);
            _a_Expression_write(out, p0);
            out.text(p1);
            out.unsigned(p2.start);
            out.unsigned(p2.end);
            out.unsigned(p3.start);
            out.unsigned(p3.end);
        }
        FunctionCall(p0, p1, p2) => {
            out.unsigned(10);
            _a_Expression_write(out, p0);
            out.unsigned(p1.count);
            for (var _item298 in p1) {
                _a_Expression_write(out, _item298);
            }
            out.unsigned(p2.start);
            out.unsigned(p2.end);
        }
        NamedArgument(p0, p1, p2, p3) => {
            out.unsigned(11);
            out.text(p0);
            out.unsigned(p1.start);
            out.unsigned(p1.end);
            _a_Expression_write(out, p2);
            out.unsigned(p3.start);
            out.unsigned(p3.end);
        }
        Closure(p0) => {
            out.unsigned(12);
            _a_ClosureLiteral_write(out, p0);
        }
        Tuple(p0, p1, p2) => {
            out.unsigned(13);
            out.unsigned(p0.count);
            for (var _item311 in p0) {
                _a_Expression_write(out, _item311);
            }
            out.unsigned(p1.count);
            for (var _item315 in p1) {
                _a_Label_write(out, _item315);
            }
            out.unsigned(p2.start);
            out.unsigned(p2.end);
        }
        ArrayLiteral(p0, p1) => {
            out.unsigned(14);
            out.unsigned(p0.count);
            for (var _item321 in p0) {
                _a_Expression_write(out, _item321);
            }
            out.unsigned(p1.start);
            out.unsigned(p1.end);
        }
        MapLiteral(p0, p1) => {
            out.unsigned(15);
            out.unsigned(p0.count);
            for (var _item327 in p0) {
                _a_MapEntry_write(out, _item327);
            }
            out.unsigned(p1.start);
            out.unsigned(p1.end);
        }
        Match(p0) => {
            out.unsigned(16);
            _a_MatchExpression_write(out, p0);
        }
        Is(p0, p1, p2, p3) => {
            out.unsigned(17);
            _a_Expression_write(out, p0);
            _a_Pattern_write(out, p1);
            out.unsigned(p2.start);
            out.unsigned(p2.end);
            out.unsigned(p3.start);
            out.unsigned(p3.end);
        }
        Interpolated(p0, p1) => {
            out.unsigned(18);
            out.unsigned(p0.count);
            for (var _item340 in p0) {
                _a_StringPart_write(out, _item340);
            }
            out.unsigned(p1.start);
            out.unsigned(p1.end);
        }
        FormatString(p0, p1, p2, p3) => {
            out.unsigned(19);
            out.unsigned(p0.count);
            for (var _item346 in p0) {
                _a_StringPart_write(out, _item346);
            }
            out.unsigned(p1.start);
            out.unsigned(p1.end);
            out.unsigned(p2);
            out.unsigned(p3.count);
            for (var _item353 in p3) {
                out.unsigned(_item353.start);
                out.unsigned(_item353.end);
            }
        }
        Parenthesized(p0, p1) => {
            out.unsigned(20);
            _a_Expression_write(out, p0);
            out.unsigned(p1.start);
            out.unsigned(p1.end);
        }
    }
}

_a_Expression_read(input: RecordIn): ast.Expression {
    var tag = input.unsigned();
    if (tag == 0) {
        var _f257 = _a_Literal_read(input);
        var _s258 = input.unsigned();
        var _f259 = ast.Span(_s258, input.unsigned());
        return ast.Expression.Literal(_f257, _f259);
    }
    if (tag == 1) {
        var _f260 = input.text();
        var _s261 = input.unsigned();
        var _f262 = ast.Span(_s261, input.unsigned());
        return ast.Expression.SymbolRef(_f260, _f262);
    }
    if (tag == 2) {
        var _f263 = _a_TypeName_read(input);
        return ast.Expression.TypeLiteral(_f263);
    }
    if (tag == 3) {
        var _f264 = _a_TypeName_read(input);
        return ast.Expression.SizeOf(_f264);
    }
    if (tag == 4) {
        var _f265 = input.text();
        var _f266 = input.flag();
        var _f267 = _a_Expression_read(input);
        var _s268 = input.unsigned();
        var _f269 = ast.Span(_s268, input.unsigned());
        return ast.Expression.Unary(_f265, _f266, _f267, _f269);
    }
    if (tag == 5) {
        var _f270 = _a_Expression_read(input);
        var _f271 = _a_TypeName_read(input);
        var _s272 = input.unsigned();
        var _f273 = ast.Span(_s272, input.unsigned());
        var _s274 = input.unsigned();
        var _f275 = ast.Span(_s274, input.unsigned());
        var _f276 = input.flag();
        return ast.Expression.Cast(_f270, _f271, _f273, _f275, _f276);
    }
    if (tag == 6) {
        var _f277 = _a_Expression_read(input);
        var _f278 = input.text();
        var _f279 = _a_Expression_read(input);
        var _s280 = input.unsigned();
        var _f281 = ast.Span(_s280, input.unsigned());
        return ast.Expression.Binary(_f277, _f278, _f279, _f281);
    }
    if (tag == 7) {
        var _f282 = _a_Expression_read(input);
        var _f283 = _a_Expression_read(input);
        var _f284 = _a_Expression_read(input);
        var _s285 = input.unsigned();
        var _f286 = ast.Span(_s285, input.unsigned());
        return ast.Expression.Ternary(_f282, _f283, _f284, _f286);
    }
    if (tag == 8) {
        var _f287 = _a_Expression_read(input);
        var _f288 = _a_Expression_read(input);
        var _s289 = input.unsigned();
        var _f290 = ast.Span(_s289, input.unsigned());
        return ast.Expression.Index(_f287, _f288, _f290);
    }
    if (tag == 9) {
        var _f291 = _a_Expression_read(input);
        var _f292 = input.text();
        var _s293 = input.unsigned();
        var _f294 = ast.Span(_s293, input.unsigned());
        var _s295 = input.unsigned();
        var _f296 = ast.Span(_s295, input.unsigned());
        return ast.Expression.MemberAccess(_f291, _f292, _f294, _f296);
    }
    if (tag == 10) {
        var _f297 = _a_Expression_read(input);
        var _v299 = Array<ast.Expression>();
        var _n300 = input.count();
        for (var _ in 0.._n300) {
            _v299.append(_a_Expression_read(input));
        }
        var _f301 = _v299;
        var _s302 = input.unsigned();
        var _f303 = ast.Span(_s302, input.unsigned());
        return ast.Expression.FunctionCall(_f297, _f301, _f303);
    }
    if (tag == 11) {
        var _f304 = input.text();
        var _s305 = input.unsigned();
        var _f306 = ast.Span(_s305, input.unsigned());
        var _f307 = _a_Expression_read(input);
        var _s308 = input.unsigned();
        var _f309 = ast.Span(_s308, input.unsigned());
        return ast.Expression.NamedArgument(_f304, _f306, _f307, _f309);
    }
    if (tag == 12) {
        var _f310 = _a_ClosureLiteral_read(input);
        return ast.Expression.Closure(_f310);
    }
    if (tag == 13) {
        var _v312 = Array<ast.Expression>();
        var _n313 = input.count();
        for (var _ in 0.._n313) {
            _v312.append(_a_Expression_read(input));
        }
        var _f314 = _v312;
        var _v316 = Array<ast.Label>();
        var _n317 = input.count();
        for (var _ in 0.._n317) {
            _v316.append(_a_Label_read(input));
        }
        var _f318 = _v316;
        var _s319 = input.unsigned();
        var _f320 = ast.Span(_s319, input.unsigned());
        return ast.Expression.Tuple(_f314, _f318, _f320);
    }
    if (tag == 14) {
        var _v322 = Array<ast.Expression>();
        var _n323 = input.count();
        for (var _ in 0.._n323) {
            _v322.append(_a_Expression_read(input));
        }
        var _f324 = _v322;
        var _s325 = input.unsigned();
        var _f326 = ast.Span(_s325, input.unsigned());
        return ast.Expression.ArrayLiteral(_f324, _f326);
    }
    if (tag == 15) {
        var _v328 = Array<ast.MapEntry>();
        var _n329 = input.count();
        for (var _ in 0.._n329) {
            _v328.append(_a_MapEntry_read(input));
        }
        var _f330 = _v328;
        var _s331 = input.unsigned();
        var _f332 = ast.Span(_s331, input.unsigned());
        return ast.Expression.MapLiteral(_f330, _f332);
    }
    if (tag == 16) {
        var _f333 = _a_MatchExpression_read(input);
        return ast.Expression.Match(_f333);
    }
    if (tag == 17) {
        var _f334 = _a_Expression_read(input);
        var _f335 = _a_Pattern_read(input);
        var _s336 = input.unsigned();
        var _f337 = ast.Span(_s336, input.unsigned());
        var _s338 = input.unsigned();
        var _f339 = ast.Span(_s338, input.unsigned());
        return ast.Expression.Is(_f334, _f335, _f337, _f339);
    }
    if (tag == 18) {
        var _v341 = Array<ast.StringPart>();
        var _n342 = input.count();
        for (var _ in 0.._n342) {
            _v341.append(_a_StringPart_read(input));
        }
        var _f343 = _v341;
        var _s344 = input.unsigned();
        var _f345 = ast.Span(_s344, input.unsigned());
        return ast.Expression.Interpolated(_f343, _f345);
    }
    if (tag == 19) {
        var _v347 = Array<ast.StringPart>();
        var _n348 = input.count();
        for (var _ in 0.._n348) {
            _v347.append(_a_StringPart_read(input));
        }
        var _f349 = _v347;
        var _s350 = input.unsigned();
        var _f351 = ast.Span(_s350, input.unsigned());
        var _f352 = input.unsigned();
        var _v354 = Array<ast.Span>();
        var _n355 = input.count();
        for (var _ in 0.._n355) {
            var _s356 = input.unsigned();
            _v354.append(ast.Span(_s356, input.unsigned()));
        }
        var _f357 = _v354;
        return ast.Expression.FormatString(_f349, _f351, _f352, _f357);
    }
    if (tag == 20) {
        var _f358 = _a_Expression_read(input);
        var _s359 = input.unsigned();
        var _f360 = ast.Span(_s359, input.unsigned());
        return ast.Expression.Parenthesized(_f358, _f360);
    }
    input.fail("Expression", tag);
    return _a_Expression_read(input);
}

_a_StringPart_write(out: RecordOut, value: ast.StringPart) {
    match (value) {
        Text(p0, p1) => {
            out.unsigned(0);
            out.text(p0);
            out.unsigned(p1.start);
            out.unsigned(p1.end);
        }
        Hole(p0, p1, p2) => {
            out.unsigned(1);
            _a_Expression_write(out, p0);
            out.unsigned(p1.start);
            out.unsigned(p1.end);
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
            out.unsigned(p1.start);
            out.unsigned(p1.end);
            out.unsigned(p2.start);
            out.unsigned(p2.end);
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
        var _f361 = input.text();
        var _s362 = input.unsigned();
        var _f363 = ast.Span(_s362, input.unsigned());
        return ast.StringPart.Text(_f361, _f363);
    }
    if (tag == 1) {
        var _f364 = _a_Expression_read(input);
        var _s365 = input.unsigned();
        var _f366 = ast.Span(_s365, input.unsigned());
        var _o367 = Optional<ast.FormatSpec>.Empty;
        if (input.unsigned() == 1) {
            _o367 = Optional<ast.FormatSpec>.Value(_a_FormatSpec_read(input));
        }
        var _f368 = _o367;
        return ast.StringPart.Hole(_f364, _f366, _f368);
    }
    if (tag == 2) {
        var _f369 = input.unsigned();
        var _s370 = input.unsigned();
        var _f371 = ast.Span(_s370, input.unsigned());
        var _s372 = input.unsigned();
        var _f373 = ast.Span(_s372, input.unsigned());
        var _o374 = Optional<ast.FormatSpec>.Empty;
        if (input.unsigned() == 1) {
            _o374 = Optional<ast.FormatSpec>.Value(_a_FormatSpec_read(input));
        }
        var _f375 = _o374;
        return ast.StringPart.Argument(_f369, _f371, _f373, _f375);
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
        out.unsigned(value.plus.value().start);
        out.unsigned(value.plus.value().end);
    } else {
        out.unsigned(0);
    }
    if (value.zero.is_value()) {
        out.unsigned(1);
        out.unsigned(value.zero.value().start);
        out.unsigned(value.zero.value().end);
    } else {
        out.unsigned(0);
    }
    out.signed(value.width as long);
    out.signed(value.precision as long);
    if (value.point.is_value()) {
        out.unsigned(1);
        out.unsigned(value.point.value().start);
        out.unsigned(value.point.value().end);
    } else {
        out.unsigned(0);
    }
    out.text(value.kind);
    out.unsigned(value.kind_span.start);
    out.unsigned(value.kind_span.end);
}

_a_FormatSpec_read(input: RecordIn): ast.FormatSpec {
    var _f376 = input.text();
    var _f377 = input.signed();
    var _f378 = input.flag();
    var _o379 = Optional<ast.Span>.Empty;
    if (input.unsigned() == 1) {
        var _s380 = input.unsigned();
        _o379 = Optional<ast.Span>.Value(ast.Span(_s380, input.unsigned()));
    }
    var _f381 = _o379;
    var _o382 = Optional<ast.Span>.Empty;
    if (input.unsigned() == 1) {
        var _s383 = input.unsigned();
        _o382 = Optional<ast.Span>.Value(ast.Span(_s383, input.unsigned()));
    }
    var _f384 = _o382;
    var _f385 = input.signed();
    var _f386 = input.signed();
    var _o387 = Optional<ast.Span>.Empty;
    if (input.unsigned() == 1) {
        var _s388 = input.unsigned();
        _o387 = Optional<ast.Span>.Value(ast.Span(_s388, input.unsigned()));
    }
    var _f389 = _o387;
    var _f390 = input.text();
    var _s391 = input.unsigned();
    var _f392 = ast.Span(_s391, input.unsigned());
    var value = ast.FormatSpec();
    value.fill = _f376;
    value.align = _f377;
    value.has_align = _f378;
    value.plus = _f381;
    value.zero = _f384;
    value.width = _f385;
    value.precision = _f386;
    value.point = _f389;
    value.kind = _f390;
    value.kind_span = _f392;
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
        for (var _item393 in value.elements.value()) {
            _a_Pattern_write(out, _item393);
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
    out.unsigned(value.case_span.start);
    out.unsigned(value.case_span.end);
    if (value.bindings.is_value()) {
        out.unsigned(1);
        out.unsigned(value.bindings.value().count);
        for (var _item394 in value.bindings.value()) {
            _a_Pattern_write(out, _item394);
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
    out.unsigned(value.span.start);
    out.unsigned(value.span.end);
}

_a_Pattern_read(input: RecordIn): ast.Pattern {
    var _o395 = Optional<ast.Expression>.Empty;
    if (input.unsigned() == 1) {
        _o395 = Optional<ast.Expression>.Value(_a_Expression_read(input));
    }
    var _f396 = _o395;
    var _o397 = Optional<Array<ast.Pattern>>.Empty;
    if (input.unsigned() == 1) {
        var _v398 = Array<ast.Pattern>();
        var _n399 = input.count();
        for (var _ in 0.._n399) {
            _v398.append(_a_Pattern_read(input));
        }
        _o397 = Optional<Array<ast.Pattern>>.Value(_v398);
    }
    var _f400 = _o397;
    var _o401 = Optional<ast.TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o401 = Optional<ast.TypeName>.Value(_a_TypeName_read(input));
    }
    var _f402 = _o401;
    var _f403 = input.text();
    var _s404 = input.unsigned();
    var _f405 = ast.Span(_s404, input.unsigned());
    var _o406 = Optional<Array<ast.Pattern>>.Empty;
    if (input.unsigned() == 1) {
        var _v407 = Array<ast.Pattern>();
        var _n408 = input.count();
        for (var _ in 0.._n408) {
            _v407.append(_a_Pattern_read(input));
        }
        _o406 = Optional<Array<ast.Pattern>>.Value(_v407);
    }
    var _f409 = _o406;
    var _o410 = Optional<ast.Expression>.Empty;
    if (input.unsigned() == 1) {
        _o410 = Optional<ast.Expression>.Value(_a_Expression_read(input));
    }
    var _f411 = _o410;
    var _f412 = input.flag();
    var _o413 = Optional<String>.Empty;
    if (input.unsigned() == 1) {
        _o413 = Optional<String>.Value(input.text());
    }
    var _f414 = _o413;
    var _o415 = Optional<ast.TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o415 = Optional<ast.TypeName>.Value(_a_TypeName_read(input));
    }
    var _f416 = _o415;
    var _s417 = input.unsigned();
    var _f418 = ast.Span(_s417, input.unsigned());
    var value = ast.Pattern();
    value.literal = _f396;
    value.elements = _f400;
    value.qualifier = _f402;
    value.case_name = _f403;
    value.case_span = _f405;
    value.bindings = _f409;
    value.range_end = _f411;
    value.range_inclusive = _f412;
    value.constant = _f414;
    value.type_name = _f416;
    value.span = _f418;
    return value;
}

_a_TypeName_write(out: RecordOut, value: ast.TypeName) {
    out.text(value.name);
    out.unsigned(value.generic_types.count);
    for (var _item419 in value.generic_types) {
        _a_TypeName_write(out, _item419);
    }
    out.unsigned(value.span.start);
    out.unsigned(value.span.end);
    out.unsigned(value.labels.count);
    for (var _item420 in value.labels) {
        out.text(_item420);
    }
}

_a_TypeName_read(input: RecordIn): ast.TypeName {
    var _f421 = input.text();
    var _v422 = Array<ast.TypeName>();
    var _n423 = input.count();
    for (var _ in 0.._n423) {
        _v422.append(_a_TypeName_read(input));
    }
    var _f424 = _v422;
    var _s425 = input.unsigned();
    var _f426 = ast.Span(_s425, input.unsigned());
    var _v427 = Array<String>();
    var _n428 = input.count();
    for (var _ in 0.._n428) {
        _v427.append(input.text());
    }
    var _f429 = _v427;
    var value = ast.TypeName();
    value.name = _f421;
    value.generic_types = _f424;
    value.span = _f426;
    value.labels = _f429;
    return value;
}

_a_MatchExpression_write(out: RecordOut, value: ast.MatchExpression) {
    _a_Expression_write(out, value.value);
    out.unsigned(value.arms.count);
    for (var _item430 in value.arms) {
        _a_MatchValueArm_write(out, _item430);
    }
    if (value.else_value.is_value()) {
        out.unsigned(1);
        _a_Expression_write(out, value.else_value.value());
    } else {
        out.unsigned(0);
    }
    out.unsigned(value.else_span.start);
    out.unsigned(value.else_span.end);
    out.unsigned(value.keyword_span.start);
    out.unsigned(value.keyword_span.end);
    out.unsigned(value.span.start);
    out.unsigned(value.span.end);
}

_a_MatchExpression_read(input: RecordIn): ast.MatchExpression {
    var _f431 = _a_Expression_read(input);
    var _v432 = Array<ast.MatchValueArm>();
    var _n433 = input.count();
    for (var _ in 0.._n433) {
        _v432.append(_a_MatchValueArm_read(input));
    }
    var _f434 = _v432;
    var _o435 = Optional<ast.Expression>.Empty;
    if (input.unsigned() == 1) {
        _o435 = Optional<ast.Expression>.Value(_a_Expression_read(input));
    }
    var _f436 = _o435;
    var _s437 = input.unsigned();
    var _f438 = ast.Span(_s437, input.unsigned());
    var _s439 = input.unsigned();
    var _f440 = ast.Span(_s439, input.unsigned());
    var _s441 = input.unsigned();
    var _f442 = ast.Span(_s441, input.unsigned());
    var value = ast.MatchExpression(_f431);
    value.value = _f431;
    value.arms = _f434;
    value.else_value = _f436;
    value.else_span = _f438;
    value.keyword_span = _f440;
    value.span = _f442;
    return value;
}

_a_MatchValueArm_write(out: RecordOut, value: ast.MatchValueArm) {
    out.unsigned(value.patterns.count);
    for (var _item443 in value.patterns) {
        _a_Pattern_write(out, _item443);
    }
    if (value.guard.is_value()) {
        out.unsigned(1);
        _a_Expression_write(out, value.guard.value());
    } else {
        out.unsigned(0);
    }
    _a_Expression_write(out, value.value);
    out.unsigned(value.span.start);
    out.unsigned(value.span.end);
}

_a_MatchValueArm_read(input: RecordIn): ast.MatchValueArm {
    var _v444 = Array<ast.Pattern>();
    var _n445 = input.count();
    for (var _ in 0.._n445) {
        _v444.append(_a_Pattern_read(input));
    }
    var _f446 = _v444;
    var _o447 = Optional<ast.Expression>.Empty;
    if (input.unsigned() == 1) {
        _o447 = Optional<ast.Expression>.Value(_a_Expression_read(input));
    }
    var _f448 = _o447;
    var _f449 = _a_Expression_read(input);
    var _s450 = input.unsigned();
    var _f451 = ast.Span(_s450, input.unsigned());
    var value = ast.MatchValueArm();
    value.patterns = _f446;
    value.guard = _f448;
    value.value = _f449;
    value.span = _f451;
    return value;
}

_a_MapEntry_write(out: RecordOut, value: ast.MapEntry) {
    _a_Expression_write(out, value.key);
    _a_Expression_write(out, value.value);
}

_a_MapEntry_read(input: RecordIn): ast.MapEntry {
    var _f452 = _a_Expression_read(input);
    var _f453 = _a_Expression_read(input);
    var value = ast.MapEntry(_f452, _f453);
    value.key = _f452;
    value.value = _f453;
    return value;
}

_a_Label_write(out: RecordOut, value: ast.Label) {
    out.text(value.name);
    out.unsigned(value.span.start);
    out.unsigned(value.span.end);
}

_a_Label_read(input: RecordIn): ast.Label {
    var _f454 = input.text();
    var _s455 = input.unsigned();
    var _f456 = ast.Span(_s455, input.unsigned());
    var value = ast.Label(_f454, _f456);
    value.name = _f454;
    value.span = _f456;
    return value;
}

_a_ClosureLiteral_write(out: RecordOut, value: ast.ClosureLiteral) {
    out.unsigned(value.parameters.count);
    for (var _item457 in value.parameters) {
        _a_VariableDecl_write(out, _item457);
    }
    _a_TypeName_write(out, value.return_type);
    _a_Block_write(out, value.body);
    out.flag(value.expression_body);
    out.unsigned(value.span.start);
    out.unsigned(value.span.end);
}

_a_ClosureLiteral_read(input: RecordIn): ast.ClosureLiteral {
    var _v458 = Array<ast.VariableDecl>();
    var _n459 = input.count();
    for (var _ in 0.._n459) {
        _v458.append(_a_VariableDecl_read(input));
    }
    var _f460 = _v458;
    var _f461 = _a_TypeName_read(input);
    var _f462 = _a_Block_read(input);
    var _f463 = input.flag();
    var _s464 = input.unsigned();
    var _f465 = ast.Span(_s464, input.unsigned());
    var value = ast.ClosureLiteral();
    value.parameters = _f460;
    value.return_type = _f461;
    value.body = _f462;
    value.expression_body = _f463;
    value.span = _f465;
    return value;
}

_a_Block_write(out: RecordOut, value: ast.Block) {
    out.unsigned(value.statements.count);
    for (var _item466 in value.statements) {
        _a_Statement_write(out, _item466);
    }
    out.unsigned(value.span.start);
    out.unsigned(value.span.end);
    out.unsigned(value.attributes.count);
    for (var _item467 in value.attributes) {
        _a_Attribute_write(out, _item467);
    }
}

_a_Block_read(input: RecordIn): ast.Block {
    var _v468 = Array<ast.Statement>();
    var _n469 = input.count();
    for (var _ in 0.._n469) {
        _v468.append(_a_Statement_read(input));
    }
    var _f470 = _v468;
    var _s471 = input.unsigned();
    var _f472 = ast.Span(_s471, input.unsigned());
    var _v473 = Array<ast.Attribute>();
    var _n474 = input.count();
    for (var _ in 0.._n474) {
        _v473.append(_a_Attribute_read(input));
    }
    var _f475 = _v473;
    var value = ast.Block();
    value.statements = _f470;
    value.span = _f472;
    value.attributes = _f475;
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
            out.unsigned(p3.start);
            out.unsigned(p3.end);
        }
        While(p0, p1, p2) => {
            out.unsigned(4);
            _a_Expression_write(out, p0);
            _a_Block_write(out, p1);
            out.unsigned(p2.start);
            out.unsigned(p2.end);
        }
        For(p0, p1, p2, p3, p4) => {
            out.unsigned(5);
            _a_VariableDecl_write(out, p0);
            out.unsigned(p1.count);
            for (var _item490 in p1) {
                _a_DestructureBinding_write(out, _item490);
            }
            _a_Expression_write(out, p2);
            _a_Block_write(out, p3);
            out.unsigned(p4.start);
            out.unsigned(p4.end);
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
            out.unsigned(p4.start);
            out.unsigned(p4.end);
        }
        Return(p0, p1) => {
            out.unsigned(7);
            if (p0.is_value()) {
                out.unsigned(1);
                _a_Expression_write(out, p0.value());
            } else {
                out.unsigned(0);
            }
            out.unsigned(p1.start);
            out.unsigned(p1.end);
        }
        LoopBreak(p0, p1) => {
            out.unsigned(8);
            out.flag(p0);
            out.unsigned(p1.start);
            out.unsigned(p1.end);
        }
        Destructure(p0, p1, p2, p3) => {
            out.unsigned(9);
            out.unsigned(p0.count);
            for (var _item513 in p0) {
                _a_DestructureBinding_write(out, _item513);
            }
            _a_Expression_write(out, p1);
            out.flag(p2);
            out.unsigned(p3.start);
            out.unsigned(p3.end);
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
        var _f476 = _a_Expression_read(input);
        return ast.Statement.Expression(_f476);
    }
    if (tag == 1) {
        var _f477 = _a_Block_read(input);
        return ast.Statement.Block(_f477);
    }
    if (tag == 2) {
        var _f478 = _a_Declaration_read(input);
        return ast.Statement.Declaration(_f478);
    }
    if (tag == 3) {
        var _f479 = _a_Expression_read(input);
        var _f480 = _a_Block_read(input);
        var _o481 = Optional<ast.Block>.Empty;
        if (input.unsigned() == 1) {
            _o481 = Optional<ast.Block>.Value(_a_Block_read(input));
        }
        var _f482 = _o481;
        var _s483 = input.unsigned();
        var _f484 = ast.Span(_s483, input.unsigned());
        return ast.Statement.Branch(_f479, _f480, _f482, _f484);
    }
    if (tag == 4) {
        var _f485 = _a_Expression_read(input);
        var _f486 = _a_Block_read(input);
        var _s487 = input.unsigned();
        var _f488 = ast.Span(_s487, input.unsigned());
        return ast.Statement.While(_f485, _f486, _f488);
    }
    if (tag == 5) {
        var _f489 = _a_VariableDecl_read(input);
        var _v491 = Array<ast.DestructureBinding>();
        var _n492 = input.count();
        for (var _ in 0.._n492) {
            _v491.append(_a_DestructureBinding_read(input));
        }
        var _f493 = _v491;
        var _f494 = _a_Expression_read(input);
        var _f495 = _a_Block_read(input);
        var _s496 = input.unsigned();
        var _f497 = ast.Span(_s496, input.unsigned());
        return ast.Statement.For(_f489, _f493, _f494, _f495, _f497);
    }
    if (tag == 6) {
        var _o498 = Optional<ast.VariableDecl>.Empty;
        if (input.unsigned() == 1) {
            _o498 = Optional<ast.VariableDecl>.Value(_a_VariableDecl_read(input));
        }
        var _f499 = _o498;
        var _f500 = _a_Expression_read(input);
        var _f501 = _a_Block_read(input);
        var _o502 = Optional<ast.Block>.Empty;
        if (input.unsigned() == 1) {
            _o502 = Optional<ast.Block>.Value(_a_Block_read(input));
        }
        var _f503 = _o502;
        var _s504 = input.unsigned();
        var _f505 = ast.Span(_s504, input.unsigned());
        return ast.Statement.With(_f499, _f500, _f501, _f503, _f505);
    }
    if (tag == 7) {
        var _o506 = Optional<ast.Expression>.Empty;
        if (input.unsigned() == 1) {
            _o506 = Optional<ast.Expression>.Value(_a_Expression_read(input));
        }
        var _f507 = _o506;
        var _s508 = input.unsigned();
        var _f509 = ast.Span(_s508, input.unsigned());
        return ast.Statement.Return(_f507, _f509);
    }
    if (tag == 8) {
        var _f510 = input.flag();
        var _s511 = input.unsigned();
        var _f512 = ast.Span(_s511, input.unsigned());
        return ast.Statement.LoopBreak(_f510, _f512);
    }
    if (tag == 9) {
        var _v514 = Array<ast.DestructureBinding>();
        var _n515 = input.count();
        for (var _ in 0.._n515) {
            _v514.append(_a_DestructureBinding_read(input));
        }
        var _f516 = _v514;
        var _f517 = _a_Expression_read(input);
        var _f518 = input.flag();
        var _s519 = input.unsigned();
        var _f520 = ast.Span(_s519, input.unsigned());
        return ast.Statement.Destructure(_f516, _f517, _f518, _f520);
    }
    if (tag == 10) {
        var _f521 = _a_Match_read(input);
        return ast.Statement.Match(_f521);
    }
    if (tag == 11) {
        var _f522 = _a_StaticBlock_read(input);
        return ast.Statement.Static(_f522);
    }
    input.fail("Statement", tag);
    return _a_Statement_read(input);
}

_a_StaticBlock_write(out: RecordOut, value: ast.StaticBlock) {
    out.unsigned(value.captures.count);
    for (var _item523 in value.captures) {
        _a_Label_write(out, _item523);
    }
    out.unsigned(value.written_captures.count);
    for (var _item524 in value.written_captures) {
        _a_Expression_write(out, _item524);
    }
    _a_Block_write(out, value.block);
    out.unsigned(value.keyword_span.start);
    out.unsigned(value.keyword_span.end);
    out.unsigned(value.span.start);
    out.unsigned(value.span.end);
    out.unsigned(value.attributes.count);
    for (var _item525 in value.attributes) {
        _a_Attribute_write(out, _item525);
    }
    out.flag(value.is_exported);
    out.flag(value.is_private);
}

_a_StaticBlock_read(input: RecordIn): ast.StaticBlock {
    var _v526 = Array<ast.Label>();
    var _n527 = input.count();
    for (var _ in 0.._n527) {
        _v526.append(_a_Label_read(input));
    }
    var _f528 = _v526;
    var _v529 = Array<ast.Expression>();
    var _n530 = input.count();
    for (var _ in 0.._n530) {
        _v529.append(_a_Expression_read(input));
    }
    var _f531 = _v529;
    var _f532 = _a_Block_read(input);
    var _s533 = input.unsigned();
    var _f534 = ast.Span(_s533, input.unsigned());
    var _s535 = input.unsigned();
    var _f536 = ast.Span(_s535, input.unsigned());
    var _v537 = Array<ast.Attribute>();
    var _n538 = input.count();
    for (var _ in 0.._n538) {
        _v537.append(_a_Attribute_read(input));
    }
    var _f539 = _v537;
    var _f540 = input.flag();
    var _f541 = input.flag();
    var value = ast.StaticBlock();
    value.captures = _f528;
    value.written_captures = _f531;
    value.block = _f532;
    value.keyword_span = _f534;
    value.span = _f536;
    value.attributes = _f539;
    value.is_exported = _f540;
    value.is_private = _f541;
    return value;
}

_a_Match_write(out: RecordOut, value: ast.Match) {
    _a_Expression_write(out, value.value);
    out.unsigned(value.arms.count);
    for (var _item542 in value.arms) {
        _a_MatchArm_write(out, _item542);
    }
    if (value.else_block.is_value()) {
        out.unsigned(1);
        _a_Block_write(out, value.else_block.value());
    } else {
        out.unsigned(0);
    }
    out.unsigned(value.else_span.start);
    out.unsigned(value.else_span.end);
    out.unsigned(value.keyword_span.start);
    out.unsigned(value.keyword_span.end);
    out.unsigned(value.span.start);
    out.unsigned(value.span.end);
}

_a_Match_read(input: RecordIn): ast.Match {
    var _f543 = _a_Expression_read(input);
    var _v544 = Array<ast.MatchArm>();
    var _n545 = input.count();
    for (var _ in 0.._n545) {
        _v544.append(_a_MatchArm_read(input));
    }
    var _f546 = _v544;
    var _o547 = Optional<ast.Block>.Empty;
    if (input.unsigned() == 1) {
        _o547 = Optional<ast.Block>.Value(_a_Block_read(input));
    }
    var _f548 = _o547;
    var _s549 = input.unsigned();
    var _f550 = ast.Span(_s549, input.unsigned());
    var _s551 = input.unsigned();
    var _f552 = ast.Span(_s551, input.unsigned());
    var _s553 = input.unsigned();
    var _f554 = ast.Span(_s553, input.unsigned());
    var value = ast.Match(_f543);
    value.value = _f543;
    value.arms = _f546;
    value.else_block = _f548;
    value.else_span = _f550;
    value.keyword_span = _f552;
    value.span = _f554;
    return value;
}

_a_MatchArm_write(out: RecordOut, value: ast.MatchArm) {
    out.unsigned(value.patterns.count);
    for (var _item555 in value.patterns) {
        _a_Pattern_write(out, _item555);
    }
    if (value.guard.is_value()) {
        out.unsigned(1);
        _a_Expression_write(out, value.guard.value());
    } else {
        out.unsigned(0);
    }
    _a_Block_write(out, value.body);
    out.unsigned(value.span.start);
    out.unsigned(value.span.end);
}

_a_MatchArm_read(input: RecordIn): ast.MatchArm {
    var _v556 = Array<ast.Pattern>();
    var _n557 = input.count();
    for (var _ in 0.._n557) {
        _v556.append(_a_Pattern_read(input));
    }
    var _f558 = _v556;
    var _o559 = Optional<ast.Expression>.Empty;
    if (input.unsigned() == 1) {
        _o559 = Optional<ast.Expression>.Value(_a_Expression_read(input));
    }
    var _f560 = _o559;
    var _f561 = _a_Block_read(input);
    var _s562 = input.unsigned();
    var _f563 = ast.Span(_s562, input.unsigned());
    var value = ast.MatchArm();
    value.patterns = _f558;
    value.guard = _f560;
    value.body = _f561;
    value.span = _f563;
    return value;
}

_a_DestructureBinding_write(out: RecordOut, value: ast.DestructureBinding) {
    out.text(value.name);
    out.unsigned(value.name_span.start);
    out.unsigned(value.name_span.end);
    _a_TypeName_write(out, value.type_name);
    out.unsigned(value.nested.count);
    for (var _item564 in value.nested) {
        _a_DestructureBinding_write(out, _item564);
    }
}

_a_DestructureBinding_read(input: RecordIn): ast.DestructureBinding {
    var _f565 = input.text();
    var _s566 = input.unsigned();
    var _f567 = ast.Span(_s566, input.unsigned());
    var _f568 = _a_TypeName_read(input);
    var _v569 = Array<ast.DestructureBinding>();
    var _n570 = input.count();
    for (var _ in 0.._n570) {
        _v569.append(_a_DestructureBinding_read(input));
    }
    var _f571 = _v569;
    var value = ast.DestructureBinding();
    value.name = _f565;
    value.name_span = _f567;
    value.type_name = _f568;
    value.nested = _f571;
    return value;
}

_a_VariableDecl_write(out: RecordOut, value: ast.VariableDecl) {
    out.unsigned(value.attributes.count);
    for (var _item572 in value.attributes) {
        _a_Attribute_write(out, _item572);
    }
    out.text(value.name);
    out.unsigned(value.name_span.start);
    out.unsigned(value.name_span.end);
    _a_TypeName_write(out, value.type_name);
    if (value.default_value.is_value()) {
        out.unsigned(1);
        _a_Expression_write(out, value.default_value.value());
    } else {
        out.unsigned(0);
    }
    out.flag(value.is_const);
    out.unsigned(value.span.start);
    out.unsigned(value.span.end);
    out.flag(value.is_exported);
    out.flag(value.is_private);
}

_a_VariableDecl_read(input: RecordIn): ast.VariableDecl {
    var _v573 = Array<ast.Attribute>();
    var _n574 = input.count();
    for (var _ in 0.._n574) {
        _v573.append(_a_Attribute_read(input));
    }
    var _f575 = _v573;
    var _f576 = input.text();
    var _s577 = input.unsigned();
    var _f578 = ast.Span(_s577, input.unsigned());
    var _f579 = _a_TypeName_read(input);
    var _o580 = Optional<ast.Expression>.Empty;
    if (input.unsigned() == 1) {
        _o580 = Optional<ast.Expression>.Value(_a_Expression_read(input));
    }
    var _f581 = _o580;
    var _f582 = input.flag();
    var _s583 = input.unsigned();
    var _f584 = ast.Span(_s583, input.unsigned());
    var _f585 = input.flag();
    var _f586 = input.flag();
    var value = ast.VariableDecl();
    value.attributes = _f575;
    value.name = _f576;
    value.name_span = _f578;
    value.type_name = _f579;
    value.default_value = _f581;
    value.is_const = _f582;
    value.span = _f584;
    value.is_exported = _f585;
    value.is_private = _f586;
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
        var _f587 = _a_VariableDecl_read(input);
        return ast.Declaration.Variable(_f587);
    }
    if (tag == 1) {
        var _f588 = _a_FunctionDecl_read(input);
        return ast.Declaration.Function(_f588);
    }
    if (tag == 2) {
        var _f589 = _a_StructDecl_read(input);
        return ast.Declaration.Struct(_f589);
    }
    if (tag == 3) {
        var _f590 = _a_TraitDecl_read(input);
        return ast.Declaration.Trait(_f590);
    }
    if (tag == 4) {
        var _f591 = _a_ExtendDecl_read(input);
        return ast.Declaration.Extend(_f591);
    }
    if (tag == 5) {
        var _f592 = _a_TypeAliasDecl_read(input);
        return ast.Declaration.TypeAlias(_f592);
    }
    if (tag == 6) {
        var _f593 = _a_StaticBlock_read(input);
        return ast.Declaration.Static(_f593);
    }
    input.fail("Declaration", tag);
    return _a_Declaration_read(input);
}

_a_TypeAliasDecl_write(out: RecordOut, value: ast.TypeAliasDecl) {
    out.unsigned(value.attributes.count);
    for (var _item594 in value.attributes) {
        _a_Attribute_write(out, _item594);
    }
    out.text(value.name);
    out.unsigned(value.name_span.start);
    out.unsigned(value.name_span.end);
    out.unsigned(value.generic_params.count);
    for (var _item595 in value.generic_params) {
        _a_GenericParam_write(out, _item595);
    }
    _a_TypeName_write(out, value.target);
    out.unsigned(value.span.start);
    out.unsigned(value.span.end);
    out.flag(value.is_exported);
    out.flag(value.is_private);
}

_a_TypeAliasDecl_read(input: RecordIn): ast.TypeAliasDecl {
    var _v596 = Array<ast.Attribute>();
    var _n597 = input.count();
    for (var _ in 0.._n597) {
        _v596.append(_a_Attribute_read(input));
    }
    var _f598 = _v596;
    var _f599 = input.text();
    var _s600 = input.unsigned();
    var _f601 = ast.Span(_s600, input.unsigned());
    var _v602 = Array<ast.GenericParam>();
    var _n603 = input.count();
    for (var _ in 0.._n603) {
        _v602.append(_a_GenericParam_read(input));
    }
    var _f604 = _v602;
    var _f605 = _a_TypeName_read(input);
    var _s606 = input.unsigned();
    var _f607 = ast.Span(_s606, input.unsigned());
    var _f608 = input.flag();
    var _f609 = input.flag();
    var value = ast.TypeAliasDecl();
    value.attributes = _f598;
    value.name = _f599;
    value.name_span = _f601;
    value.generic_params = _f604;
    value.target = _f605;
    value.span = _f607;
    value.is_exported = _f608;
    value.is_private = _f609;
    return value;
}

_a_GenericParam_write(out: RecordOut, value: ast.GenericParam) {
    out.text(value.name);
    out.unsigned(value.name_span.start);
    out.unsigned(value.name_span.end);
    out.unsigned(value.bounds.count);
    for (var _item610 in value.bounds) {
        _a_TypeName_write(out, _item610);
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
    var _f611 = input.text();
    var _s612 = input.unsigned();
    var _f613 = ast.Span(_s612, input.unsigned());
    var _v614 = Array<ast.TypeName>();
    var _n615 = input.count();
    for (var _ in 0.._n615) {
        _v614.append(_a_TypeName_read(input));
    }
    var _f616 = _v614;
    var _o617 = Optional<ast.TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o617 = Optional<ast.TypeName>.Value(_a_TypeName_read(input));
    }
    var _f618 = _o617;
    var _f619 = input.flag();
    var value = ast.GenericParam(_f611, _f613);
    value.name = _f611;
    value.name_span = _f613;
    value.bounds = _f616;
    value.default = _f618;
    value.is_argument = _f619;
    return value;
}

_a_ExtendDecl_write(out: RecordOut, value: ast.ExtendDecl) {
    out.unsigned(value.attributes.count);
    for (var _item620 in value.attributes) {
        _a_Attribute_write(out, _item620);
    }
    _a_TypeName_write(out, value.target);
    out.unsigned(value.target_bounds.count);
    for (var _item621 in value.target_bounds) {
        out.unsigned(_item621.count);
        for (var _item622 in _item621) {
            _a_TypeName_write(out, _item622);
        }
    }
    out.unsigned(value.traits.count);
    for (var _item623 in value.traits) {
        _a_TypeName_write(out, _item623);
    }
    out.unsigned(value.methods.count);
    for (var _item624 in value.methods) {
        _a_FunctionDecl_write(out, _item624);
    }
    out.unsigned(value.properties.count);
    for (var _item625 in value.properties) {
        _a_PropertyDecl_write(out, _item625);
    }
    out.unsigned(value.span.start);
    out.unsigned(value.span.end);
    out.flag(value.is_exported);
    out.flag(value.is_private);
}

_a_ExtendDecl_read(input: RecordIn): ast.ExtendDecl {
    var _v626 = Array<ast.Attribute>();
    var _n627 = input.count();
    for (var _ in 0.._n627) {
        _v626.append(_a_Attribute_read(input));
    }
    var _f628 = _v626;
    var _f629 = _a_TypeName_read(input);
    var _v630 = Array<Array<ast.TypeName>>();
    var _n631 = input.count();
    for (var _ in 0.._n631) {
        var _v632 = Array<ast.TypeName>();
        var _n633 = input.count();
        for (var _ in 0.._n633) {
            _v632.append(_a_TypeName_read(input));
        }
        _v630.append(_v632);
    }
    var _f634 = _v630;
    var _v635 = Array<ast.TypeName>();
    var _n636 = input.count();
    for (var _ in 0.._n636) {
        _v635.append(_a_TypeName_read(input));
    }
    var _f637 = _v635;
    var _v638 = Array<ast.FunctionDecl>();
    var _n639 = input.count();
    for (var _ in 0.._n639) {
        _v638.append(_a_FunctionDecl_read(input));
    }
    var _f640 = _v638;
    var _v641 = Array<ast.PropertyDecl>();
    var _n642 = input.count();
    for (var _ in 0.._n642) {
        _v641.append(_a_PropertyDecl_read(input));
    }
    var _f643 = _v641;
    var _s644 = input.unsigned();
    var _f645 = ast.Span(_s644, input.unsigned());
    var _f646 = input.flag();
    var _f647 = input.flag();
    var value = ast.ExtendDecl();
    value.attributes = _f628;
    value.target = _f629;
    value.target_bounds = _f634;
    value.traits = _f637;
    value.methods = _f640;
    value.properties = _f643;
    value.span = _f645;
    value.is_exported = _f646;
    value.is_private = _f647;
    return value;
}

_a_PropertyDecl_write(out: RecordOut, value: ast.PropertyDecl) {
    out.unsigned(value.attributes.count);
    for (var _item648 in value.attributes) {
        _a_Attribute_write(out, _item648);
    }
    out.text(value.name);
    out.unsigned(value.name_span.start);
    out.unsigned(value.name_span.end);
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
    out.unsigned(value.span.start);
    out.unsigned(value.span.end);
}

_a_PropertyDecl_read(input: RecordIn): ast.PropertyDecl {
    var _v649 = Array<ast.Attribute>();
    var _n650 = input.count();
    for (var _ in 0.._n650) {
        _v649.append(_a_Attribute_read(input));
    }
    var _f651 = _v649;
    var _f652 = input.text();
    var _s653 = input.unsigned();
    var _f654 = ast.Span(_s653, input.unsigned());
    var _f655 = _a_TypeName_read(input);
    var _o656 = Optional<ast.Expression>.Empty;
    if (input.unsigned() == 1) {
        _o656 = Optional<ast.Expression>.Value(_a_Expression_read(input));
    }
    var _f657 = _o656;
    var _o658 = Optional<ast.Accessor>.Empty;
    if (input.unsigned() == 1) {
        _o658 = Optional<ast.Accessor>.Value(_a_Accessor_read(input));
    }
    var _f659 = _o658;
    var _o660 = Optional<ast.Accessor>.Empty;
    if (input.unsigned() == 1) {
        _o660 = Optional<ast.Accessor>.Value(_a_Accessor_read(input));
    }
    var _f661 = _o660;
    var _s662 = input.unsigned();
    var _f663 = ast.Span(_s662, input.unsigned());
    var value = ast.PropertyDecl();
    value.attributes = _f651;
    value.name = _f652;
    value.name_span = _f654;
    value.type_name = _f655;
    value.default_value = _f657;
    value.getter = _f659;
    value.setter = _f661;
    value.span = _f663;
    return value;
}

_a_Accessor_write(out: RecordOut, value: ast.Accessor) {
    out.unsigned(value.span.start);
    out.unsigned(value.span.end);
    _a_FunctionDecl_write(out, value.function);
}

_a_Accessor_read(input: RecordIn): ast.Accessor {
    var _s664 = input.unsigned();
    var _f665 = ast.Span(_s664, input.unsigned());
    var _f666 = _a_FunctionDecl_read(input);
    var value = ast.Accessor(_f665, _f666);
    value.span = _f665;
    value.function = _f666;
    return value;
}

_a_FunctionDecl_write(out: RecordOut, value: ast.FunctionDecl) {
    out.text(value.name);
    out.unsigned(value.name_span.start);
    out.unsigned(value.name_span.end);
    out.unsigned(value.generic_params.count);
    for (var _item667 in value.generic_params) {
        _a_GenericParam_write(out, _item667);
    }
    _a_TypeName_write(out, value.return_type);
    out.unsigned(value.parameters.count);
    for (var _item668 in value.parameters) {
        _a_VariableDecl_write(out, _item668);
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
    out.unsigned(value.span.start);
    out.unsigned(value.span.end);
    out.unsigned(value.attributes.count);
    for (var _item669 in value.attributes) {
        _a_Attribute_write(out, _item669);
    }
    out.flag(value.is_exported);
    out.flag(value.is_private);
}

_a_FunctionDecl_read(input: RecordIn): ast.FunctionDecl {
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
    var _v677 = Array<ast.VariableDecl>();
    var _n678 = input.count();
    for (var _ in 0.._n678) {
        _v677.append(_a_VariableDecl_read(input));
    }
    var _f679 = _v677;
    var _f680 = input.flag();
    var _o681 = Optional<ast.Block>.Empty;
    if (input.unsigned() == 1) {
        _o681 = Optional<ast.Block>.Value(_a_Block_read(input));
    }
    var _f682 = _o681;
    var _f683 = input.flag();
    var _f684 = input.flag();
    var _f685 = input.flag();
    var _s686 = input.unsigned();
    var _f687 = ast.Span(_s686, input.unsigned());
    var _v688 = Array<ast.Attribute>();
    var _n689 = input.count();
    for (var _ in 0.._n689) {
        _v688.append(_a_Attribute_read(input));
    }
    var _f690 = _v688;
    var _f691 = input.flag();
    var _f692 = input.flag();
    var value = ast.FunctionDecl();
    value.name = _f670;
    value.name_span = _f672;
    value.generic_params = _f675;
    value.return_type = _f676;
    value.parameters = _f679;
    value.external = _f680;
    value.body = _f682;
    value.is_static = _f683;
    value.is_indexer = _f684;
    value.is_variadic = _f685;
    value.span = _f687;
    value.attributes = _f690;
    value.is_exported = _f691;
    value.is_private = _f692;
    return value;
}

_a_TraitDecl_write(out: RecordOut, value: ast.TraitDecl) {
    out.unsigned(value.attributes.count);
    for (var _item693 in value.attributes) {
        _a_Attribute_write(out, _item693);
    }
    out.text(value.name);
    out.unsigned(value.name_span.start);
    out.unsigned(value.name_span.end);
    out.unsigned(value.generic_params.count);
    for (var _item694 in value.generic_params) {
        _a_GenericParam_write(out, _item694);
    }
    out.unsigned(value.methods.count);
    for (var _item695 in value.methods) {
        _a_FunctionDecl_write(out, _item695);
    }
    out.unsigned(value.properties.count);
    for (var _item696 in value.properties) {
        _a_PropertyDecl_write(out, _item696);
    }
    out.unsigned(value.span.start);
    out.unsigned(value.span.end);
    out.flag(value.is_exported);
    out.flag(value.is_private);
}

_a_TraitDecl_read(input: RecordIn): ast.TraitDecl {
    var _v697 = Array<ast.Attribute>();
    var _n698 = input.count();
    for (var _ in 0.._n698) {
        _v697.append(_a_Attribute_read(input));
    }
    var _f699 = _v697;
    var _f700 = input.text();
    var _s701 = input.unsigned();
    var _f702 = ast.Span(_s701, input.unsigned());
    var _v703 = Array<ast.GenericParam>();
    var _n704 = input.count();
    for (var _ in 0.._n704) {
        _v703.append(_a_GenericParam_read(input));
    }
    var _f705 = _v703;
    var _v706 = Array<ast.FunctionDecl>();
    var _n707 = input.count();
    for (var _ in 0.._n707) {
        _v706.append(_a_FunctionDecl_read(input));
    }
    var _f708 = _v706;
    var _v709 = Array<ast.PropertyDecl>();
    var _n710 = input.count();
    for (var _ in 0.._n710) {
        _v709.append(_a_PropertyDecl_read(input));
    }
    var _f711 = _v709;
    var _s712 = input.unsigned();
    var _f713 = ast.Span(_s712, input.unsigned());
    var _f714 = input.flag();
    var _f715 = input.flag();
    var value = ast.TraitDecl();
    value.attributes = _f699;
    value.name = _f700;
    value.name_span = _f702;
    value.generic_params = _f705;
    value.methods = _f708;
    value.properties = _f711;
    value.span = _f713;
    value.is_exported = _f714;
    value.is_private = _f715;
    return value;
}

_a_StructDecl_write(out: RecordOut, value: ast.StructDecl) {
    out.text(value.name);
    out.unsigned(value.name_span.start);
    out.unsigned(value.name_span.end);
    out.unsigned(value.generic_params.count);
    for (var _item716 in value.generic_params) {
        _a_GenericParam_write(out, _item716);
    }
    out.unsigned(value.fields.count);
    for (var _item717 in value.fields) {
        _a_VariableDecl_write(out, _item717);
    }
    out.unsigned(value.properties.count);
    for (var _item718 in value.properties) {
        _a_PropertyDecl_write(out, _item718);
    }
    out.unsigned(value.methods.count);
    for (var _item719 in value.methods) {
        _a_FunctionDecl_write(out, _item719);
    }
    out.unsigned(value.constructors.count);
    for (var _item720 in value.constructors) {
        _a_FunctionDecl_write(out, _item720);
    }
    if (value.destructor.is_value()) {
        out.unsigned(1);
        _a_Block_write(out, value.destructor.value());
    } else {
        out.unsigned(0);
    }
    if (value.destruct_span.is_value()) {
        out.unsigned(1);
        out.unsigned(value.destruct_span.value().start);
        out.unsigned(value.destruct_span.value().end);
    } else {
        out.unsigned(0);
    }
    out.unsigned(value.span.start);
    out.unsigned(value.span.end);
    out.unsigned(value.attributes.count);
    for (var _item721 in value.attributes) {
        _a_Attribute_write(out, _item721);
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
    var _f722 = input.text();
    var _s723 = input.unsigned();
    var _f724 = ast.Span(_s723, input.unsigned());
    var _v725 = Array<ast.GenericParam>();
    var _n726 = input.count();
    for (var _ in 0.._n726) {
        _v725.append(_a_GenericParam_read(input));
    }
    var _f727 = _v725;
    var _v728 = Array<ast.VariableDecl>();
    var _n729 = input.count();
    for (var _ in 0.._n729) {
        _v728.append(_a_VariableDecl_read(input));
    }
    var _f730 = _v728;
    var _v731 = Array<ast.PropertyDecl>();
    var _n732 = input.count();
    for (var _ in 0.._n732) {
        _v731.append(_a_PropertyDecl_read(input));
    }
    var _f733 = _v731;
    var _v734 = Array<ast.FunctionDecl>();
    var _n735 = input.count();
    for (var _ in 0.._n735) {
        _v734.append(_a_FunctionDecl_read(input));
    }
    var _f736 = _v734;
    var _v737 = Array<ast.FunctionDecl>();
    var _n738 = input.count();
    for (var _ in 0.._n738) {
        _v737.append(_a_FunctionDecl_read(input));
    }
    var _f739 = _v737;
    var _o740 = Optional<ast.Block>.Empty;
    if (input.unsigned() == 1) {
        _o740 = Optional<ast.Block>.Value(_a_Block_read(input));
    }
    var _f741 = _o740;
    var _o742 = Optional<ast.Span>.Empty;
    if (input.unsigned() == 1) {
        var _s743 = input.unsigned();
        _o742 = Optional<ast.Span>.Value(ast.Span(_s743, input.unsigned()));
    }
    var _f744 = _o742;
    var _s745 = input.unsigned();
    var _f746 = ast.Span(_s745, input.unsigned());
    var _v747 = Array<ast.Attribute>();
    var _n748 = input.count();
    for (var _ in 0.._n748) {
        _v747.append(_a_Attribute_read(input));
    }
    var _f749 = _v747;
    var _f750 = input.flag();
    var _f751 = input.flag();
    var _o752 = Optional<ast.EnumBody>.Empty;
    if (input.unsigned() == 1) {
        _o752 = Optional<ast.EnumBody>.Value(_a_EnumBody_read(input));
    }
    var _f753 = _o752;
    var value = ast.StructDecl();
    value.name = _f722;
    value.name_span = _f724;
    value.generic_params = _f727;
    value.fields = _f730;
    value.properties = _f733;
    value.methods = _f736;
    value.constructors = _f739;
    value.destructor = _f741;
    value.destruct_span = _f744;
    value.span = _f746;
    value.attributes = _f749;
    value.is_exported = _f750;
    value.is_private = _f751;
    value.enumeration = _f753;
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
    for (var _item754 in value.cases) {
        _a_EnumCase_write(out, _item754);
    }
}

_a_EnumBody_read(input: RecordIn): ast.EnumBody {
    var _o755 = Optional<ast.TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o755 = Optional<ast.TypeName>.Value(_a_TypeName_read(input));
    }
    var _f756 = _o755;
    var _v757 = Array<ast.EnumCase>();
    var _n758 = input.count();
    for (var _ in 0.._n758) {
        _v757.append(_a_EnumCase_read(input));
    }
    var _f759 = _v757;
    var value = ast.EnumBody();
    value.representation = _f756;
    value.cases = _f759;
    return value;
}

_a_EnumCase_write(out: RecordOut, value: ast.EnumCase) {
    out.text(value.name);
    out.unsigned(value.name_span.start);
    out.unsigned(value.name_span.end);
    if (value.value.is_value()) {
        out.unsigned(1);
        _a_Expression_write(out, value.value.value());
    } else {
        out.unsigned(0);
    }
    if (value.payload.is_value()) {
        out.unsigned(1);
        out.unsigned(value.payload.value().count);
        for (var _item760 in value.payload.value()) {
            _a_VariableDecl_write(out, _item760);
        }
    } else {
        out.unsigned(0);
    }
    out.unsigned(value.attributes.count);
    for (var _item761 in value.attributes) {
        _a_Attribute_write(out, _item761);
    }
    out.unsigned(value.span.start);
    out.unsigned(value.span.end);
}

_a_EnumCase_read(input: RecordIn): ast.EnumCase {
    var _f762 = input.text();
    var _s763 = input.unsigned();
    var _f764 = ast.Span(_s763, input.unsigned());
    var _o765 = Optional<ast.Expression>.Empty;
    if (input.unsigned() == 1) {
        _o765 = Optional<ast.Expression>.Value(_a_Expression_read(input));
    }
    var _f766 = _o765;
    var _o767 = Optional<Array<ast.VariableDecl>>.Empty;
    if (input.unsigned() == 1) {
        var _v768 = Array<ast.VariableDecl>();
        var _n769 = input.count();
        for (var _ in 0.._n769) {
            _v768.append(_a_VariableDecl_read(input));
        }
        _o767 = Optional<Array<ast.VariableDecl>>.Value(_v768);
    }
    var _f770 = _o767;
    var _v771 = Array<ast.Attribute>();
    var _n772 = input.count();
    for (var _ in 0.._n772) {
        _v771.append(_a_Attribute_read(input));
    }
    var _f773 = _v771;
    var _s774 = input.unsigned();
    var _f775 = ast.Span(_s774, input.unsigned());
    var value = ast.EnumCase();
    value.name = _f762;
    value.name_span = _f764;
    value.value = _f766;
    value.payload = _f770;
    value.attributes = _f773;
    value.span = _f775;
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
        var _f776 = input.text();
        return ast.Literal.String(_f776);
    }
    if (tag == 1) {
        var _f777 = input.signed();
        return ast.Literal.Integer(_f777);
    }
    if (tag == 2) {
        var _f778 = input.number();
        return ast.Literal.Float(_f778);
    }
    if (tag == 3) {
        var _f779 = input.flag();
        return ast.Literal.Bool(_f779);
    }
    if (tag == 4) {
        var _f780 = input.unsigned() as u8;
        return ast.Literal.Char(_f780);
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
    for (var _item781 in value.items) {
        _m_Statement_write(out, _item781);
    }
    out.unsigned(value.attributes.count);
    for (var _item782 in value.attributes) {
        _a_Attribute_write(out, _item782);
    }
}

_m_Block_read(input: RecordIn): Block {
    var _f783 = input.text();
    var _v784 = Array<Statement>();
    var _n785 = input.count();
    for (var _ in 0.._n785) {
        _v784.append(_m_Statement_read(input));
    }
    var _f786 = _v784;
    var _v787 = Array<ast.Attribute>();
    var _n788 = input.count();
    for (var _ in 0.._n788) {
        _v787.append(_a_Attribute_read(input));
    }
    var _f789 = _v787;
    return Block(_f783, _f786, _f789);
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
        var _f1194 = _m_Expression_read(input);
        return Statement.Expression(_f1194);
    }
    if (tag == 1) {
        var _f1195 = _m_Block_read(input);
        return Statement.Block(_f1195);
    }
    if (tag == 2) {
        var _f1196 = _m_Declaration_read(input);
        return Statement.Declaration(_f1196);
    }
    if (tag == 3) {
        var _f1197 = _m_Branch_read(input);
        return Statement.Branch(_f1197);
    }
    if (tag == 4) {
        var _f1198 = _m_While_read(input);
        return Statement.While(_f1198);
    }
    if (tag == 5) {
        var _f1199 = _m_ReturnStatement_read(input);
        return Statement.Return(_f1199);
    }
    if (tag == 6) {
        var _f1200 = _m_LoopBreak_read(input);
        return Statement.LoopBreak(_f1200);
    }
    if (tag == 7) {
        var _f1201 = _m_StaticBlock_read(input);
        return Statement.Static(_f1201);
    }
    if (tag == 8) {
        var _f1202 = _m_StaticPass_read(input);
        return Statement.StaticPass(_f1202);
    }
    input.fail("Statement", tag);
    return _m_Statement_read(input);
}

_m_StaticPass_write(out: RecordOut, value: StaticPass) {
    out.loc(value.loc);
    out.flag(value.stop);
    out.unsigned(value.values.count);
    for (var _item790 in value.values) {
        var (_t791, _t792) = _item790;
        out.text(_t791);
        _m_StaticConstant_write(out, _t792);
    }
    if (value.header.is_value()) {
        out.unsigned(1);
        out.unsigned(value.header.value() as ulong);
    } else {
        out.unsigned(0);
    }
    out.unsigned(value.lines.count);
    for (var _item793 in value.lines) {
        var (_t794, _t795) = _item793;
        out.loc(_t794);
        out.unsigned(_t795 as ulong);
    }
}

_m_StaticPass_read(input: RecordIn): StaticPass {
    var _f796 = input.loc();
    var _f797 = input.flag();
    var _v798 = Array<(String, StaticConstant)>();
    var _n799 = input.count();
    for (var _ in 0.._n799) {
        var _t800 = input.text();
        var _t801 = _m_StaticConstant_read(input);
        _v798.append((_t800, _t801));
    }
    var _f802 = _v798;
    var _o803 = Optional<uint>.Empty;
    if (input.unsigned() == 1) {
        _o803 = Optional<uint>.Value(input.unsigned() as uint);
    }
    var _f804 = _o803;
    var _v805 = Array<(Loc, uint)>();
    var _n806 = input.count();
    for (var _ in 0.._n806) {
        var _t807 = input.loc();
        var _t808 = input.unsigned() as uint;
        _v805.append((_t807, _t808));
    }
    var _f809 = _v805;
    return StaticPass(_f796, _f797, _f802, _f804, _f809);
}

_m_RecordStaticConstant_write(out: RecordOut, value: RecordStaticConstant) {
    out.text(value.name);
    out.unsigned(value.fields.count);
    for (var _item1207 in value.fields) {
        var (_t1208, _t1209) = _item1207;
        out.text(_t1208);
        _m_StaticConstant_write(out, _t1209);
    }
}

_m_RecordStaticConstant_read(input: RecordIn): RecordStaticConstant {
    var _f1210 = input.text();
    var _v1211 = Array<(String, StaticConstant)>();
    var _n1212 = input.count();
    for (var _ in 0.._n1212) {
        var _t1213 = input.text();
        var _t1214 = _m_StaticConstant_read(input);
        _v1211.append((_t1213, _t1214));
    }
    var _f1215 = _v1211;
    return RecordStaticConstant(_f1210, _f1215);
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
        var _f1203 = input.signed();
        return StaticConstant.Int(_f1203);
    }
    if (tag == 1) {
        var _f1204 = input.number();
        return StaticConstant.Float(_f1204);
    }
    if (tag == 2) {
        var _f1205 = input.flag();
        return StaticConstant.Bool(_f1205);
    }
    if (tag == 3) {
        var _f1206 = input.text();
        return StaticConstant.String(_f1206);
    }
    if (tag == 4) {
        return StaticConstant.Record(_m_RecordStaticConstant_read(input));
    }
    input.fail("StaticConstant", tag);
    return _m_StaticConstant_read(input);
}

_m_StaticBlock_write(out: RecordOut, value: StaticBlock) {
    out.unsigned(value.captures.count);
    for (var _item810 in value.captures) {
        out.text(_item810);
    }
    out.unsigned(value.items.count);
    for (var _item811 in value.items) {
        _m_StaticItem_write(out, _item811);
    }
    out.unsigned(value.type_map.count);
    for (var _item812 in value.type_map) {
        var (_t813, _t814) = _item812;
        out.text(_t813);
        _m_TypeName_write(out, _t814);
    }
    out.loc(value.loc);
    out.unsigned(value.span.start);
    out.unsigned(value.span.end);
}

_m_StaticBlock_read(input: RecordIn): StaticBlock {
    var _v815 = Array<String>();
    var _n816 = input.count();
    for (var _ in 0.._n816) {
        _v815.append(input.text());
    }
    var _f817 = _v815;
    var _v818 = Array<StaticItem>();
    var _n819 = input.count();
    for (var _ in 0.._n819) {
        _v818.append(_m_StaticItem_read(input));
    }
    var _f820 = _v818;
    var _v821 = Array<(String, TypeName)>();
    var _n822 = input.count();
    for (var _ in 0.._n822) {
        var _t823 = input.text();
        var _t824 = _m_TypeName_read(input);
        _v821.append((_t823, _t824));
    }
    var _f825 = _v821;
    var _f826 = input.loc();
    var _s827 = input.unsigned();
    var _f828 = ast.Span(_s827, input.unsigned());
    return StaticBlock(_f817, _f820, _f825, _f826, _f828);
}

_m_TypeName_write(out: RecordOut, value: TypeName) {
    out.text(value.name);
    out.unsigned(value.sub_types.count);
    for (var _item829 in value.sub_types) {
        _m_TypeName_write(out, _item829);
    }
    _m_TypeFlags_write(out, value.flags);
    out.unsigned(value.labels.count);
    for (var _item830 in value.labels) {
        out.text(_item830);
    }
}

_m_TypeName_read(input: RecordIn): TypeName {
    var _f831 = input.text();
    var _v832 = Array<TypeName>();
    var _n833 = input.count();
    for (var _ in 0.._n833) {
        _v832.append(_m_TypeName_read(input));
    }
    var _f834 = _v832;
    var _f835 = _m_TypeFlags_read(input);
    var _v836 = Array<String>();
    var _n837 = input.count();
    for (var _ in 0.._n837) {
        _v836.append(input.text());
    }
    var _f838 = _v836;
    return TypeName(_f831, _f834, _f835, _f838);
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
    for (var _item1216 in value.body) {
        _m_StaticItem_write(out, _item1216);
    }
    out.loc(value.loc);
}

_m_ForStaticItem_read(input: RecordIn): ForStaticItem {
    var _f1217 = input.text();
    var _f1218 = _a_Expression_read(input);
    var _v1219 = Array<StaticItem>();
    var _n1220 = input.count();
    for (var _ in 0.._n1220) {
        _v1219.append(_m_StaticItem_read(input));
    }
    var _f1221 = _v1219;
    var _f1222 = input.loc();
    return ForStaticItem(_f1218, _f1217, _f1221, _f1222);
}

_m_WhileStaticItem_write(out: RecordOut, value: WhileStaticItem) {
    _a_Expression_write(out, value.condition);
    out.unsigned(value.body.count);
    for (var _item1223 in value.body) {
        _m_StaticItem_write(out, _item1223);
    }
    out.loc(value.loc);
}

_m_WhileStaticItem_read(input: RecordIn): WhileStaticItem {
    var _f1224 = _a_Expression_read(input);
    var _v1225 = Array<StaticItem>();
    var _n1226 = input.count();
    for (var _ in 0.._n1226) {
        _v1225.append(_m_StaticItem_read(input));
    }
    var _f1227 = _v1225;
    var _f1228 = input.loc();
    return WhileStaticItem(_f1224, _f1227, _f1228);
}

_m_JumpStaticItem_write(out: RecordOut, value: JumpStaticItem) {
    _m_LoopBreakKind_write(out, value.kind);
    out.loc(value.loc);
}

_m_JumpStaticItem_read(input: RecordIn): JumpStaticItem {
    var _f1229 = _m_LoopBreakKind_read(input);
    var _f1230 = input.loc();
    return JumpStaticItem(_f1229, _f1230);
}

_m_IfStaticItem_write(out: RecordOut, value: IfStaticItem) {
    _a_Expression_write(out, value.condition);
    out.unsigned(value.then_items.count);
    for (var _item1231 in value.then_items) {
        _m_StaticItem_write(out, _item1231);
    }
    out.unsigned(value.else_items.count);
    for (var _item1232 in value.else_items) {
        _m_StaticItem_write(out, _item1232);
    }
    out.loc(value.loc);
}

_m_IfStaticItem_read(input: RecordIn): IfStaticItem {
    var _f1233 = _a_Expression_read(input);
    var _v1234 = Array<StaticItem>();
    var _n1235 = input.count();
    for (var _ in 0.._n1235) {
        _v1234.append(_m_StaticItem_read(input));
    }
    var _f1236 = _v1234;
    var _v1237 = Array<StaticItem>();
    var _n1238 = input.count();
    for (var _ in 0.._n1238) {
        _v1237.append(_m_StaticItem_read(input));
    }
    var _f1239 = _v1237;
    var _f1240 = input.loc();
    return IfStaticItem(_f1233, _f1236, _f1239, _f1240);
}

_m_EmitIfStaticItem_write(out: RecordOut, value: EmitIfStaticItem) {
    _m_Expression_write(out, value.condition);
    out.unsigned(value.then_items.count);
    for (var _item1241 in value.then_items) {
        _m_StaticItem_write(out, _item1241);
    }
    out.unsigned(value.else_items.count);
    for (var _item1242 in value.else_items) {
        _m_StaticItem_write(out, _item1242);
    }
    out.unsigned(value.span.start);
    out.unsigned(value.span.end);
}

_m_EmitIfStaticItem_read(input: RecordIn): EmitIfStaticItem {
    var _f1243 = _m_Expression_read(input);
    var _v1244 = Array<StaticItem>();
    var _n1245 = input.count();
    for (var _ in 0.._n1245) {
        _v1244.append(_m_StaticItem_read(input));
    }
    var _f1246 = _v1244;
    var _v1247 = Array<StaticItem>();
    var _n1248 = input.count();
    for (var _ in 0.._n1248) {
        _v1247.append(_m_StaticItem_read(input));
    }
    var _f1249 = _v1247;
    var _s1250 = input.unsigned();
    var _f1251 = ast.Span(_s1250, input.unsigned());
    return EmitIfStaticItem(_f1243, _f1246, _f1249, _f1251);
}

_m_VarStaticItem_write(out: RecordOut, value: VarStaticItem) {
    out.text(value.name);
    _a_Expression_write(out, value.value);
    out.loc(value.loc);
}

_m_VarStaticItem_read(input: RecordIn): VarStaticItem {
    var _f1256 = input.text();
    var _f1257 = _a_Expression_read(input);
    var _f1258 = input.loc();
    return VarStaticItem(_f1257, _f1256, _f1258);
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
            for (var _item1252 in v) {
                _m_StaticItem_write(out, _item1252);
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
            out.unsigned(v1.start);
            out.unsigned(v1.end);
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
        var _v1253 = Array<StaticItem>();
        var _n1254 = input.count();
        for (var _ in 0.._n1254) {
            _v1253.append(_m_StaticItem_read(input));
        }
        var _f1255 = _v1253;
        return StaticItem.Block(_f1255);
    }
    if (tag == 6) {
        return StaticItem.Var(_m_VarStaticItem_read(input));
    }
    if (tag == 7) {
        var _f1259 = _a_Expression_read(input);
        return StaticItem.Evaluate(_f1259);
    }
    if (tag == 8) {
        var _f1260 = _m_Statement_read(input);
        var _s1261 = input.unsigned();
        var _f1262 = ast.Span(_s1261, input.unsigned());
        return StaticItem.Emit(_f1260, _f1262);
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
    var _f1263 = input.text();
    var _f1264 = _m_TypeName_read(input);
    var _f1265 = input.loc();
    return SymbolRefExpression(_f1263, _f1264, _f1265);
}

_m_MemberRefExpression_write(out: RecordOut, value: MemberRefExpression) {
    _m_Expression_write(out, value.lhs);
    out.text(value.name);
    out.loc(value.loc);
}

_m_MemberRefExpression_read(input: RecordIn): MemberRefExpression {
    var _f1266 = _m_Expression_read(input);
    var _f1267 = input.text();
    var _f1268 = input.loc();
    return MemberRefExpression(_f1266, _f1267, _f1268);
}

_m_StringLiteralExpression_write(out: RecordOut, value: StringLiteralExpression) {
    out.text(value.value);
    out.flag(value.is_raw);
    out.loc(value.loc);
}

_m_StringLiteralExpression_read(input: RecordIn): StringLiteralExpression {
    var _f1272 = input.text();
    var _f1273 = input.flag();
    var _f1274 = input.loc();
    return StringLiteralExpression(_f1272, _f1273, _f1274);
}

_m_BinaryExpression_write(out: RecordOut, value: BinaryExpression) {
    _m_BinaryOp_write(out, value.op);
    _m_Expression_write(out, value.lhs);
    _m_Expression_write(out, value.rhs);
    out.loc(value.loc);
}

_m_BinaryExpression_read(input: RecordIn): BinaryExpression {
    var _f1275 = _m_BinaryOp_read(input);
    var _f1276 = _m_Expression_read(input);
    var _f1277 = _m_Expression_read(input);
    var _f1278 = input.loc();
    return BinaryExpression(_f1276, _f1277, _f1275, _f1278);
}

_m_UnaryExpression_write(out: RecordOut, value: UnaryExpression) {
    _m_UnaryOp_write(out, value.op);
    _m_Expression_write(out, value.operand);
    out.loc(value.loc);
}

_m_UnaryExpression_read(input: RecordIn): UnaryExpression {
    var _f1279 = _m_UnaryOp_read(input);
    var _f1280 = _m_Expression_read(input);
    var _f1281 = input.loc();
    return UnaryExpression(_f1280, _f1279, _f1281);
}

_m_CastExpression_write(out: RecordOut, value: CastExpression) {
    _m_Expression_write(out, value.expr);
    _m_TypeName_write(out, value.ty);
    out.loc(value.loc);
    _m_CastKind_write(out, value.kind);
}

_m_CastExpression_read(input: RecordIn): CastExpression {
    var _f1282 = _m_Expression_read(input);
    var _f1283 = _m_TypeName_read(input);
    var _f1284 = input.loc();
    var _f1285 = _m_CastKind_read(input);
    return CastExpression(_f1282, _f1283, _f1284, _f1285);
}

_m_TernaryExpression_write(out: RecordOut, value: TernaryExpression) {
    _m_Expression_write(out, value.condition);
    _m_Expression_write(out, value.true_expr);
    _m_Expression_write(out, value.false_expr);
}

_m_TernaryExpression_read(input: RecordIn): TernaryExpression {
    var _f1286 = _m_Expression_read(input);
    var _f1287 = _m_Expression_read(input);
    var _f1288 = _m_Expression_read(input);
    return TernaryExpression(_f1286, _f1287, _f1288);
}

_m_IndexExpression_write(out: RecordOut, value: IndexExpression) {
    _m_Expression_write(out, value.lhs);
    _m_Expression_write(out, value.rhs);
    out.loc(value.loc);
}

_m_IndexExpression_read(input: RecordIn): IndexExpression {
    var _f1289 = _m_Expression_read(input);
    var _f1290 = _m_Expression_read(input);
    var _f1291 = input.loc();
    return IndexExpression(_f1289, _f1290, _f1291);
}

_m_ArrayIndexExpression_write(out: RecordOut, value: ArrayIndexExpression) {
    _m_TypeName_write(out, value.ty);
    _m_Expression_write(out, value.lhs);
    _m_Expression_write(out, value.rhs);
    out.loc(value.loc);
}

_m_ArrayIndexExpression_read(input: RecordIn): ArrayIndexExpression {
    var _f1292 = _m_TypeName_read(input);
    var _f1293 = _m_Expression_read(input);
    var _f1294 = _m_Expression_read(input);
    var _f1295 = input.loc();
    return ArrayIndexExpression(_f1293, _f1294, _f1292, _f1295);
}

_m_SimdExpression_write(out: RecordOut, value: SimdExpression) {
    _m_SimdOp_write(out, value.op);
    _m_TypeName_write(out, value.ty);
    out.unsigned(value.args.count);
    for (var _item1319 in value.args) {
        _m_Expression_write(out, _item1319);
    }
    out.loc(value.loc);
}

_m_SimdExpression_read(input: RecordIn): SimdExpression {
    var _f1320 = _m_SimdOp_read(input);
    var _f1321 = _m_TypeName_read(input);
    var _v1322 = Array<Expression>();
    var _n1323 = input.count();
    for (var _ in 0.._n1323) {
        _v1322.append(_m_Expression_read(input));
    }
    var _f1324 = _v1322;
    var _f1325 = input.loc();
    return SimdExpression(_f1320, _f1321, _f1324, _f1325);
}

_m_CountStepExpression_write(out: RecordOut, value: CountStepExpression) {
    _m_CountField_write(out, value.field);
    out.flag(value.increment);
    out.flag(value.atomic);
}

_m_CountStepExpression_read(input: RecordIn): CountStepExpression {
    var _f1329 = _m_CountField_read(input);
    var _f1330 = input.flag();
    var _f1331 = input.flag();
    return CountStepExpression(_f1329, _f1330, _f1331);
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
    var _o1332 = Optional<TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o1332 = Optional<TypeName>.Value(_m_TypeName_read(input));
    }
    var _f1333 = _o1332;
    var _f1334 = input.text();
    var _f1335 = input.loc();
    return FunctionPointerExpression(_f1333, _f1334, _f1335);
}

_m_FunctionCallExpression_write(out: RecordOut, value: FunctionCallExpression) {
    out.text(value.function);
    out.unsigned(value.args.count);
    for (var _item1336 in value.args) {
        _m_Expression_write(out, _item1336);
    }
    out.loc(value.loc);
}

_m_FunctionCallExpression_read(input: RecordIn): FunctionCallExpression {
    var _f1337 = input.text();
    var _v1338 = Array<Expression>();
    var _n1339 = input.count();
    for (var _ in 0.._n1339) {
        _v1338.append(_m_Expression_read(input));
    }
    var _f1340 = _v1338;
    var _f1341 = input.loc();
    return FunctionCallExpression(_f1337, _f1340, _f1341);
}

_m_NamedArgumentExpression_write(out: RecordOut, value: NamedArgumentExpression) {
    out.text(value.name);
    _m_Expression_write(out, value.value);
    out.loc(value.loc);
}

_m_NamedArgumentExpression_read(input: RecordIn): NamedArgumentExpression {
    var _f1342 = input.text();
    var _f1343 = _m_Expression_read(input);
    var _f1344 = input.loc();
    return NamedArgumentExpression(_f1343, _f1342, _f1344);
}

_m_DefaultArgumentExpression_write(out: RecordOut, value: DefaultArgumentExpression) {
    _m_TypeName_write(out, value.ty);
}

_m_DefaultArgumentExpression_read(input: RecordIn): DefaultArgumentExpression {
    var _f1345 = _m_TypeName_read(input);
    return DefaultArgumentExpression(_f1345);
}

_m_MethodCallExpression_write(out: RecordOut, value: MethodCallExpression) {
    _m_Expression_write(out, value.this_value);
    out.text(value.method);
    out.unsigned(value.args.count);
    for (var _item1346 in value.args) {
        _m_Expression_write(out, _item1346);
    }
    out.loc(value.loc);
}

_m_MethodCallExpression_read(input: RecordIn): MethodCallExpression {
    var _f1347 = _m_Expression_read(input);
    var _f1348 = input.text();
    var _v1349 = Array<Expression>();
    var _n1350 = input.count();
    for (var _ in 0.._n1350) {
        _v1349.append(_m_Expression_read(input));
    }
    var _f1351 = _v1349;
    var _f1352 = input.loc();
    return MethodCallExpression(_f1347, _f1348, _f1351, _f1352);
}

_m_FunctionRefExpression_write(out: RecordOut, value: FunctionRefExpression) {
    out.text(value.function);
    _m_TypeName_write(out, value.ty);
    out.loc(value.loc);
}

_m_FunctionRefExpression_read(input: RecordIn): FunctionRefExpression {
    var _f1353 = input.text();
    var _f1354 = _m_TypeName_read(input);
    var _f1355 = input.loc();
    return FunctionRefExpression(_f1353, _f1354, _f1355);
}

_m_InvokeExpression_write(out: RecordOut, value: InvokeExpression) {
    _m_Expression_write(out, value.callee);
    out.unsigned(value.args.count);
    for (var _item1356 in value.args) {
        _m_Expression_write(out, _item1356);
    }
}

_m_InvokeExpression_read(input: RecordIn): InvokeExpression {
    var _f1357 = _m_Expression_read(input);
    var _v1358 = Array<Expression>();
    var _n1359 = input.count();
    for (var _ in 0.._n1359) {
        _v1358.append(_m_Expression_read(input));
    }
    var _f1360 = _v1358;
    return InvokeExpression(_f1357, _f1360);
}

_m_MakeClosureExpression_write(out: RecordOut, value: MakeClosureExpression) {
    _m_Expression_write(out, value.value);
    out.text(value.closure);
    _m_TypeName_write(out, value.ty);
    out.loc(value.loc);
}

_m_MakeClosureExpression_read(input: RecordIn): MakeClosureExpression {
    var _f1362 = _m_Expression_read(input);
    var _f1363 = input.text();
    var _f1364 = _m_TypeName_read(input);
    var _f1365 = input.loc();
    return MakeClosureExpression(_f1362, _f1363, _f1364, _f1365);
}

_m_CallPointerExpression_write(out: RecordOut, value: CallPointerExpression) {
    _m_Expression_write(out, value.pointer);
    out.unsigned(value.args.count);
    for (var _item1367 in value.args) {
        _m_Expression_write(out, _item1367);
    }
}

_m_CallPointerExpression_read(input: RecordIn): CallPointerExpression {
    var _f1368 = _m_Expression_read(input);
    var _v1369 = Array<Expression>();
    var _n1370 = input.count();
    for (var _ in 0.._n1370) {
        _v1369.append(_m_Expression_read(input));
    }
    var _f1371 = _v1369;
    return CallPointerExpression(_f1368, _f1371);
}

_m_MoveExpression_write(out: RecordOut, value: MoveExpression) {
    _m_Expression_write(out, value.value);
    out.loc(value.loc);
}

_m_MoveExpression_read(input: RecordIn): MoveExpression {
    var _f1374 = _m_Expression_read(input);
    var _f1375 = input.loc();
    return MoveExpression(_f1374, _f1375);
}

_m_DestructureExpression_write(out: RecordOut, value: DestructureExpression) {
    _m_Expression_write(out, value.value);
    out.unsigned(value.count);
    out.loc(value.loc);
}

_m_DestructureExpression_read(input: RecordIn): DestructureExpression {
    var _f1376 = _m_Expression_read(input);
    var _f1377 = input.unsigned();
    var _f1378 = input.loc();
    return DestructureExpression(_f1376, _f1377, _f1378);
}

_m_StaticCaseExpression_write(out: RecordOut, value: StaticCaseExpression) {
    _m_TypeName_write(out, value.ty);
    out.signed(value.tag as long);
}

_m_StaticCaseExpression_read(input: RecordIn): StaticCaseExpression {
    var _f1381 = _m_TypeName_read(input);
    var _f1382 = input.signed();
    return StaticCaseExpression(_f1381, _f1382);
}

_m_StaticStringExpression_write(out: RecordOut, value: StaticStringExpression) {
    out.text(value.value);
    out.loc(value.loc);
}

_m_StaticStringExpression_read(input: RecordIn): StaticStringExpression {
    var _f1383 = input.text();
    var _f1384 = input.loc();
    return StaticStringExpression(_f1383, _f1384);
}

_m_SubjectExpression_write(out: RecordOut, value: SubjectExpression) {
    out.unsigned(value.id);
    _m_TypeName_write(out, value.ty);
    out.loc(value.loc);
}

_m_SubjectExpression_read(input: RecordIn): SubjectExpression {
    var _f1386 = input.unsigned();
    var _f1387 = _m_TypeName_read(input);
    var _f1388 = input.loc();
    return SubjectExpression(_f1386, _f1387, _f1388);
}

_m_ToTraitExpression_write(out: RecordOut, value: ToTraitExpression) {
    _m_Expression_write(out, value.value);
    _m_TypeName_write(out, value.from);
    _m_TypeName_write(out, value.to);
    out.loc(value.loc);
}

_m_ToTraitExpression_read(input: RecordIn): ToTraitExpression {
    var _f1389 = _m_Expression_read(input);
    var _f1390 = _m_TypeName_read(input);
    var _f1391 = _m_TypeName_read(input);
    var _f1392 = input.loc();
    return ToTraitExpression(_f1389, _f1390, _f1391, _f1392);
}

_m_FromTraitExpression_write(out: RecordOut, value: FromTraitExpression) {
    _m_Expression_write(out, value.value);
    _m_TypeName_write(out, value.from);
    _m_TypeName_write(out, value.to);
    out.unsigned(value.candidates.count);
    for (var _item1393 in value.candidates) {
        _m_TypeName_write(out, _item1393);
    }
    out.flag(value.test);
    out.loc(value.loc);
}

_m_FromTraitExpression_read(input: RecordIn): FromTraitExpression {
    var _f1394 = _m_Expression_read(input);
    var _f1395 = _m_TypeName_read(input);
    var _f1396 = _m_TypeName_read(input);
    var _v1397 = Array<TypeName>();
    var _n1398 = input.count();
    for (var _ in 0.._n1398) {
        _v1397.append(_m_TypeName_read(input));
    }
    var _f1399 = _v1397;
    var _f1400 = input.flag();
    var _f1401 = input.loc();
    return FromTraitExpression(_f1394, _f1395, _f1396, _f1399, _f1400, _f1401);
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
        var _f1269 = input.flag();
        return Expression.BoolLiteral(_f1269);
    }
    if (tag == 4) {
        var _f1270 = input.signed();
        return Expression.IntLiteral(_f1270);
    }
    if (tag == 5) {
        var _f1271 = input.number();
        return Expression.FloatLiteral(_f1271);
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
        var _f1296 = _m_TypeName_read(input);
        return Expression.SizeOf(_f1296);
    }
    if (tag == 15) {
        var _f1297 = _m_TypeName_read(input);
        return Expression.IsPod(_f1297);
    }
    if (tag == 16) {
        var _f1298 = _m_TypeName_read(input);
        return Expression.Default(_f1298);
    }
    if (tag == 17) {
        var _f1299 = _m_TypeName_read(input);
        return Expression.Allocate(_f1299);
    }
    if (tag == 18) {
        var _f1300 = _m_TypeName_read(input);
        var _f1301 = _m_Expression_read(input);
        return Expression.RefCount(_f1300, _f1301);
    }
    if (tag == 19) {
        var _f1302 = _m_TypeName_read(input);
        var _f1303 = _m_Expression_read(input);
        return Expression.Address(_f1302, _f1303);
    }
    if (tag == 20) {
        var _f1304 = _m_TypeName_read(input);
        var _f1305 = _m_Expression_read(input);
        return Expression.AtomicLoad(_f1304, _f1305);
    }
    if (tag == 21) {
        var _f1306 = _m_TypeName_read(input);
        var _f1307 = _m_Expression_read(input);
        var _f1308 = _m_Expression_read(input);
        return Expression.AtomicStore(_f1306, _f1307, _f1308);
    }
    if (tag == 22) {
        var _f1309 = _m_Expression_read(input);
        var _f1310 = _m_Expression_read(input);
        return Expression.ConstructAt(_f1309, _f1310);
    }
    if (tag == 23) {
        var _f1311 = _m_TypeName_read(input);
        var _f1312 = _m_Expression_read(input);
        var _f1313 = _m_Expression_read(input);
        var _f1314 = _m_Expression_read(input);
        return Expression.AtomicCmpXchg(_f1311, _f1312, _f1313, _f1314);
    }
    if (tag == 24) {
        var _f1315 = _m_AtomicFetchOp_read(input);
        var _f1316 = _m_TypeName_read(input);
        var _f1317 = _m_Expression_read(input);
        var _f1318 = _m_Expression_read(input);
        return Expression.AtomicFetch(_f1315, _f1316, _f1317, _f1318);
    }
    if (tag == 25) {
        return Expression.Simd(_m_SimdExpression_read(input));
    }
    if (tag == 26) {
        var _f1326 = _m_WeakOp_read(input);
        var _f1327 = _m_TypeName_read(input);
        var _f1328 = _m_Expression_read(input);
        return Expression.Weak(_f1326, _f1327, _f1328);
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
        var _f1361 = _m_ClosureLiteral_read(input);
        return Expression.ClosureLiteral(_f1361);
    }
    if (tag == 36) {
        return Expression.MakeClosure(_m_MakeClosureExpression_read(input));
    }
    if (tag == 37) {
        var _f1366 = input.text();
        return Expression.MethodAddress(_f1366);
    }
    if (tag == 38) {
        return Expression.CallPointer(_m_CallPointerExpression_read(input));
    }
    if (tag == 39) {
        var _f1372 = _m_Expression_read(input);
        return Expression.ForIterator(_f1372);
    }
    if (tag == 40) {
        var _f1373 = _m_Expression_read(input);
        return Expression.WithEntered(_f1373);
    }
    if (tag == 41) {
        return Expression.Move(_m_MoveExpression_read(input));
    }
    if (tag == 42) {
        return Expression.Destructure(_m_DestructureExpression_read(input));
    }
    if (tag == 43) {
        var _f1379 = _m_MatchArmTest_read(input);
        return Expression.MatchArm(_f1379);
    }
    if (tag == 44) {
        var _f1380 = _m_CaseValue_read(input);
        return Expression.CaseValue(_f1380);
    }
    if (tag == 45) {
        return Expression.StaticCase(_m_StaticCaseExpression_read(input));
    }
    if (tag == 46) {
        return Expression.StaticString(_m_StaticStringExpression_read(input));
    }
    if (tag == 47) {
        var _f1385 = _m_WithSubject_read(input);
        return Expression.WithSubject(_f1385);
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
        var _f1402 = _m_StaticValue_read(input);
        return Expression.StaticValue(_f1402);
    }
    if (tag == 53) {
        var _f1403 = _m_StaticMember_read(input);
        return Expression.StaticMember(_f1403);
    }
    input.fail("Expression", tag);
    return _m_Expression_read(input);
}

_m_StaticMember_write(out: RecordOut, value: StaticMember) {
    _a_Expression_write(out, value.member);
    out.text(value.method);
    out.unsigned(value.args.count);
    for (var _item839 in value.args) {
        _m_Expression_write(out, _item839);
    }
    out.loc(value.loc);
    out.unsigned(value.span.start);
    out.unsigned(value.span.end);
    out.unsigned(value.argument_spans.count);
    for (var _item840 in value.argument_spans) {
        out.unsigned(_item840.start);
        out.unsigned(_item840.end);
    }
}

_m_StaticMember_read(input: RecordIn): StaticMember {
    var _f841 = _a_Expression_read(input);
    var _f842 = input.text();
    var _v843 = Array<Expression>();
    var _n844 = input.count();
    for (var _ in 0.._n844) {
        _v843.append(_m_Expression_read(input));
    }
    var _f845 = _v843;
    var _f846 = input.loc();
    var _s847 = input.unsigned();
    var _f848 = ast.Span(_s847, input.unsigned());
    var _v849 = Array<ast.Span>();
    var _n850 = input.count();
    for (var _ in 0.._n850) {
        var _s851 = input.unsigned();
        _v849.append(ast.Span(_s851, input.unsigned()));
    }
    var _f852 = _v849;
    return StaticMember(_f841, _f842, _f845, _f846, _f848, _f852);
}

_m_StaticValue_write(out: RecordOut, value: StaticValue) {
    _a_Expression_write(out, value.expr);
    out.loc(value.loc);
}

_m_StaticValue_read(input: RecordIn): StaticValue {
    var _f853 = _a_Expression_read(input);
    var _f854 = input.loc();
    return StaticValue(_f853, _f854);
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
    var _f855 = input.unsigned();
    var _f856 = _m_Expression_read(input);
    var _f857 = _m_Expression_read(input);
    var _o858 = Optional<String>.Empty;
    if (input.unsigned() == 1) {
        _o858 = Optional<String>.Value(input.text());
    }
    var _f859 = _o858;
    var _f860 = input.loc();
    return WithSubject(_f856, _f857, _f855, _f859, _f860);
}

_m_CaseValue_write(out: RecordOut, value: CaseValue) {
    _m_Expression_write(out, value.subject);
    out.text(value.name);
    out.unsigned(value.choices.count);
    for (var _item861 in value.choices) {
        _m_CaseChoice_write(out, _item861);
    }
    out.loc(value.loc);
}

_m_CaseValue_read(input: RecordIn): CaseValue {
    var _f862 = _m_Expression_read(input);
    var _f863 = input.text();
    var _v864 = Array<CaseChoice>();
    var _n865 = input.count();
    for (var _ in 0.._n865) {
        _v864.append(_m_CaseChoice_read(input));
    }
    var _f866 = _v864;
    var _f867 = input.loc();
    return CaseValue(_f862, _f863, _f866, _f867);
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
    for (var _item868 in value.bindings) {
        out.loc(_item868);
    }
    out.loc(value.loc);
}

_m_CaseChoice_read(input: RecordIn): CaseChoice {
    var _f869 = input.text();
    var _f870 = input.loc();
    var _o871 = Optional<TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o871 = Optional<TypeName>.Value(_m_TypeName_read(input));
    }
    var _f872 = _o871;
    var _f873 = input.unsigned();
    var _v874 = Array<Loc>();
    var _n875 = input.count();
    for (var _ in 0.._n875) {
        _v874.append(input.loc());
    }
    var _f876 = _v874;
    var _f877 = input.loc();
    return CaseChoice(_f869, _f870, _f872, _f873, _f876, _f877);
}

_m_MatchArmTest_write(out: RecordOut, value: MatchArmTest) {
    _m_Expression_write(out, value.subject);
    out.unsigned(value.patterns.count);
    for (var _item878 in value.patterns) {
        _m_CasePattern_write(out, _item878);
    }
    _m_MatchSite_write(out, value.site);
    out.unsigned(value.element_names.count);
    for (var _item879 in value.element_names) {
        _m_ElementName_write(out, _item879);
    }
    out.flag(value.guarded);
}

_m_MatchArmTest_read(input: RecordIn): MatchArmTest {
    var _f880 = _m_Expression_read(input);
    var _v881 = Array<CasePattern>();
    var _n882 = input.count();
    for (var _ in 0.._n882) {
        _v881.append(_m_CasePattern_read(input));
    }
    var _f883 = _v881;
    var _f884 = _m_MatchSite_read(input);
    var _v885 = Array<ElementName>();
    var _n886 = input.count();
    for (var _ in 0.._n886) {
        _v885.append(_m_ElementName_read(input));
    }
    var _f887 = _v885;
    var _f888 = input.flag();
    return MatchArmTest(_f880, _f883, _f884, _f887, _f888);
}

_m_ElementName_write(out: RecordOut, value: ElementName) {
    out.text(value.name);
    out.loc(value.loc);
    out.flag(value.declared);
    if (value.missing.is_value()) {
        out.unsigned(1);
        var (_t889, _t890) = value.missing.value();
        out.text(_t889);
        out.loc(_t890);
    } else {
        out.unsigned(0);
    }
}

_m_ElementName_read(input: RecordIn): ElementName {
    var _f891 = input.text();
    var _f892 = input.loc();
    var _f893 = input.flag();
    var _o894 = Optional<(String, Loc)>.Empty;
    if (input.unsigned() == 1) {
        var _t895 = input.text();
        var _t896 = input.loc();
        _o894 = Optional<(String, Loc)>.Value((_t895, _t896));
    }
    var _f897 = _o894;
    return ElementName(_f891, _f892, _f893, _f897);
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
    var _f898 = input.unsigned();
    var _f899 = input.loc();
    var _o900 = Optional<Loc>.Empty;
    if (input.unsigned() == 1) {
        _o900 = Optional<Loc>.Value(input.loc());
    }
    var _f901 = _o900;
    var _f902 = input.flag();
    var _f903 = input.flag();
    return MatchSite(_f898, _f899, _f901, _f902, _f903);
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
        for (var _item904 in value.bindings.value()) {
            _m_CasePattern_write(out, _item904);
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
        for (var _item905 in value.elements.value()) {
            _m_CasePattern_write(out, _item905);
        }
    } else {
        out.unsigned(0);
    }
    out.flag(value.range);
    out.flag(value.constant);
    if (value.values.is_value()) {
        out.unsigned(1);
        var (_t906, _t907) = value.values.value();
        out.signed(_t906 as long);
        out.signed(_t907 as long);
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
    var _o908 = Optional<TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o908 = Optional<TypeName>.Value(_m_TypeName_read(input));
    }
    var _f909 = _o908;
    var _f910 = input.text();
    var _f911 = input.loc();
    var _o912 = Optional<Array<CasePattern>>.Empty;
    if (input.unsigned() == 1) {
        var _v913 = Array<CasePattern>();
        var _n914 = input.count();
        for (var _ in 0.._n914) {
            _v913.append(_m_CasePattern_read(input));
        }
        _o912 = Optional<Array<CasePattern>>.Value(_v913);
    }
    var _f915 = _o912;
    var _o916 = Optional<Expression>.Empty;
    if (input.unsigned() == 1) {
        _o916 = Optional<Expression>.Value(_m_Expression_read(input));
    }
    var _f917 = _o916;
    var _o918 = Optional<Array<CasePattern>>.Empty;
    if (input.unsigned() == 1) {
        var _v919 = Array<CasePattern>();
        var _n920 = input.count();
        for (var _ in 0.._n920) {
            _v919.append(_m_CasePattern_read(input));
        }
        _o918 = Optional<Array<CasePattern>>.Value(_v919);
    }
    var _f921 = _o918;
    var _f922 = input.flag();
    var _f923 = input.flag();
    var _o924 = Optional<(long, long)>.Empty;
    if (input.unsigned() == 1) {
        var _t925 = input.signed();
        var _t926 = input.signed();
        _o924 = Optional<(long, long)>.Value((_t925, _t926));
    }
    var _f927 = _o924;
    var _o928 = Optional<TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o928 = Optional<TypeName>.Value(_m_TypeName_read(input));
    }
    var _f929 = _o928;
    return CasePattern(_f909, _f910, _f911, _f915, _f917, _f921, _f922, _f923, _f927, _f929);
}

_m_ClosureLiteral_write(out: RecordOut, value: ClosureLiteral) {
    out.unsigned(value.parameters.count);
    for (var _item930 in value.parameters) {
        _m_VariableDef_write(out, _item930);
    }
    _m_TypeName_write(out, value.ty);
    _m_Block_write(out, value.body);
    out.flag(value.expression_body);
    out.loc(value.loc);
}

_m_ClosureLiteral_read(input: RecordIn): ClosureLiteral {
    var _v931 = Array<VariableDef>();
    var _n932 = input.count();
    for (var _ in 0.._n932) {
        _v931.append(_m_VariableDef_read(input));
    }
    var _f933 = _v931;
    var _f934 = _m_TypeName_read(input);
    var _f935 = _m_Block_read(input);
    var _f936 = input.flag();
    var _f937 = input.loc();
    return ClosureLiteral(_f933, _f934, _f935, _f936, _f937);
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
    for (var _item938 in value.attributes) {
        _a_Attribute_write(out, _item938);
    }
    out.loc(value.loc);
    out.loc(value.type_loc);
    out.flag(value.is_const);
}

_m_VariableDef_read(input: RecordIn): VariableDef {
    var _f939 = input.text();
    var _f940 = _m_TypeName_read(input);
    var _o941 = Optional<Expression>.Empty;
    if (input.unsigned() == 1) {
        _o941 = Optional<Expression>.Value(_m_Expression_read(input));
    }
    var _f942 = _o941;
    var _f943 = input.flag();
    var _f944 = _m_Kind_read(input);
    var _v945 = Array<ast.Attribute>();
    var _n946 = input.count();
    for (var _ in 0.._n946) {
        _v945.append(_a_Attribute_read(input));
    }
    var _f947 = _v945;
    var _f948 = input.loc();
    var _f949 = input.loc();
    var _f950 = input.flag();
    return VariableDef(_f939, _f940, _f942, _f943, _f944, _f947, _f948, _f949, _f950);
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
    var _f951 = _m_LoopBreakKind_read(input);
    return LoopBreak(_f951);
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
    var _o952 = Optional<Expression>.Empty;
    if (input.unsigned() == 1) {
        _o952 = Optional<Expression>.Value(_m_Expression_read(input));
    }
    var _f953 = _o952;
    var _f954 = input.loc();
    return ReturnStatement(_f953, _f954);
}

_m_While_write(out: RecordOut, value: While) {
    _m_Expression_write(out, value.condition);
    _m_Block_write(out, value.block);
}

_m_While_read(input: RecordIn): While {
    var _f955 = _m_Expression_read(input);
    var _f956 = _m_Block_read(input);
    return While(_f955, _f956);
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
    var _f957 = _m_Expression_read(input);
    var _f958 = _m_Block_read(input);
    var _o959 = Optional<Block>.Empty;
    if (input.unsigned() == 1) {
        _o959 = Optional<Block>.Value(_m_Block_read(input));
    }
    var _f960 = _o959;
    return Branch(_f957, _f958, _f960);
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
        var _f1404 = _m_VariableDef_read(input);
        return Declaration.Variable(_f1404);
    }
    if (tag == 1) {
        var _f1405 = _m_FunctionDef_read(input);
        return Declaration.Function(_f1405);
    }
    if (tag == 2) {
        var _f1406 = _m_StructDef_read(input);
        return Declaration.Struct(_f1406);
    }
    if (tag == 3) {
        var _f1407 = _m_TraitDef_read(input);
        return Declaration.Trait(_f1407);
    }
    if (tag == 4) {
        var _f1408 = _m_ExtensionDef_read(input);
        return Declaration.Extension(_f1408);
    }
    if (tag == 5) {
        var _f1409 = _m_ExternDef_read(input);
        return Declaration.Extern(_f1409);
    }
    if (tag == 6) {
        var _f1410 = _m_TypeAliasDef_read(input);
        return Declaration.TypeAlias(_f1410);
    }
    input.fail("Declaration", tag);
    return _m_Declaration_read(input);
}

_m_TypeAliasDef_write(out: RecordOut, value: TypeAliasDef) {
    out.text(value.name);
    out.unsigned(value.generic_params.count);
    for (var _item961 in value.generic_params) {
        _m_GenericParam_write(out, _item961);
    }
    _m_TypeName_write(out, value.target);
    out.unsigned(value.attributes.count);
    for (var _item962 in value.attributes) {
        _a_Attribute_write(out, _item962);
    }
    out.loc(value.loc);
}

_m_TypeAliasDef_read(input: RecordIn): TypeAliasDef {
    var _f963 = input.text();
    var _v964 = Array<GenericParam>();
    var _n965 = input.count();
    for (var _ in 0.._n965) {
        _v964.append(_m_GenericParam_read(input));
    }
    var _f966 = _v964;
    var _f967 = _m_TypeName_read(input);
    var _v968 = Array<ast.Attribute>();
    var _n969 = input.count();
    for (var _ in 0.._n969) {
        _v968.append(_a_Attribute_read(input));
    }
    var _f970 = _v968;
    var _f971 = input.loc();
    return TypeAliasDef(_f963, _f966, _f967, _f970, _f971);
}

_m_GenericParam_write(out: RecordOut, value: GenericParam) {
    out.text(value.name);
    out.loc(value.loc);
    out.unsigned(value.bounds.count);
    for (var _item972 in value.bounds) {
        _m_Bound_write(out, _item972);
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
    var _f973 = input.text();
    var _f974 = input.loc();
    var _v975 = Array<Bound>();
    var _n976 = input.count();
    for (var _ in 0.._n976) {
        _v975.append(_m_Bound_read(input));
    }
    var _f977 = _v975;
    var _o978 = Optional<TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o978 = Optional<TypeName>.Value(_m_TypeName_read(input));
    }
    var _f979 = _o978;
    var _f980 = input.loc();
    var _f981 = input.flag();
    return GenericParam(_f973, _f974, _f977, _f979, _f980, _f981);
}

_m_Bound_write(out: RecordOut, value: Bound) {
    _m_TypeName_write(out, value.ty);
    out.loc(value.loc);
}

_m_Bound_read(input: RecordIn): Bound {
    var _f982 = _m_TypeName_read(input);
    var _f983 = input.loc();
    return Bound(_f982, _f983);
}

_m_ExternDef_write(out: RecordOut, value: ExternDef) {
    out.text(value.name);
    _m_TypeName_write(out, value.ty);
    out.unsigned(value.parameters.count);
    for (var _item984 in value.parameters) {
        _m_VariableDef_write(out, _item984);
    }
    out.flag(value.is_variadic);
    out.unsigned(value.attributes.count);
    for (var _item985 in value.attributes) {
        _a_Attribute_write(out, _item985);
    }
    out.loc(value.loc);
}

_m_ExternDef_read(input: RecordIn): ExternDef {
    var _f986 = input.text();
    var _f987 = _m_TypeName_read(input);
    var _v988 = Array<VariableDef>();
    var _n989 = input.count();
    for (var _ in 0.._n989) {
        _v988.append(_m_VariableDef_read(input));
    }
    var _f990 = _v988;
    var _f991 = input.flag();
    var _v992 = Array<ast.Attribute>();
    var _n993 = input.count();
    for (var _ in 0.._n993) {
        _v992.append(_a_Attribute_read(input));
    }
    var _f994 = _v992;
    var _f995 = input.loc();
    return ExternDef(_f986, _f987, _f990, _f991, _f994, _f995);
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
    for (var _item996 in value.traits) {
        _m_TypeName_write(out, _item996);
    }
    out.unsigned(value.restated.count);
    for (var _item997 in value.restated) {
        var (_t998, _t999) = _item997;
        out.unsigned(_t998);
        _m_Bound_write(out, _t999);
    }
    out.unsigned(value.methods.count);
    for (var _item1000 in value.methods) {
        _m_FunctionDef_write(out, _item1000);
    }
    out.unsigned(value.attributes.count);
    for (var _item1001 in value.attributes) {
        _a_Attribute_write(out, _item1001);
    }
    out.loc(value.loc);
    out.flag(value.is_exported);
    out.flag(value.is_private);
}

_m_ExtensionDef_read(input: RecordIn): ExtensionDef {
    var _f1002 = _m_TypeName_read(input);
    var _o1003 = Optional<String>.Empty;
    if (input.unsigned() == 1) {
        _o1003 = Optional<String>.Value(input.text());
    }
    var _f1004 = _o1003;
    var _v1005 = Array<TypeName>();
    var _n1006 = input.count();
    for (var _ in 0.._n1006) {
        _v1005.append(_m_TypeName_read(input));
    }
    var _f1007 = _v1005;
    var _v1008 = Array<(ulong, Bound)>();
    var _n1009 = input.count();
    for (var _ in 0.._n1009) {
        var _t1010 = input.unsigned();
        var _t1011 = _m_Bound_read(input);
        _v1008.append((_t1010, _t1011));
    }
    var _f1012 = _v1008;
    var _v1013 = Array<FunctionDef>();
    var _n1014 = input.count();
    for (var _ in 0.._n1014) {
        _v1013.append(_m_FunctionDef_read(input));
    }
    var _f1015 = _v1013;
    var _v1016 = Array<ast.Attribute>();
    var _n1017 = input.count();
    for (var _ in 0.._n1017) {
        _v1016.append(_a_Attribute_read(input));
    }
    var _f1018 = _v1016;
    var _f1019 = input.loc();
    var _f1020 = input.flag();
    var _f1021 = input.flag();
    return ExtensionDef(_f1002, _f1004, _f1007, _f1012, _f1015, _f1018, _f1019, _f1020, _f1021);
}

_m_TraitDef_write(out: RecordOut, value: TraitDef) {
    out.text(value.name);
    out.unsigned(value.generic_params.count);
    for (var _item1022 in value.generic_params) {
        _m_GenericParam_write(out, _item1022);
    }
    out.unsigned(value.methods.count);
    for (var _item1023 in value.methods) {
        _m_FunctionDef_write(out, _item1023);
    }
    out.unsigned(value.attributes.count);
    for (var _item1024 in value.attributes) {
        _a_Attribute_write(out, _item1024);
    }
    out.loc(value.loc);
}

_m_TraitDef_read(input: RecordIn): TraitDef {
    var _f1025 = input.text();
    var _v1026 = Array<GenericParam>();
    var _n1027 = input.count();
    for (var _ in 0.._n1027) {
        _v1026.append(_m_GenericParam_read(input));
    }
    var _f1028 = _v1026;
    var _v1029 = Array<FunctionDef>();
    var _n1030 = input.count();
    for (var _ in 0.._n1030) {
        _v1029.append(_m_FunctionDef_read(input));
    }
    var _f1031 = _v1029;
    var _v1032 = Array<ast.Attribute>();
    var _n1033 = input.count();
    for (var _ in 0.._n1033) {
        _v1032.append(_a_Attribute_read(input));
    }
    var _f1034 = _v1032;
    var _f1035 = input.loc();
    return TraitDef(_f1025, _f1028, _f1031, _f1034, _f1035);
}

_m_StructDef_write(out: RecordOut, value: StructDef) {
    out.text(value.name);
    _m_TypeName_write(out, value.ty);
    out.unsigned(value.generic_params.count);
    for (var _item1036 in value.generic_params) {
        _m_GenericParam_write(out, _item1036);
    }
    out.unsigned(value.field_members.count);
    for (var _item1037 in value.field_members) {
        _m_VariableDef_write(out, _item1037);
    }
    out.unsigned(value.method_members.count);
    for (var _item1038 in value.method_members) {
        _m_FunctionDef_write(out, _item1038);
    }
    out.unsigned(value.generic_methods.count);
    for (var _item1039 in value.generic_methods) {
        _m_FunctionDef_write(out, _item1039);
    }
    out.unsigned(value.constructors.count);
    for (var _item1040 in value.constructors) {
        _m_FunctionDef_write(out, _item1040);
    }
    _m_FunctionDef_write(out, value.destructor);
    _m_FunctionDef_write(out, value.acquire);
    _m_FunctionDef_write(out, value.release);
    out.unsigned(value.traits.count);
    for (var _item1041 in value.traits) {
        _m_TypeName_write(out, _item1041);
    }
    out.unsigned(value.attributes.count);
    for (var _item1042 in value.attributes) {
        _a_Attribute_write(out, _item1042);
    }
    out.loc(value.loc);
    if (value.enum_cases.is_value()) {
        out.unsigned(1);
        out.unsigned(value.enum_cases.value().count);
        for (var _item1043 in value.enum_cases.value()) {
            _m_EnumCaseDef_write(out, _item1043);
        }
    } else {
        out.unsigned(0);
    }
}

_m_StructDef_read(input: RecordIn): StructDef {
    var _f1044 = input.text();
    var _f1045 = _m_TypeName_read(input);
    var _v1046 = Array<GenericParam>();
    var _n1047 = input.count();
    for (var _ in 0.._n1047) {
        _v1046.append(_m_GenericParam_read(input));
    }
    var _f1048 = _v1046;
    var _v1049 = Array<VariableDef>();
    var _n1050 = input.count();
    for (var _ in 0.._n1050) {
        _v1049.append(_m_VariableDef_read(input));
    }
    var _f1051 = _v1049;
    var _v1052 = Array<FunctionDef>();
    var _n1053 = input.count();
    for (var _ in 0.._n1053) {
        _v1052.append(_m_FunctionDef_read(input));
    }
    var _f1054 = _v1052;
    var _v1055 = Array<FunctionDef>();
    var _n1056 = input.count();
    for (var _ in 0.._n1056) {
        _v1055.append(_m_FunctionDef_read(input));
    }
    var _f1057 = _v1055;
    var _v1058 = Array<FunctionDef>();
    var _n1059 = input.count();
    for (var _ in 0.._n1059) {
        _v1058.append(_m_FunctionDef_read(input));
    }
    var _f1060 = _v1058;
    var _f1061 = _m_FunctionDef_read(input);
    var _f1062 = _m_FunctionDef_read(input);
    var _f1063 = _m_FunctionDef_read(input);
    var _v1064 = Array<TypeName>();
    var _n1065 = input.count();
    for (var _ in 0.._n1065) {
        _v1064.append(_m_TypeName_read(input));
    }
    var _f1066 = _v1064;
    var _v1067 = Array<ast.Attribute>();
    var _n1068 = input.count();
    for (var _ in 0.._n1068) {
        _v1067.append(_a_Attribute_read(input));
    }
    var _f1069 = _v1067;
    var _f1070 = input.loc();
    var _o1071 = Optional<Array<EnumCaseDef>>.Empty;
    if (input.unsigned() == 1) {
        var _v1072 = Array<EnumCaseDef>();
        var _n1073 = input.count();
        for (var _ in 0.._n1073) {
            _v1072.append(_m_EnumCaseDef_read(input));
        }
        _o1071 = Optional<Array<EnumCaseDef>>.Value(_v1072);
    }
    var _f1074 = _o1071;
    return StructDef(
        _f1044, _f1045, _f1048, _f1051, _f1054, _f1057, _f1060, _f1061, _f1062, _f1063, _f1066, _f1069, _f1070, _f1074
    );
}

_m_EnumCaseDef_write(out: RecordOut, value: EnumCaseDef) {
    out.text(value.name);
    out.signed(value.value as long);
    out.unsigned(value.payload.count);
    for (var _item1075 in value.payload) {
        var (_t1076, _t1077) = _item1075;
        out.text(_t1076);
        out.loc(_t1077);
    }
    out.unsigned(value.attributes.count);
    for (var _item1078 in value.attributes) {
        _a_Attribute_write(out, _item1078);
    }
    out.loc(value.loc);
}

_m_EnumCaseDef_read(input: RecordIn): EnumCaseDef {
    var _f1079 = input.text();
    var _f1080 = input.signed();
    var _v1081 = Array<(String, Loc)>();
    var _n1082 = input.count();
    for (var _ in 0.._n1082) {
        var _t1083 = input.text();
        var _t1084 = input.loc();
        _v1081.append((_t1083, _t1084));
    }
    var _f1085 = _v1081;
    var _v1086 = Array<ast.Attribute>();
    var _n1087 = input.count();
    for (var _ in 0.._n1087) {
        _v1086.append(_a_Attribute_read(input));
    }
    var _f1088 = _v1086;
    var _f1089 = input.loc();
    return EnumCaseDef(_f1079, _f1080, _f1085, _f1088, _f1089);
}

_m_ExtensionScopes_write(out: RecordOut, value: ExtensionScopes) {
    out.unsigned(value.prelude.count);
    for (var _item1090 in value.prelude) {
        out.unsigned(_item1090 as ulong);
    }
    out.unsigned(value.visible.count);
    for (var _item1091 in value.visible) {
        out.unsigned(_item1091.count);
        for (var _item1092 in _item1091) {
            out.unsigned(_item1092 as ulong);
        }
    }
    out.unsigned(value.module.count);
    for (var _item1093 in value.module) {
        if (_item1093.is_value()) {
            out.unsigned(1);
            out.unsigned(_item1093.value() as ulong);
        } else {
            out.unsigned(0);
        }
    }
}

_m_ExtensionScopes_read(input: RecordIn): ExtensionScopes {
    var _v1094 = HashSet<uint>();
    var _n1095 = input.count();
    for (var _ in 0.._n1095) {
        _v1094.insert(input.unsigned() as uint);
    }
    var _f1096 = _v1094;
    var _v1097 = Array<HashSet<uint>>();
    var _n1098 = input.count();
    for (var _ in 0.._n1098) {
        var _v1099 = HashSet<uint>();
        var _n1100 = input.count();
        for (var _ in 0.._n1100) {
            _v1099.insert(input.unsigned() as uint);
        }
        _v1097.append(_v1099);
    }
    var _f1101 = _v1097;
    var _v1102 = Array<Optional<uint>>();
    var _n1103 = input.count();
    for (var _ in 0.._n1103) {
        var _o1104 = Optional<uint>.Empty;
        if (input.unsigned() == 1) {
            _o1104 = Optional<uint>.Value(input.unsigned() as uint);
        }
        _v1102.append(_o1104);
    }
    var _f1105 = _v1102;
    return ExtensionScopes(_f1096, _f1101, _f1105);
}

_m_Conversion_write(out: RecordOut, value: Conversion) {
    out.loc(value.at);
    _m_TypeName_write(out, value.from);
    _m_TypeName_write(out, value.to);
    out.loc(value.constructor);
}

_m_Conversion_read(input: RecordIn): Conversion {
    var _f1106 = input.loc();
    var _f1107 = _m_TypeName_read(input);
    var _f1108 = _m_TypeName_read(input);
    var _f1109 = input.loc();
    return Conversion(_f1106, _f1107, _f1108, _f1109);
}

_m_TraitType_write(out: RecordOut, value: TraitType) {
    _m_TypeName_write(out, value.ty);
    out.unsigned(value.methods.count);
    for (var _item1110 in value.methods) {
        _m_FunctionDef_write(out, _item1110);
    }
}

_m_TraitType_read(input: RecordIn): TraitType {
    var _f1111 = _m_TypeName_read(input);
    var _v1112 = Array<FunctionDef>();
    var _n1113 = input.count();
    for (var _ in 0.._n1113) {
        _v1112.append(_m_FunctionDef_read(input));
    }
    var _f1114 = _v1112;
    return TraitType(_f1111, _f1114);
}

_m_UseContext_write(out: RecordOut, value: UseContext) {
    out.unsigned(value.scope.count);
    for (var _item1115 in value.scope) {
        _m_GenericParam_write(out, _item1115);
    }
    if (value.extension.is_value()) {
        out.unsigned(1);
        _m_TypeName_write(out, value.extension.value());
    } else {
        out.unsigned(0);
    }
    out.unsigned(value.conditions.count);
    for (var _item1116 in value.conditions) {
        _a_Attribute_write(out, _item1116);
    }
}

_m_UseContext_read(input: RecordIn): UseContext {
    var _v1117 = Array<GenericParam>();
    var _n1118 = input.count();
    for (var _ in 0.._n1118) {
        _v1117.append(_m_GenericParam_read(input));
    }
    var _f1119 = _v1117;
    var _o1120 = Optional<TypeName>.Empty;
    if (input.unsigned() == 1) {
        _o1120 = Optional<TypeName>.Value(_m_TypeName_read(input));
    }
    var _f1121 = _o1120;
    var _v1122 = Array<ast.Attribute>();
    var _n1123 = input.count();
    for (var _ in 0.._n1123) {
        _v1122.append(_a_Attribute_read(input));
    }
    var _f1124 = _v1122;
    return UseContext(_f1119, _f1121, _f1124);
}

_m_TypeUse_write(out: RecordOut, value: TypeUse) {
    _m_TypeName_write(out, value.ty);
    out.unsigned(value.args.count);
    for (var _item1125 in value.args) {
        out.loc(_item1125);
    }
    out.unsigned(value.context);
}

_m_TypeUse_read(input: RecordIn): TypeUse {
    var _f1126 = _m_TypeName_read(input);
    var _v1127 = Array<Loc>();
    var _n1128 = input.count();
    for (var _ in 0.._n1128) {
        _v1127.append(input.loc());
    }
    var _f1129 = _v1127;
    var _f1130 = input.unsigned();
    return TypeUse(_f1126, _f1129, _f1130);
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
    var _f1131 = input.text();
    var _f1132 = input.text();
    var _f1133 = input.flag();
    var _f1134 = input.loc();
    var _f1135 = _m_AccessorKind_read(input);
    var _o1136 = Optional<AccessorKind>.Empty;
    if (input.unsigned() == 1) {
        _o1136 = Optional<AccessorKind>.Value(_m_AccessorKind_read(input));
    }
    var _f1137 = _o1136;
    var _f1138 = input.loc();
    var _o1139 = Optional<String>.Empty;
    if (input.unsigned() == 1) {
        _o1139 = Optional<String>.Value(input.text());
    }
    var _f1140 = _o1139;
    var _f1141 = input.flag();
    return PropertyDef(_f1131, _f1132, _f1133, _f1134, _f1135, _f1137, _f1138, _f1140, _f1141);
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
    var _f1142 = input.text();
    var _f1143 = input.text();
    var _f1144 = input.text();
    var _f1145 = input.unsigned();
    var _f1146 = _m_TypeName_read(input);
    var _f1147 = _m_TypeName_read(input);
    var _f1148 = input.loc();
    return Withheld(_f1142, _f1143, _f1144, _f1145, _f1146, _f1147, _f1148);
}

_m_EnumDef_write(out: RecordOut, value: EnumDef) {
    out.text(value.name);
    _m_TypeName_write(out, value.representation);
    out.unsigned(value.cases.count);
    for (var _item1149 in value.cases) {
        _m_EnumCaseDef_write(out, _item1149);
    }
    out.unsigned(value.attributes.count);
    for (var _item1150 in value.attributes) {
        _a_Attribute_write(out, _item1150);
    }
    out.loc(value.loc);
}

_m_EnumDef_read(input: RecordIn): EnumDef {
    var _f1151 = input.text();
    var _f1152 = _m_TypeName_read(input);
    var _v1153 = Array<EnumCaseDef>();
    var _n1154 = input.count();
    for (var _ in 0.._n1154) {
        _v1153.append(_m_EnumCaseDef_read(input));
    }
    var _f1155 = _v1153;
    var _v1156 = Array<ast.Attribute>();
    var _n1157 = input.count();
    for (var _ in 0.._n1157) {
        _v1156.append(_a_Attribute_read(input));
    }
    var _f1158 = _v1156;
    var _f1159 = input.loc();
    return EnumDef(_f1151, _f1152, _f1155, _f1158, _f1159);
}

_m_ModuleStaticBlock_write(out: RecordOut, value: ModuleStaticBlock) {
    _m_StaticBlock_write(out, value.block);
    out.unsigned(value.constants.count);
    for (var _item1160 in value.constants) {
        var (_t1161, _t1162) = _item1160;
        out.text(_t1161);
        out.loc(_t1162);
    }
}

_m_ModuleStaticBlock_read(input: RecordIn): ModuleStaticBlock {
    var _f1163 = _m_StaticBlock_read(input);
    var _v1164 = Array<(String, Loc)>();
    var _n1165 = input.count();
    for (var _ in 0.._n1165) {
        var _t1166 = input.text();
        var _t1167 = input.loc();
        _v1164.append((_t1166, _t1167));
    }
    var _f1168 = _v1164;
    return ModuleStaticBlock(_f1163, _f1168);
}

_a_Import_write(out: RecordOut, value: ast.Import) {
    out.text(value.name);
    out.unsigned(value.name_span.start);
    out.unsigned(value.name_span.end);
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
        for (var _item1169 in value.symbols.value()) {
            _a_ImportedSymbol_write(out, _item1169);
        }
    } else {
        out.unsigned(0);
    }
    out.flag(value.reexport);
    out.unsigned(value.attributes.count);
    for (var _item1170 in value.attributes) {
        _a_Attribute_write(out, _item1170);
    }
    out.unsigned(value.span.start);
    out.unsigned(value.span.end);
}

_a_Import_read(input: RecordIn): ast.Import {
    var _f1171 = input.text();
    var _s1172 = input.unsigned();
    var _f1173 = ast.Span(_s1172, input.unsigned());
    var _o1174 = Optional<String>.Empty;
    if (input.unsigned() == 1) {
        _o1174 = Optional<String>.Value(input.text());
    }
    var _f1175 = _o1174;
    var _f1176 = input.flag();
    var _o1177 = Optional<Array<ast.ImportedSymbol>>.Empty;
    if (input.unsigned() == 1) {
        var _v1178 = Array<ast.ImportedSymbol>();
        var _n1179 = input.count();
        for (var _ in 0.._n1179) {
            _v1178.append(_a_ImportedSymbol_read(input));
        }
        _o1177 = Optional<Array<ast.ImportedSymbol>>.Value(_v1178);
    }
    var _f1180 = _o1177;
    var _f1181 = input.flag();
    var _v1182 = Array<ast.Attribute>();
    var _n1183 = input.count();
    for (var _ in 0.._n1183) {
        _v1182.append(_a_Attribute_read(input));
    }
    var _f1184 = _v1182;
    var _s1185 = input.unsigned();
    var _f1186 = ast.Span(_s1185, input.unsigned());
    var value = ast.Import();
    value.name = _f1171;
    value.name_span = _f1173;
    value.alias = _f1175;
    value.is_local = _f1176;
    value.symbols = _f1180;
    value.reexport = _f1181;
    value.attributes = _f1184;
    value.span = _f1186;
    return value;
}

_a_ImportedSymbol_write(out: RecordOut, value: ast.ImportedSymbol) {
    out.text(value.name);
    out.unsigned(value.name_span.start);
    out.unsigned(value.name_span.end);
    if (value.alias.is_value()) {
        out.unsigned(1);
        out.text(value.alias.value());
    } else {
        out.unsigned(0);
    }
    out.unsigned(value.span.start);
    out.unsigned(value.span.end);
}

_a_ImportedSymbol_read(input: RecordIn): ast.ImportedSymbol {
    var _f1187 = input.text();
    var _s1188 = input.unsigned();
    var _f1189 = ast.Span(_s1188, input.unsigned());
    var _o1190 = Optional<String>.Empty;
    if (input.unsigned() == 1) {
        _o1190 = Optional<String>.Value(input.text());
    }
    var _f1191 = _o1190;
    var _s1192 = input.unsigned();
    var _f1193 = ast.Span(_s1192, input.unsigned());
    var value = ast.ImportedSymbol();
    value.name = _f1187;
    value.name_span = _f1189;
    value.alias = _f1191;
    value.span = _f1193;
    return value;
}
