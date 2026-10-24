"""Offline WX-78 regression using installed native UI methods and actual PVP hooks.

Requires Python + lupa.lua51; no game process or save is touched.
Run: python tools/pvp/tests/wx78_quick_announce.py --lupa-path <temporary install>
Optional --baseline-ref reproduces the prior wrong names and battery messages.
UI animation, input, and network objects are stubs; this is not a live-client test.
"""

import argparse
from pathlib import Path
import re
import subprocess
import sys
import zipfile


def between(source, start, end):
    first = source.index(start)
    return source[first:source.index(end, first)]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lupa-path", type=Path)
    parser.add_argument("--baseline-ref")
    args = parser.parse_args()
    if args.lupa_path:
        sys.path.insert(0, str(args.lupa_path))
    from lupa.lua51 import LuaRuntime

    root = Path(__file__).resolve().parents[3]
    with zipfile.ZipFile(root.parent / "data/databundles/scripts.zip") as archive:
        display = archive.read("scripts/widgets/upgrademodulesdisplay.lua").decode("utf-8")
        moduledefs = archive.read("scripts/wx78_moduledefs.lua").decode("utf-8")
        stringutil = archive.read("scripts/stringutil.lua").decode("utf-8")
        constants = archive.read("scripts/constants.lua").decode("utf-8")

    native = []
    for method in ("OnModuleAdded", "PopModuleAtIndex", "DropChip", "PopOneModule", "PopAllModules", "UpdateMaxEnergy"):
        match = re.search(r"^function UpgradeModulesDisplay:" + method + r"\([^\n]*\)\r?\n.*?^end\b", display, re.M | re.S)
        if not match:
            raise RuntimeError(f"Installed WX-78 display lacks {method}; review this build")
        native.append(match.group())
    native.append(re.search(r"^function subfmt\([^\n]*\)\r?\n.*?^end\b", stringutil, re.M | re.S).group())
    bars = re.search(r"^CIRCUIT_BARS =[^\n]*\r?\n\{.*?^\}", constants, re.M | re.S).group()
    native.insert(0, bars)

    # Derive real module IDs and slot costs from the installed registration order.
    tables = dict(re.findall(r"local (\w+_MODULE_DATA)\s*=\s*\{(.*?)^\}", moduledefs, re.M | re.S))
    definitions = []
    for netid, name in enumerate(re.findall(r"table.insert\(module_definitions, (\w+)\)", moduledefs), 1):
        body = tables[name]
        module_name = re.search(r'name\s*=\s*"([^"]+)"', body).group(1)
        bar = re.search(r"type\s*=\s*(CIRCUIT_BARS\.\w+)", body).group(1)
        slots = re.search(r"slots\s*=\s*(\d+)", body).group(1)
        definitions.append(f'[{netid}]={{name="{module_name}",type={bar},slots={slots}}}')
    native.append("module_definitions={" + ",".join(definitions) + "}")

    harness = Path(__file__).with_suffix(".lua").read_text(encoding="utf-8")
    revisions = [(None, False)]
    if args.baseline_ref:
        revisions.insert(0, (args.baseline_ref, True))
    paths = {
        "loader_source": "pvp/scripts/src/ui/quick_announce.lua",
        "guard_source": "pvp/scripts/src/ui/wx78_quick_announce_guard.lua",
        "defaults_source": "pvp/scripts/qa_default.lua",
        "qa_source": "pvp/scripts/qa_main.lua",
    }
    for revision, baseline in revisions:
        sources = {}
        for key, path in paths.items():
            sources[key] = (
                subprocess.check_output(["git", "show", f"{revision}:{path}"], cwd=root).decode("utf-8")
                if revision else (root / path).read_text(encoding="utf-8")
            )
        qa = sources["qa_source"]
        sender = between(qa, 'local bird_team_state=require("src/team/lobby_team_state")', "local function J(")
        if 'local ao=require("wx78_moduledefs")' in qa:
            hook = between(qa, 'local ao=require("wx78_moduledefs")', "local aB=")
        else:
            hook = between(qa, "AddClassPostConstruct('widgets/upgrademodulesdisplay'", "local aB=")
        energy = between(qa, "if O.controls.secondary_status", "if O.controls and O.controls.foodcrafting")
        sources["qa_fragment_source"] = (
            sender + hook + "\nfunction AnnounceWXEnergy(display) "
            "local O={controls={secondary_status={upgrademodulesdisplay=display}}}; " + energy + "end"
        )
        lua = LuaRuntime(unpack_returned_tuples=True)
        for key, source in sources.items():
            # Also compile the whole minified module, not only executed WX fragments.
            lua.execute("assert(loadstring(...))", source)
            lua.globals()[key] = source
        lua.globals().native_source = "UpgradeModulesDisplay={}\n" + "\n".join(native)
        lua.globals().is_baseline = baseline
        result = lua.execute(harness)
        print(f"PASS {revision or 'working tree'}: {result} assertions ({lua.eval('_VERSION')})")


if __name__ == "__main__":
    main()
