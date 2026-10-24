"""Offline planar-damage regression using installed DST Combat and actual PVP scripts.

Requires Python + lupa.lua51. No game process or save is touched.
Run: python tools/pvp/tests/planar_damage.py --lupa-path <temporary install>
Optional --baseline-ref 2de57b9 reproduces the old internal-entry damage leak.
Engine entities, special-damage defenses, and original SG reactions are stubs;
this validates Lua integration, not a real-client session.
"""

import argparse
from pathlib import Path
import re
import subprocess
import sys
import zipfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lupa-path", type=Path)
    parser.add_argument("--baseline-ref", help="Optional revision before the planar fix")
    args = parser.parse_args()
    if args.lupa_path:
        sys.path.insert(0, str(args.lupa_path))
    from lupa.lua51 import LuaRuntime

    root = Path(__file__).resolve().parents[3]
    health_bar_path = "pvp/scripts/src/ui/health_bar.lua"
    with zipfile.ZipFile(root.parent / "data/databundles/scripts.zip") as archive:
        combat = archive.read("scripts/components/combat.lua").decode("utf-8")
    methods = []
    for name in ("DoAttack", "DoAreaAttack", "GetAttacked", "GetAttacked_Internal"):
        match = re.search(r"^function Combat:" + name + r"\([^\n]*\)\r?\n.*?^end\b", combat, re.M | re.S)
        if not match:
            raise RuntimeError(f"Installed Combat lacks {name}; review this build before testing")
        methods.append(match.group())
    harness = Path(__file__).with_suffix(".lua").read_text(encoding="utf-8")
    protection = (root / "pvp/scripts/src/protection/player.lua").read_text(encoding="utf-8")
    versions = []
    if args.baseline_ref:
        baseline = subprocess.check_output(
            ["git", "show", f"{args.baseline_ref}:{health_bar_path}"], cwd=root
        ).decode("utf-8")
        versions.append((f"{args.baseline_ref} baseline", baseline, True))
    versions.append(("working tree", (root / health_bar_path).read_text(encoding="utf-8"), False))
    for label, source, is_baseline in versions:
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().Combat = lua.table()
        lua.execute("\n\n".join(methods))
        lua.globals().health_bar_source = source
        lua.globals().protection_source = protection
        lua.globals().is_baseline = is_baseline
        count = lua.execute(harness)
        print(f"PASS {label}: {count} assertions ({lua.eval('_VERSION')})")
    if args.baseline_ref:
        print("PASS: baseline leaks planar damage through native internal attacks; fixed entries remove it.")


if __name__ == "__main__":
    main()
