"""Offline first-day tornado regression with the installed game's actual Lua.

Run: python tools/pvp/tests/tornado_protection.py --lupa-path <temporary install>
Uses native CastSpell, tornado creation/damage, and Combat methods with engine
entity stubs. No game process or save is touched; this is not a live-client test.
"""

import argparse
from pathlib import Path
import re
import sys
import zipfile


def extract(source, declaration):
    match = re.search(r"^" + re.escape(declaration) + r"\([^\n]*\)\r?\n.*?^end\b", source, re.M | re.S)
    if not match:
        raise RuntimeError(f"Installed scripts lack {declaration}; review this build before testing")
    return match.group()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lupa-path", type=Path)
    args = parser.parse_args()
    if args.lupa_path:
        sys.path.insert(0, str(args.lupa_path))
    from lupa.lua51 import LuaRuntime

    root = Path(__file__).resolve().parents[3]
    with zipfile.ZipFile(root.parent / "data/databundles/scripts.zip") as archive:
        combat = archive.read("scripts/components/combat.lua").decode("utf-8")
        spellcaster = archive.read("scripts/components/spellcaster.lua").decode("utf-8")
        staff = archive.read("scripts/prefabs/staff_tornado.lua").decode("utf-8")
        tornado = archive.read("scripts/stategraphs/SGtornado.lua").decode("utf-8")
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().Combat = lua.table()
    lua.globals().SpellCaster = lua.table()
    lua.execute("\n\n".join(extract(combat, f"function Combat:{name}") for name in ("GetAttacked", "GetAttacked_Internal")))
    lua.execute(extract(spellcaster, "function SpellCaster:CastSpell"))
    lua.execute("\n\n".join([
        extract(staff, "local function getspawnlocation"),
        extract(staff, "local function spawntornado"),
        "native_spawntornado = spawntornado",
        "local TARGET_IGNORE_TAGS, TARGET_TAGS, WORK_ACTIONS = {}, {}, {}",
        extract(tornado, "local function destroystuff"),
        "native_tornado_damage = destroystuff",
    ]))
    lua.globals().early_game_source = (root / "pvp/scripts/src/gameplay/early_game.lua").read_text(encoding="utf-8")
    lua.globals().protection_source = (root / "pvp/scripts/src/protection/player.lua").read_text(encoding="utf-8")
    count = lua.execute(Path(__file__).with_suffix(".lua").read_text(encoding="utf-8"))
    print(f"PASS tornado protection: {count} assertions ({lua.eval('_VERSION')})")


if __name__ == "__main__":
    main()
