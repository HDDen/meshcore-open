#!/usr/bin/env python3
"""Verify static MCOtxt Dart/C artifacts and the canonical model manifest."""
from __future__ import annotations
import hashlib, json, re
from pathlib import Path

VERSION=1
LANGS=("en","ru","fr","de","it","uk","be")


def find_root() -> Path:
    here=Path(__file__).resolve()
    for candidate in (here.parent,*here.parents):
        if (candidate/"pubspec.yaml").is_file(): return candidate
    for candidate in (Path.cwd().resolve(),*Path.cwd().resolve().parents):
        if (candidate/"lib/MCOtxt/models/mcotxt_model_registry.dart").is_file(): return candidate
    raise SystemExit("Cannot locate project root")


def canonical_hash_from_dart(text:str, lang:str, language_id:int)->str:
    C=lang[0].upper()+lang[1:]; p=f"mcotxt{C}"
    def int_list(name):
        m=re.search(rf"const List<int> {name} = <int>\[(.*?)\];",text,re.S)
        if not m: raise ValueError(f"missing {name}")
        return [int(x,0) for x in re.findall(r"0x[0-9A-Fa-f]+|\d+",m.group(1))]
    primary=int_list(p+"PrimarySymbols"); extension=int_list(p+"ExtensionSymbols")
    start=int_list(p+"StartTop4Indexes"); punct=int_list(p+"PunctStartTop4Indexes"); top4=int_list(p+"Top4Indexes")
    symbols=primary+extension; index={cp:i for i,cp in enumerate(symbols)}
    mm=re.search(rf"const Map<int, int> {p}UppercaseToLowercase = <int, int>\{{(.*?)\}};",text,re.S)
    if not mm: raise ValueError(f"missing {p}UppercaseToLowercase")
    pairs=[]
    for u,l in re.findall(r"(0x[0-9A-Fa-f]+|\d+)\s*:\s*(0x[0-9A-Fa-f]+|\d+)",mm.group(1)):
        pairs.append({"uppercaseCodepoint":int(u,0),"lowercaseSymbolIndex":index[int(l,0)]})
    payload={"codecVersion":VERSION,"language":lang,"languageId":language_id,"primarySymbols":primary,"extensionSymbols":extension,"startTop4Indexes":start,"punctStartTop4Indexes":punct,"top4Indexes":top4,"uppercaseMap":sorted(pairs,key=lambda x:(x["uppercaseCodepoint"],x["lowercaseSymbolIndex"]))}
    blob=json.dumps(payload,ensure_ascii=False,sort_keys=True,separators=(",",":")).encode()
    return hashlib.sha256(blob).hexdigest()


def canonical_hash_from_c(text:str, lang:str, language_id:int)->str:
    prefix=f"mcotxt_{lang}"
    def arr(name):
        m=re.search(rf"static const uint(?:8|16)_t {name}\[\d+\] = \{{(.*?)\}};",text,re.S)
        if not m: raise ValueError(f"missing C array {name}")
        return [int(x,0) for x in re.findall(r"0x[0-9A-Fa-f]+|\d+",m.group(1))]
    primary=arr(prefix+"_primary_symbols"); extension=arr(prefix+"_extension_symbols")
    start=arr(prefix+"_start_top4"); punct=arr(prefix+"_punct_start_top4"); top4=arr(prefix+"_top4")
    mm=re.search(rf"static const mcotxt_uppercase_pair_t {prefix}_uppercase_map\[\d+\] = \{{(.*?)\}};",text,re.S)
    if not mm: raise ValueError(f"missing C uppercase map {prefix}")
    pairs=[{"uppercaseCodepoint":int(u,0),"lowercaseSymbolIndex":int(i,0)} for u,i in re.findall(r"\{\s*(0x[0-9A-Fa-f]+|\d+)u?\s*,\s*(\d+)u?\s*\}",mm.group(1))]
    payload={"codecVersion":VERSION,"language":lang,"languageId":language_id,"primarySymbols":primary,"extensionSymbols":extension,"startTop4Indexes":start,"punctStartTop4Indexes":punct,"top4Indexes":top4,"uppercaseMap":sorted(pairs,key=lambda x:(x["uppercaseCodepoint"],x["lowercaseSymbolIndex"]))}
    blob=json.dumps(payload,ensure_ascii=False,sort_keys=True,separators=(",",":")).encode()
    return hashlib.sha256(blob).hexdigest()


def main()->int:
    root=find_root(); runtime=root/f"lib/MCOtxt/models/generated/v{VERSION}"; gen=root/"tools/MCOtxt/generated"; manifest_path=gen/"model_manifest.json"; registry=root/"lib/MCOtxt/models/mcotxt_model_registry.dart"
    manifest=json.loads(manifest_path.read_text(encoding="utf-8")); reg=registry.read_text(encoding="utf-8"); ok=True
    if manifest.get("codecVersion")!=VERSION: print("MANIFEST ERROR: codecVersion mismatch"); ok=False
    for lang in LANGS:
        entry=manifest["models"][lang]; wid=entry["languageId"]; rt=runtime/f"model_{lang}.dart"; local=gen/lang/f"model_{lang}.dart"; chead=gen/lang/f"model_{lang}.h"; C=lang[0].upper()+lang[1:]
        for path,label in ((rt,"runtime Dart"),(local,"generated Dart"),(chead,"generated C")):
            if not path.is_file(): print(f"MISSING {lang.upper()} {label}: {path}"); ok=False
        if not (rt.is_file() and local.is_file() and chead.is_file()): continue
        rt_text=rt.read_text(encoding="utf-8"); local_text=local.read_text(encoding="utf-8"); c_text=chead.read_text(encoding="utf-8")
        if rt_text != local_text: print(f"MISMATCH {lang.upper()}: runtime Dart != generated Dart"); ok=False
        if f"generated/v{VERSION}/model_{lang}.dart" not in reg or f"mcotxtModel{C}" not in reg: print(f"REGISTRY MISSING {lang.upper()}"); ok=False
        if entry.get("available"):
            expected=entry.get("wireHash")
            try:
                actual=canonical_hash_from_dart(rt_text,lang,wid)
                actual_c=canonical_hash_from_c(c_text,lang,wid)
            except Exception as exc: print(f"PARSE ERROR {lang.upper()}: {exc}"); ok=False; continue
            dart_hash=re.search(r"WireHash = '([0-9a-f]{64})'",rt_text); c_hash=re.search(r'_wire_hash\[\] = "([0-9a-f]{64})"',c_text)
            if actual!=expected or actual_c!=expected or not dart_hash or dart_hash.group(1)!=expected or not c_hash or c_hash.group(1)!=expected:
                print(f"HASH MISMATCH {lang.upper()}: manifest/Dart/C disagree"); ok=False
            else: print(f"OK {lang.upper()}: available, wire hash {expected[:12]}…")
        else:
            if "MCOtxtLanguageModel.unavailable" not in rt_text or re.search(r'_available\s*=\s*0u',c_text) is None:
                print(f"PLACEHOLDER ERROR {lang.upper()}: unavailable marker missing"); ok=False
            else: print(f"OK {lang.upper()}: unavailable placeholder")
    if "_buildModel(" in reg or "_buildTop4Tables(" in reg: print("REGISTRY ERROR: runtime model-building remains"); ok=False
    if ok:
        print(f"All MCOtxt v{VERSION} static model artifacts match the manifest. frozen={bool(manifest.get('frozen'))}")
        return 0
    return 1

if __name__=="__main__": raise SystemExit(main())
