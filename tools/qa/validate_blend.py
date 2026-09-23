from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPO_ROOT / "assets" / "source"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--blender")
    parser.add_argument("--inside-blender", action="store_true")
    parser.add_argument("--manifest")
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else sys.argv[1:]
    return parser.parse_args(argv)


def blend_manifests() -> list[Path]:
    results: list[Path] = []
    for path in SOURCE_ROOT.rglob("*.json"):
        data = json.loads(path.read_text(encoding="utf-8"))
        if data.get("source_type") == "blend":
            results.append(path)
    return sorted(results)


def require_names(actual: set[str], expected: list[str], label: str) -> None:
    missing = sorted(set(expected).difference(actual))
    if missing:
        raise RuntimeError(f"Blend is missing {label}: {', '.join(missing)}")


def validate_inside_blender(manifest_path: Path) -> None:
    import bpy

    manifest: dict[str, Any] = json.loads(
        manifest_path.read_text(encoding="utf-8")
    )
    require_names(
        {collection.name for collection in bpy.data.collections},
        manifest.get("collections", []),
        "collections",
    )
    require_names(
        {material.name for material in bpy.data.materials},
        manifest.get("materials", []),
        "materials",
    )
    action_specs = manifest.get("actions", [])
    require_names(
        {action.name for action in bpy.data.actions},
        [str(item["name"]) for item in action_specs],
        "actions",
    )
    for action_spec in action_specs:
        action = bpy.data.actions.get(str(action_spec["name"]))
        expected_range = action_spec.get("frame_range")
        if expected_range is not None:
            actual_range = [float(action.frame_range[0]), float(action.frame_range[1])]
            if actual_range != [float(value) for value in expected_range]:
                raise RuntimeError(
                    f"Action range drift for {action.name}: "
                    f"expected {expected_range}, got {actual_range}"
                )
    for object_spec in manifest.get("objects", []):
        name = str(object_spec["name"])
        obj = bpy.data.objects.get(name)
        if obj is None:
            raise RuntimeError(f"Blend is missing object: {name}")
        if obj.type == "MESH":
            mesh = obj.data
            topology = {
                "vertices": len(mesh.vertices),
                "edges": len(mesh.edges),
                "polygons": len(mesh.polygons),
            }
            expected = object_spec.get("topology")
            if expected is not None and topology != expected:
                raise RuntimeError(
                    f"Topology drift for {name}: expected {expected}, got {topology}"
                )
            expected_hash = object_spec.get("topology_hash")
            if expected_hash is not None:
                digest = hashlib.sha256()
                for vertex in mesh.vertices:
                    digest.update(
                        ",".join(f"{component:.6f}" for component in vertex.co).encode()
                    )
                    digest.update(b";")
                for edge in mesh.edges:
                    digest.update(f"{edge.vertices[0]},{edge.vertices[1]};".encode())
                for polygon in mesh.polygons:
                    digest.update(
                        (",".join(str(index) for index in polygon.vertices) + ";").encode()
                    )
                actual_hash = digest.hexdigest()
                if actual_hash != expected_hash:
                    raise RuntimeError(
                        f"Topology hash drift for {name}: "
                        f"expected {expected_hash}, got {actual_hash}"
                    )
    for armature_spec in manifest.get("armatures", []):
        armature = bpy.data.objects.get(str(armature_spec["name"]))
        if armature is None or armature.type != "ARMATURE":
            raise RuntimeError(
                f"Blend is missing armature: {armature_spec['name']}"
            )
        actual_bones = {
            bone.name: bone.parent.name if bone.parent is not None else ""
            for bone in armature.data.bones
        }
        expected_bones = {
            str(item["name"]): str(item.get("parent", ""))
            for item in armature_spec.get("bones", [])
        }
        if actual_bones != expected_bones:
            raise RuntimeError(
                f"Bone hierarchy drift for {armature.name}: "
                f"expected {expected_bones}, got {actual_bones}"
            )
    for socket_spec in manifest.get("sockets", []):
        socket = bpy.data.objects.get(str(socket_spec["name"]))
        if socket is None:
            raise RuntimeError(f"Blend is missing socket: {socket_spec['name']}")
        expected_location = [float(value) for value in socket_spec["location"]]
        actual_location = [float(value) for value in socket.location]
        if any(
            abs(actual_location[index] - expected_location[index]) > 0.0001
            for index in range(3)
        ):
            raise RuntimeError(
                f"Socket drift for {socket.name}: "
                f"expected {expected_location}, got {actual_location}"
            )
    print(f"[blend] verified manifest={manifest_path}")


def main() -> int:
    args = parse_args()
    if args.inside_blender:
        if not args.manifest:
            raise ValueError("--manifest is required inside Blender.")
        validate_inside_blender(Path(args.manifest).resolve())
        return 0

    manifests = blend_manifests()
    if not manifests:
        print("[blend] no controlled scene-first sources")
        return 0
    if not args.blender:
        raise ValueError("--blender is required when blend manifests exist.")
    blender = Path(args.blender).resolve()
    for manifest_path in manifests:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        blend_path = (manifest_path.parent / str(manifest["blend_file"])).resolve()
        command = [
            str(blender),
            "--background",
            str(blend_path),
            "--python",
            str(Path(__file__).resolve()),
            "--",
            "--inside-blender",
            "--manifest",
            str(manifest_path),
        ]
        result = subprocess.run(command, check=False)
        if result.returncode != 0:
            return result.returncode
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
