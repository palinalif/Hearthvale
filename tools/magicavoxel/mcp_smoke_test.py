"""Exercise Hearthvale's pinned MagicaVoxel server through MCP stdio."""

from __future__ import annotations

import asyncio
import json
import os
from pathlib import Path

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

PROJECT = Path(__file__).resolve().parents[2]
STAGING = PROJECT / ".tools" / "magicavoxel"
MODEL = "hearthvale_tree_pilot_broad"


def text_of(result) -> str:
    return "\n".join(getattr(item, "text", "") for item in result.content)


async def call(session: ClientSession, name: str, arguments: dict) -> str:
    result = await session.call_tool(name, arguments)
    value = text_of(result)
    if result.isError or value.startswith("Error:"):
        raise RuntimeError(f"{name}: {value}")
    return value


async def main() -> None:
    parameters = StdioServerParameters(
        command=str(Path.home() / ".codex" / "mcp" / "magicavoxel-mcp-venv" / "Scripts" / "python.exe"),
        args=[str(Path.home() / ".codex" / "mcp" / "magicavoxel_safe_server.py")],
        env={
            **os.environ,
            "VOX_DIR": str(STAGING / "vox"),
            "EXPORT_DIR": str(STAGING / "previews"),
        },
    )
    async with stdio_client(parameters) as streams:
        async with ClientSession(*streams) as session:
            await session.initialize()
            listed = await session.list_tools()
            tool_names = {tool.name for tool in listed.tools}
            required = {"create_voxel_model", "set_palette_color", "fill_box", "create_cylinder", "create_sphere", "get_model_info", "take_snapshot"}
            missing = sorted(required - tool_names)
            if missing:
                raise RuntimeError(f"missing MCP tools: {missing}")

            blocked = await session.call_tool("create_voxel_model", {"filename": "../escape_probe", "width": 1, "height": 1, "depth": 1})
            if "plain .vox basename" not in text_of(blocked):
                raise RuntimeError("confinement wrapper did not reject traversal probe")

            await call(session, "create_voxel_model", {"filename": MODEL, "width": 32, "height": 48, "depth": 32})
            for color_index, rgb in {1: (118, 89, 66), 2: (99, 131, 72), 3: (72, 109, 70), 4: (135, 166, 87)}.items():
                await call(session, "set_palette_color", {"filename": MODEL, "color_index": color_index, "r": rgb[0], "g": rgb[1], "b": rgb[2], "a": 255})
            await call(session, "create_cylinder", {"filename": MODEL, "center_x": 15, "center_y": 0, "center_z": 15, "radius": 2, "height": 23, "axis": "y", "color_index": 1})
            await call(session, "fill_box", {"filename": MODEL, "x1": 13, "y1": 15, "z1": 14, "x2": 8, "y2": 18, "z2": 16, "color_index": 1})
            await call(session, "fill_box", {"filename": MODEL, "x1": 16, "y1": 17, "z1": 14, "x2": 22, "y2": 20, "z2": 16, "color_index": 1})
            for x, y, z, radius, color in [(9, 24, 15, 8, 2), (21, 27, 16, 9, 3), (15, 36, 14, 9, 4)]:
                await call(session, "create_sphere", {"filename": MODEL, "center_x": x, "center_y": y, "center_z": z, "radius": radius, "color_index": color, "hollow": False})
            info = await call(session, "get_model_info", {"filename": MODEL})
            snapshot = await call(session, "take_snapshot", {"filename": MODEL, "snapshot_name": MODEL + "_preview"})

    model_path = STAGING / "vox" / f"{MODEL}.vox"
    if not model_path.is_file() or model_path.stat().st_size <= 32:
        raise RuntimeError("MCP did not produce a valid staging file")
    print(json.dumps({"ok": True, "tools": len(tool_names), "model": str(model_path), "bytes": model_path.stat().st_size, "info": info, "snapshot": snapshot}, sort_keys=True))


if __name__ == "__main__":
    asyncio.run(main())
