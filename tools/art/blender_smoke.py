import argparse
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    return parser.parse_args(argv)


def point_at(obj: bpy.types.Object, target: Vector) -> None:
    direction = target - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def main() -> None:
    args = parse_args()
    output = Path(args.output).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 128
    scene.render.resolution_y = 128
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = True
    scene.render.filepath = str(output)

    bpy.ops.mesh.primitive_cube_add(location=(0.0, 0.0, 0.65))
    cube = bpy.context.object
    cube.name = "ToolchainSmokeCube"
    cube.scale = (1.25, 0.72, 0.65)
    bevel = cube.modifiers.new(name="EdgeBevel", type="BEVEL")
    bevel.width = 0.08
    bevel.segments = 3

    material = bpy.data.materials.new("BrassSmokeMaterial")
    material.diffuse_color = (0.63, 0.31, 0.08, 1.0)
    material.metallic = 0.72
    material.roughness = 0.34
    cube.data.materials.append(material)

    bpy.ops.mesh.primitive_plane_add(size=8.0, location=(0.0, 0.0, 0.0))
    ground = bpy.context.object
    ground.name = "ToolchainSmokeGround"
    ground_material = bpy.data.materials.new("GroundMaterial")
    ground_material.diffuse_color = (0.018, 0.024, 0.04, 1.0)
    ground_material.roughness = 0.9
    ground.data.materials.append(ground_material)

    bpy.ops.object.light_add(type="AREA", location=(2.8, -3.0, 4.0))
    key = bpy.context.object
    key.name = "WarmKey"
    key.data.energy = 850.0
    key.data.color = (1.0, 0.45, 0.12)
    key.data.shape = "DISK"
    key.data.size = 3.0
    point_at(key, Vector((0.0, 0.0, 0.6)))

    bpy.ops.object.light_add(type="AREA", location=(-3.0, 1.8, 2.5))
    rim = bpy.context.object
    rim.name = "ColdRim"
    rim.data.energy = 500.0
    rim.data.color = (0.34, 0.58, 0.8)
    rim.data.size = 2.0
    point_at(rim, Vector((0.0, 0.0, 0.8)))

    bpy.ops.object.camera_add(location=(4.2, -6.0, 3.4))
    camera = bpy.context.object
    camera.name = "ToolchainSmokeCamera"
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 4.2
    point_at(camera, Vector((0.0, 0.0, 0.65)))
    scene.camera = camera

    scene.world = bpy.data.worlds.new("ToolchainSmokeWorld")
    scene.world.color = (0.008, 0.012, 0.02)
    scene.render.filepath = str(output)
    bpy.ops.render.render(write_still=True)

    if not output.is_file():
        raise RuntimeError(f"Smoke render was not created: {output}")
    print(f"[blender-smoke] version={bpy.app.version_string} output={output}")


if __name__ == "__main__":
    main()
