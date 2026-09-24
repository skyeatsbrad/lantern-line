from __future__ import annotations

import argparse
import json
import math
import random
import sys
from pathlib import Path
from typing import Any

import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True)
    parser.add_argument("--treatment", required=True)
    parser.add_argument("--output-root", required=True)
    parser.add_argument(
        "--engine",
        choices=["preview", "canonical"],
        default="preview",
    )
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    return parser.parse_args(argv)


def hex_rgb(value: str) -> tuple[float, float, float, float]:
    text = value.lstrip("#")
    values = [int(text[index : index + 2], 16) / 255.0 for index in (0, 2, 4)]
    return values[0], values[1], values[2], 1.0


def point_at(obj: bpy.types.Object, target: Vector) -> None:
    direction = target - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def make_principled(
    name: str,
    color: tuple[float, float, float, float],
    metallic: float,
    roughness: float,
    emission_strength: float = 0.0,
) -> bpy.types.Material:
    material = bpy.data.materials.new(name)
    material.diffuse_color = color
    material.use_nodes = True
    node = material.node_tree.nodes.get("Principled BSDF")
    node.inputs["Base Color"].default_value = color
    node.inputs["Metallic"].default_value = metallic
    node.inputs["Roughness"].default_value = roughness
    if emission_strength > 0.0:
        node.inputs["Emission Color"].default_value = color
        node.inputs["Emission Strength"].default_value = emission_strength
    material["base_color"] = list(color)
    material["base_metallic"] = metallic
    material["base_roughness"] = roughness
    material["emission_strength"] = emission_strength
    return material


def make_emission(
    name: str,
    color: tuple[float, float, float, float],
) -> bpy.types.Material:
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    emission = nodes.new("ShaderNodeEmission")
    emission.inputs["Color"].default_value = color
    emission.inputs["Strength"].default_value = 1.0
    links.new(emission.outputs["Emission"], output.inputs["Surface"])
    return material


def add_bevel(obj: bpy.types.Object, width: float, segments: int = 3) -> None:
    modifier = obj.modifiers.new(name="EdgeBevel", type="BEVEL")
    modifier.width = width
    modifier.segments = segments


def tag(
    obj: bpy.types.Object,
    role: str,
    part: str,
    subject: bool,
) -> bpy.types.Object:
    obj["style_role"] = role
    obj["part_id"] = part
    obj["subject"] = subject
    return obj


def add_box(
    name: str,
    location: tuple[float, float, float],
    dimensions: tuple[float, float, float],
    material: bpy.types.Material,
    role: str,
    part: str,
    subject: bool = True,
    bevel: float = 0.06,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(location=location)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel > 0.0:
        add_bevel(obj, bevel)
    obj.data.materials.append(material)
    return tag(obj, role, part, subject)


def add_cylinder(
    name: str,
    location: tuple[float, float, float],
    radius: float,
    depth: float,
    rotation: tuple[float, float, float],
    material: bpy.types.Material,
    role: str,
    part: str,
    subject: bool = True,
    vertices: int = 24,
    bevel: float = 0.035,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=radius,
        depth=depth,
        location=location,
        rotation=rotation,
    )
    obj = bpy.context.object
    obj.name = name
    if bevel > 0.0:
        add_bevel(obj, bevel, 2)
    obj.data.materials.append(material)
    return tag(obj, role, part, subject)


def add_cone(
    name: str,
    location: tuple[float, float, float],
    radius: float,
    depth: float,
    rotation: tuple[float, float, float],
    material: bpy.types.Material,
    role: str,
    part: str,
    subject: bool = True,
    vertices: int = 4,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cone_add(
        vertices=vertices,
        radius1=radius,
        radius2=0.0,
        depth=depth,
        location=location,
        rotation=rotation,
    )
    obj = bpy.context.object
    obj.name = name
    add_bevel(obj, 0.018, 2)
    obj.data.materials.append(material)
    return tag(obj, role, part, subject)


def add_uv_sphere(
    name: str,
    location: tuple[float, float, float],
    scale: tuple[float, float, float],
    material: bpy.types.Material,
    role: str,
    part: str,
    subject: bool = True,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_ico_sphere_add(
        subdivisions=2,
        radius=1.0,
        location=location,
    )
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    add_bevel(obj, 0.025, 2)
    obj.data.materials.append(material)
    return tag(obj, role, part, subject)


def add_wedge(
    name: str,
    center: tuple[float, float, float],
    length: float,
    width: float,
    height: float,
    material: bpy.types.Material,
    role: str,
    part: str,
    subject: bool = True,
) -> bpy.types.Object:
    x = length * 0.5
    y = width * 0.5
    z = height * 0.5
    vertices = [
        (-x, -y, -z),
        (-x, y, -z),
        (-x, -y, z),
        (-x, y, z),
        (x, -y, -z),
        (x, y, -z),
        (x, -y, 0.0),
        (x, y, 0.0),
    ]
    faces = [
        (0, 4, 5, 1),
        (2, 3, 7, 6),
        (0, 2, 6, 4),
        (1, 5, 7, 3),
        (0, 1, 3, 2),
        (4, 6, 7, 5),
    ]
    mesh = bpy.data.meshes.new(f"{name}Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.location = center
    add_bevel(obj, 0.04, 2)
    obj.data.materials.append(material)
    return tag(obj, role, part, subject)


def add_bar_between(
    name: str,
    start: Vector,
    end: Vector,
    radius: float,
    material: bpy.types.Material,
    role: str,
    part: str,
    subject: bool = True,
) -> bpy.types.Object:
    midpoint = (start + end) * 0.5
    direction = end - start
    obj = add_cylinder(
        name,
        tuple(midpoint),
        radius,
        direction.length,
        (0.0, 0.0, 0.0),
        material,
        role,
        part,
        subject,
        vertices=16,
        bevel=0.018,
    )
    obj.rotation_euler = direction.to_track_quat("Z", "Y").to_euler()
    return obj


def build_materials(
    palette: dict[str, str],
    treatment: dict[str, Any],
) -> dict[str, bpy.types.Material]:
    metallic_scale = float(treatment["metallic_scale"])
    roughness_bias = float(treatment["roughness_bias"])

    def rough(base: float) -> float:
        return max(0.12, min(0.95, base + roughness_bias))

    return {
        "coal": make_principled(
            "Coal",
            hex_rgb(palette["coal"]),
            metallic_scale * 0.34,
            rough(0.68),
        ),
        "iron": make_principled(
            "Iron",
            hex_rgb(palette["iron"]),
            metallic_scale * 0.72,
            rough(0.56),
        ),
        "slate": make_principled(
            "Slate",
            hex_rgb(palette["slate"]),
            metallic_scale * 0.64,
            rough(0.48),
        ),
        "brass": make_principled(
            "Brass",
            hex_rgb(palette["brass"]),
            metallic_scale,
            rough(0.34),
        ),
        "bone": make_principled(
            "Bone",
            hex_rgb(palette["bone"]),
            metallic_scale * 0.08,
            rough(0.62),
        ),
        "ember": make_principled(
            "Ember",
            hex_rgb(palette["ember"]),
            metallic_scale * 0.12,
            rough(0.28),
            3.8,
        ),
        "flame": make_principled(
            "Flame",
            hex_rgb(palette["flame"]),
            metallic_scale * 0.08,
            rough(0.36),
            1.6,
        ),
        "cold_signal": make_principled(
            "ColdSignal",
            hex_rgb(palette["cold_signal"]),
            metallic_scale * 0.2,
            rough(0.38),
            1.2,
        ),
        "pursuer": make_principled(
            "PursuerRust",
            hex_rgb(palette["pursuer_rust"]),
            metallic_scale * 0.38,
            rough(0.52),
        ),
        "night": make_principled(
            "Night",
            hex_rgb(palette["night_void"]),
            0.0,
            0.92,
        ),
    }


def build_tracks(materials: dict[str, bpy.types.Material]) -> None:
    for y in (-0.56, 0.56):
        add_box(
            f"Rail_{y}",
            (0.0, y, 0.18),
            (31.0, 0.10, 0.13),
            materials["iron"],
            "iron",
            "rail",
            False,
            0.025,
        )
    for index in range(-21, 22):
        add_box(
            f"Sleeper_{index:02d}",
            (float(index) * 0.72, 0.0, 0.08),
            (0.34, 1.75, 0.12),
            materials["coal"],
            "coal",
            "sleeper",
            False,
            0.02,
        )


def build_locomotive(
    x: float,
    materials: dict[str, bpy.types.Material],
) -> None:
    add_box(
        "LocomotiveFrame",
        (x, 0.0, 0.72),
        (3.05, 1.20, 0.34),
        materials["iron"],
        "iron",
        "locomotive",
        bevel=0.09,
    )
    add_box(
        "LocomotiveCab",
        (x - 0.72, 0.0, 1.48),
        (1.05, 1.16, 1.48),
        materials["coal"],
        "coal",
        "locomotive",
        bevel=0.09,
    )
    add_box(
        "CabRoof",
        (x - 0.72, 0.0, 2.28),
        (1.30, 1.36, 0.18),
        materials["brass"],
        "brass",
        "locomotive_trim",
        bevel=0.07,
    )
    add_cylinder(
        "Boiler",
        (x + 0.55, 0.0, 1.48),
        0.58,
        1.95,
        (0.0, math.pi * 0.5, 0.0),
        materials["slate"],
        "slate",
        "locomotive",
        vertices=32,
        bevel=0.06,
    )
    for index, offset in enumerate((-0.10, 0.52, 1.12)):
        add_cylinder(
            f"BoilerBand_{index}",
            (x + offset, 0.0, 1.48),
            0.605,
            0.055,
            (0.0, math.pi * 0.5, 0.0),
            materials["brass"],
            "brass",
            "locomotive_trim",
            vertices=32,
            bevel=0.012,
        )
    add_cylinder(
        "BoilerFront",
        (x + 1.55, 0.0, 1.48),
        0.63,
        0.16,
        (0.0, math.pi * 0.5, 0.0),
        materials["iron"],
        "iron",
        "locomotive",
        vertices=32,
        bevel=0.04,
    )
    add_cylinder(
        "SmokeboxBand",
        (x + 1.635, 0.0, 1.48),
        0.64,
        0.045,
        (0.0, math.pi * 0.5, 0.0),
        materials["brass"],
        "brass",
        "locomotive_trim",
        vertices=32,
        bevel=0.012,
    )
    add_cylinder(
        "SmokeStackBase",
        (x + 0.36, 0.0, 2.18),
        0.20,
        0.42,
        (0.0, 0.0, 0.0),
        materials["iron"],
        "iron",
        "locomotive_mechanism",
        vertices=24,
    )
    add_cylinder(
        "SmokeStack",
        (x + 0.36, 0.0, 2.52),
        0.15,
        0.48,
        (0.0, 0.0, 0.0),
        materials["coal"],
        "coal",
        "locomotive_mechanism",
        vertices=24,
    )
    add_cylinder(
        "SmokeStackCap",
        (x + 0.36, 0.0, 2.78),
        0.25,
        0.10,
        (0.0, 0.0, 0.0),
        materials["brass"],
        "brass",
        "locomotive_trim",
        vertices=24,
    )
    for y in (-0.615, 0.615):
        for wheel_index, wheel_x in enumerate(
            (x - 0.86, x - 0.10, x + 0.72, x + 1.34)
        ):
            radius = 0.39 if wheel_index in (1, 2) else 0.31
            add_cylinder(
                f"LocomotiveWheel_{y}_{wheel_index}",
                (wheel_x, y, 0.47),
                radius,
                0.16,
                (math.pi * 0.5, 0.0, 0.0),
                materials["coal"],
                "coal",
                "wheel",
                vertices=24,
                bevel=0.025,
            )
            add_cylinder(
                f"LocomotiveHub_{y}_{wheel_index}",
                (wheel_x, y - 0.09 if y < 0 else y + 0.09, 0.47),
                radius * 0.36,
                0.035,
                (math.pi * 0.5, 0.0, 0.0),
                materials["brass"],
                "brass",
                "wheel_trim",
                vertices=18,
                bevel=0.01,
            )
    add_bar_between(
        "DriveRod",
        Vector((x - 0.86, -0.72, 0.47)),
        Vector((x + 1.34, -0.72, 0.47)),
        0.045,
        materials["brass"],
        "brass",
        "locomotive_mechanism",
    )
    add_box(
        "CabWindowFrame",
        (x - 0.80, -0.604, 1.68),
        (0.56, 0.035, 0.58),
        materials["brass"],
        "brass",
        "window_frame",
        bevel=0.035,
    )
    add_box(
        "CabWindow",
        (x - 0.80, -0.626, 1.68),
        (0.40, 0.025, 0.42),
        materials["ember"],
        "ember",
        "window",
        bevel=0.022,
    )
    add_cylinder(
        "HeadlightHousing",
        (x + 1.69, -0.02, 1.66),
        0.22,
        0.18,
        (0.0, math.pi * 0.5, 0.0),
        materials["brass"],
        "brass",
        "headlight",
        vertices=24,
    )
    add_cylinder(
        "HeadlightLens",
        (x + 1.80, -0.02, 1.66),
        0.15,
        0.05,
        (0.0, math.pi * 0.5, 0.0),
        materials["ember"],
        "ember",
        "headlight",
        vertices=24,
        bevel=0.015,
    )
    add_wedge(
        "Cowcatcher",
        (x + 1.78, 0.0, 0.67),
        0.62,
        1.15,
        0.68,
        materials["iron"],
        "iron",
        "locomotive",
    )
    for stripe in range(3):
        add_box(
            f"BrassStripe_{stripe}",
            (x - 0.15 + stripe * 0.55, -0.615, 1.02),
            (0.34, 0.035, 0.08),
            materials["brass"],
            "brass",
            "locomotive_trim",
            bevel=0.01,
        )
    add_box(
        "LocomotiveNameplate",
        (x + 0.52, -0.624, 1.54),
        (0.78, 0.035, 0.16),
        materials["brass"],
        "brass",
        "locomotive_trim",
        bevel=0.025,
    )
    add_box(
        "LocomotiveStep",
        (x - 0.76, -0.79, 0.88),
        (0.78, 0.32, 0.12),
        materials["iron"],
        "iron",
        "locomotive_mechanism",
        bevel=0.025,
    )


def build_defense_car(
    x: float,
    materials: dict[str, bpy.types.Material],
) -> None:
    add_box(
        "DefenseFrame",
        (x, 0.0, 0.66),
        (2.55, 1.16, 0.28),
        materials["iron"],
        "iron",
        "defense_car",
        bevel=0.07,
    )
    add_box(
        "DefenseBody",
        (x, 0.0, 1.20),
        (2.42, 1.08, 0.92),
        materials["coal"],
        "coal",
        "defense_car",
        bevel=0.08,
    )
    add_box(
        "DefenseDeck",
        (x, 0.0, 1.70),
        (2.22, 1.02, 0.13),
        materials["slate"],
        "slate",
        "defense_car",
        bevel=0.035,
    )
    add_box(
        "DefenseArmor",
        (x + 0.15, -0.56, 1.24),
        (1.72, 0.06, 0.54),
        materials["slate"],
        "slate",
        "defense_car",
        bevel=0.035,
    )
    for panel in range(4):
        add_box(
            f"DefenseRivetPanel_{panel}",
            (x - 0.78 + panel * 0.52, -0.60, 1.24),
            (0.38, 0.03, 0.42),
            materials["iron"],
            "iron",
            "defense_car",
            bevel=0.02,
        )
        add_box(
            f"DefensePanelBrace_{panel}",
            (x - 0.78 + panel * 0.52, -0.625, 1.24),
            (0.045, 0.025, 0.50),
            materials["brass"],
            "brass",
            "defense_trim",
            bevel=0.008,
        )
    for y in (-0.61, 0.61):
        for wheel_index, wheel_x in enumerate((x - 0.78, x + 0.78)):
            add_cylinder(
                f"DefenseWheel_{y}_{wheel_index}",
                (wheel_x, y, 0.44),
                0.31,
                0.16,
                (math.pi * 0.5, 0.0, 0.0),
                materials["coal"],
                "coal",
                "wheel",
                vertices=24,
            )
            add_cylinder(
                f"DefenseHub_{y}_{wheel_index}",
                (wheel_x, y - 0.09 if y < 0 else y + 0.09, 0.44),
                0.11,
                0.04,
                (math.pi * 0.5, 0.0, 0.0),
                materials["brass"],
                "brass",
                "wheel_trim",
                vertices=18,
            )
    add_cylinder(
        "CannonTurntable",
        (x + 0.18, 0.0, 1.82),
        0.54,
        0.22,
        (0.0, 0.0, 0.0),
        materials["brass"],
        "brass",
        "heavy_cannon",
        vertices=32,
    )
    add_cylinder(
        "CannonAmmoDrum",
        (x - 0.46, -0.20, 1.92),
        0.30,
        0.52,
        (math.pi * 0.5, 0.0, 0.0),
        materials["iron"],
        "iron",
        "heavy_cannon",
        vertices=24,
    )
    add_box(
        "CannonBreech",
        (x + 0.04, 0.0, 2.14),
        (1.18, 0.82, 0.78),
        materials["iron"],
        "iron",
        "heavy_cannon",
        bevel=0.09,
    )
    add_box(
        "CannonMantlet",
        (x + 0.55, -0.02, 2.17),
        (0.42, 0.90, 0.68),
        materials["brass"],
        "brass",
        "heavy_cannon",
        bevel=0.08,
    )
    barrel_start = Vector((x + 0.48, 0.0, 2.18))
    barrel_end = Vector((x + 1.72, 0.0, 2.18))
    barrel_direction = (barrel_end - barrel_start).normalized()
    add_bar_between(
        "CannonBarrel",
        barrel_start,
        barrel_end,
        0.25,
        materials["slate"],
        "slate",
        "heavy_cannon",
    )
    add_bar_between(
        "CannonMuzzle",
        barrel_end - barrel_direction * 0.18,
        barrel_end + barrel_direction * 0.18,
        0.39,
        materials["brass"],
        "brass",
        "heavy_cannon",
    )
    add_bar_between(
        "CannonMuzzleCap",
        barrel_end + barrel_direction * 0.14,
        barrel_end + barrel_direction * 0.36,
        0.31,
        materials["iron"],
        "iron",
        "heavy_cannon",
    )
    add_bar_between(
        "CannonRecoilCylinder",
        Vector((x + 0.26, -0.32, 1.94)),
        Vector((x + 1.16, -0.32, 1.94)),
        0.085,
        materials["brass"],
        "brass",
        "heavy_cannon",
    )
    add_box(
        "CannonShield",
        (x + 0.35, -0.42, 2.14),
        (0.86, 0.12, 0.52),
        materials["brass"],
        "brass",
        "heavy_cannon",
        bevel=0.06,
    )
    add_bar_between(
        "Coupling",
        Vector((x + 1.34, 0.0, 0.70)),
        Vector((x + 1.90, 0.0, 0.70)),
        0.07,
        materials["brass"],
        "brass",
        "coupling",
    )


def build_pursuer(
    x: float,
    materials: dict[str, bpy.types.Material],
) -> None:
    add_wedge(
        "PursuerChassis",
        (x - 0.08, -0.06, 0.82),
        1.52,
        0.76,
        0.46,
        materials["pursuer"],
        "pursuer_rust",
        "pursuer",
    )
    add_wedge(
        "PursuerRearCarapace",
        (x - 0.48, -0.02, 1.00),
        0.82,
        0.88,
        0.38,
        materials["iron"],
        "iron",
        "pursuer",
    )
    add_wedge(
        "PursuerHead",
        (x + 0.70, -0.10, 0.82),
        0.76,
        0.60,
        0.34,
        materials["pursuer"],
        "pursuer_rust",
        "pursuer",
    )
    add_uv_sphere(
        "PursuerEyeHousing",
        (x + 1.04, -0.41, 0.84),
        (0.17, 0.045, 0.17),
        materials["cold_signal"],
        "cold_signal",
        "pursuer_eye",
    )
    add_uv_sphere(
        "PursuerEye",
        (x + 1.04, -0.46, 0.84),
        (0.11, 0.07, 0.11),
        materials["ember"],
        "ember",
        "pursuer_eye",
    )
    legs = [
        (-0.66, -0.34, 0.72, -1.12, -0.68, 0.14, "near"),
        (-0.38, 0.25, 0.70, -0.74, 0.54, 0.15, "far"),
        (-0.10, -0.38, 0.69, -0.30, -0.75, 0.13, "near"),
        (0.18, 0.27, 0.70, 0.34, 0.58, 0.14, "far"),
        (0.46, -0.35, 0.71, 0.80, -0.70, 0.14, "near"),
        (0.72, 0.24, 0.72, 1.20, 0.54, 0.16, "far"),
    ]
    for index, values in enumerate(legs):
        hip = Vector((x + values[0], values[1], values[2]))
        foot = Vector((x + values[3], values[4], values[5]))
        near = values[6] == "near"
        upper_material = materials["pursuer"] if near else materials["iron"]
        upper_role = "pursuer_rust" if near else "iron"
        add_bar_between(
            f"PursuerLeg_{index}",
            hip,
            foot,
            0.060 if near else 0.052,
            upper_material,
            upper_role,
            "pursuer_leg",
        )
        claw_direction = 0.16 if index >= 3 else -0.16
        toe = foot + Vector((claw_direction, 0.0, -0.03))
        add_bar_between(
            f"PursuerRailClaw_{index}",
            foot,
            toe,
            0.035,
            materials["brass"] if near else materials["slate"],
            "brass" if near else "slate",
            "pursuer_leg",
        )
    add_bar_between(
        "PursuerSpine",
        Vector((x - 0.68, -0.10, 1.08)),
        Vector((x + 0.52, -0.10, 1.10)),
        0.055,
        materials["cold_signal"],
        "cold_signal",
        "pursuer_trim",
    )
    for index, spike_x in enumerate((-0.48, -0.05, 0.37)):
        add_cone(
            f"PursuerDorsalSpike_{index}",
            (x + spike_x, -0.08, 1.22),
            0.12,
            0.34,
            (0.0, 0.0, 0.0),
            materials["brass"],
            "brass",
            "pursuer_trim",
            vertices=4,
        )
    add_bar_between(
        "PursuerUpperJaw",
        Vector((x + 0.82, -0.28, 0.88)),
        Vector((x + 1.30, -0.28, 0.93)),
        0.045,
        materials["iron"],
        "iron",
        "pursuer_jaw",
    )
    add_bar_between(
        "PursuerLowerJaw",
        Vector((x + 0.82, -0.30, 0.73)),
        Vector((x + 1.22, -0.30, 0.64)),
        0.038,
        materials["brass"],
        "brass",
        "pursuer_jaw",
    )
    add_bar_between(
        "PursuerTailHook",
        Vector((x - 0.82, -0.08, 0.86)),
        Vector((x - 1.18, -0.08, 1.06)),
        0.045,
        materials["cold_signal"],
        "cold_signal",
        "pursuer_trim",
    )


def build_dead_signal(
    x: float,
    materials: dict[str, bpy.types.Material],
) -> None:
    add_box(
        "SignalPost",
        (x, 1.55, 1.58),
        (0.18, 0.18, 3.0),
        materials["coal"],
        "coal",
        "dead_signal",
        False,
        0.025,
    )
    add_box(
        "SignalCrossbar",
        (x, 1.55, 2.58),
        (1.18, 0.18, 0.15),
        materials["iron"],
        "iron",
        "dead_signal",
        False,
        0.025,
    )
    add_cylinder(
        "SignalLensDead",
        (x + 0.34, 1.43, 2.37),
        0.18,
        0.12,
        (math.pi * 0.5, 0.0, 0.0),
        materials["cold_signal"],
        "cold_signal",
        "dead_signal",
        False,
        vertices=20,
    )
    add_bar_between(
        "SignalArm",
        Vector((x - 0.05, 1.48, 2.54)),
        Vector((x + 0.82, 1.48, 2.92)),
        0.07,
        materials["brass"],
        "brass",
        "dead_signal",
        False,
    )
    add_box(
        "SignalBase",
        (x, 1.55, 0.28),
        (0.66, 0.54, 0.24),
        materials["iron"],
        "iron",
        "dead_signal",
        False,
        0.035,
    )
    for index in range(5):
        add_box(
            f"SignalLadder_{index}",
            (x - 0.18, 1.43, 0.72 + index * 0.31),
            (0.32, 0.045, 0.045),
            materials["slate"],
            "slate",
            "dead_signal",
            False,
            0.008,
        )


def build_environment(
    materials: dict[str, bpy.types.Material],
    separation: float,
) -> None:
    background_iron = materials["iron"].copy()
    background_iron.name = "BackgroundIron"
    node = background_iron.node_tree.nodes.get("Principled BSDF")
    base = Vector(hex_rgb("#202A36")[:3])
    adjusted = tuple(min(1.0, value * (0.7 + separation)) for value in base)
    node.inputs["Base Color"].default_value = (*adjusted, 1.0)
    background_slate = materials["slate"].copy()
    background_slate.name = "BackgroundSlate"
    slate_node = background_slate.node_tree.nodes.get("Principled BSDF")
    slate_base = Vector(hex_rgb("#354455")[:3])
    slate_adjusted = tuple(
        min(1.0, value * (0.58 + separation * 0.78))
        for value in slate_base
    )
    slate_node.inputs["Base Color"].default_value = (*slate_adjusted, 1.0)
    for index in range(13):
        x = -13.2 + index * 2.2
        height = 1.5 + float((index * 7) % 6) * 0.46
        add_box(
            f"FarRuin_{index}",
            (x, 5.4 + float(index % 2) * 0.35, height * 0.5),
            (0.72 + float(index % 3) * 0.34, 0.32, height),
            background_iron,
            "iron",
            "far_environment",
            False,
            0.025,
        )
        if index % 3 == 1:
            add_cone(
                f"FarRuinRoof_{index}",
                (x, 5.4 + float(index % 2) * 0.35, height + 0.30),
                0.42,
                0.60,
                (0.0, 0.0, 0.0),
                background_iron,
                "iron",
                "far_environment",
                False,
                vertices=4,
            )
    for index in range(9):
        x = -11.6 + index * 2.8
        height = 0.9 + float((index * 5) % 4) * 0.42
        add_box(
            f"MidRuin_{index}",
            (x, 2.9 + float(index % 2) * 0.28, height * 0.5),
            (0.92 + float(index % 3) * 0.24, 0.42, height),
            background_slate,
            "slate",
            "mid_environment",
            False,
            0.035,
        )
    add_box(
        "CollapsedStationPostLeft",
        (-8.7, 2.4, 1.35),
        (0.34, 0.42, 2.7),
        background_slate,
        "slate",
        "mid_environment",
        False,
        0.035,
    )
    add_box(
        "CollapsedStationPostRight",
        (-6.5, 2.4, 1.08),
        (0.34, 0.42, 2.16),
        background_slate,
        "slate",
        "mid_environment",
        False,
        0.035,
    )
    station_beam = add_box(
        "CollapsedStationBeam",
        (-7.62, 2.4, 2.32),
        (2.50, 0.38, 0.24),
        background_slate,
        "slate",
        "mid_environment",
        False,
        0.025,
    )
    station_beam.rotation_euler.y = math.radians(-8.0)
    for index in range(8):
        add_wedge(
            f"NearDebris_{index}",
            (-12.0 + index * 3.4, 1.25, 0.22),
            0.64 + float(index % 3) * 0.14,
            0.52,
            0.34 + float(index % 2) * 0.12,
            materials["coal"],
            "coal",
            "near_environment",
            False,
        )


def build_scene(
    config: dict[str, Any],
    treatment: dict[str, Any],
) -> tuple[bpy.types.Scene, dict[str, bpy.types.Material]]:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    random.seed(int(config["seed"]))
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.film_transparent = False
    scene.render.use_file_extension = True
    scene.render.image_settings.compression = 100
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 720
    try:
        scene.view_settings.look = "AgX - Medium High Contrast"
    except TypeError:
        pass
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.exposure = 0.0
    scene.view_settings.gamma = 1.0

    materials = build_materials(config["palette"], treatment)
    build_tracks(materials)
    composition = config["composition"]
    build_locomotive(float(composition["locomotive_x"]), materials)
    build_defense_car(float(composition["defense_car_x"]), materials)
    build_pursuer(float(composition["pursuer_x"]), materials)
    build_dead_signal(float(composition["signal_x"]), materials)
    build_environment(materials, float(treatment["background_separation"]))

    bpy.ops.object.light_add(type="AREA", location=(2.8, -4.8, 7.0))
    key = bpy.context.object
    key.name = "CoalKey"
    key.data.energy = float(treatment["key_energy"])
    key.data.color = (0.92, 0.58, 0.31)
    key.data.shape = "RECTANGLE"
    key.data.size = 5.5
    key.data.size_y = 3.2
    point_at(key, Vector((0.2, 0.0, 1.0)))

    bpy.ops.object.light_add(type="AREA", location=(-4.5, 3.5, 5.2))
    rim = bpy.context.object
    rim.name = "EmberRim"
    rim.data.energy = float(treatment["rim_energy"])
    rim.data.color = (0.34, 0.58, 0.80)
    rim.data.shape = "DISK"
    rim.data.size = 4.2
    point_at(rim, Vector((-0.2, 0.0, 1.2)))

    bpy.ops.object.light_add(type="POINT", location=(2.55, -0.2, 1.72))
    lamp = bpy.context.object
    lamp.name = "HeadlightGlow"
    lamp.data.energy = 175.0
    lamp.data.color = (1.0, 0.46, 0.18)
    lamp.data.shadow_soft_size = 1.1

    world = bpy.data.worlds.new("StyleWorld")
    world.use_nodes = True
    background = world.node_tree.nodes.get("Background")
    background.inputs["Color"].default_value = hex_rgb(
        config["palette"]["night_void"]
    )
    background.inputs["Strength"].default_value = float(
        treatment["fill_strength"]
    )
    scene.world = world

    camera_config = config["camera"]
    pitch = math.radians(float(treatment["camera_pitch_degrees"]))
    target = Vector(camera_config["target"])
    distance = float(camera_config["distance"])
    camera_location = target + Vector(
        (0.0, -distance * math.cos(pitch), distance * math.sin(pitch))
    )
    bpy.ops.object.camera_add(location=camera_location)
    camera = bpy.context.object
    camera.name = "GameplayOrthoCamera"
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = float(camera_config["ortho_scale"])
    camera.data.sensor_fit = "VERTICAL"
    point_at(camera, target)
    scene.camera = camera
    return scene, materials


def set_resolution(scene: bpy.types.Scene, size: list[int]) -> None:
    scene.render.resolution_x = int(size[0])
    scene.render.resolution_y = int(size[1])
    scene.render.resolution_percentage = 100


def set_palette_variant(
    config: dict[str, Any],
    materials: dict[str, bpy.types.Material],
    variant: str,
) -> None:
    if variant == "default":
        for material in materials.values():
            node = material.node_tree.nodes.get("Principled BSDF")
            if node is None:
                continue
            node.inputs["Base Color"].default_value = material["base_color"]
            node.inputs["Metallic"].default_value = float(
                material["base_metallic"]
            )
            node.inputs["Roughness"].default_value = float(
                material["base_roughness"]
            )
        return

    dark_roles = {"coal", "iron", "night"}
    bright_roles = {"brass", "bone", "ember", "flame", "cold_signal", "pursuer"}
    for role, material in materials.items():
        node = material.node_tree.nodes.get("Principled BSDF")
        if node is None:
            continue
        color = list(material["base_color"])
        if role in dark_roles:
            color[:3] = [max(0.0, value * 0.55) for value in color[:3]]
        elif role in bright_roles:
            color[:3] = [min(1.0, value * 1.28 + 0.04) for value in color[:3]]
        node.inputs["Base Color"].default_value = color
        node.inputs["Roughness"].default_value = min(
            0.95,
            float(material["base_roughness"]) + 0.08,
        )


def render_image(
    scene: bpy.types.Scene,
    path: Path,
    size: list[int],
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    set_resolution(scene, size)
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


def snapshot_object_state() -> dict[str, Any]:
    snapshot: dict[str, Any] = {}
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH":
            continue
        snapshot[obj.name] = {
            "hide_render": obj.hide_render,
            "materials": list(obj.data.materials),
        }
    return snapshot


def restore_object_state(snapshot: dict[str, Any]) -> None:
    for name, state in snapshot.items():
        obj = bpy.data.objects.get(name)
        if obj is None:
            continue
        obj.hide_render = bool(state["hide_render"])
        obj.data.materials.clear()
        for material in state["materials"]:
            obj.data.materials.append(material)


def hide_lights(hidden: bool) -> None:
    for obj in bpy.context.scene.objects:
        if obj.type == "LIGHT":
            obj.hide_render = hidden


def render_flat_pass(
    scene: bpy.types.Scene,
    path: Path,
    mode: str,
    palette: dict[str, str],
    size: list[int] | None = None,
) -> None:
    state = snapshot_object_state()
    world = scene.world
    background = world.node_tree.nodes.get("Background")
    background_color = tuple(background.inputs["Color"].default_value)
    background_strength = float(background.inputs["Strength"].default_value)
    hide_lights(True)
    background.inputs["Strength"].default_value = 1.0

    flat_materials: dict[str, bpy.types.Material] = {}
    role_colors = {
        "coal": palette["coal"],
        "iron": palette["iron"],
        "slate": palette["slate"],
        "brass": palette["brass"],
        "bone": palette["bone"],
        "ember": palette["ember"],
        "flame": palette["flame"],
        "cold_signal": palette["cold_signal"],
        "pursuer_rust": palette["pursuer_rust"],
        "night": palette["night_void"],
    }

    if mode == "silhouette":
        background.inputs["Color"].default_value = hex_rgb(palette["bone"])
        flat_materials["all"] = make_emission(
            "SilhouettePass",
            hex_rgb(palette["coal"]),
        )
    elif mode == "normal":
        background.inputs["Color"].default_value = (0.5, 0.5, 1.0, 1.0)
        material = bpy.data.materials.new("NormalPass")
        material.use_nodes = True
        nodes = material.node_tree.nodes
        links = material.node_tree.links
        nodes.clear()
        output = nodes.new("ShaderNodeOutputMaterial")
        geometry = nodes.new("ShaderNodeNewGeometry")
        multiply = nodes.new("ShaderNodeVectorMath")
        multiply.operation = "SCALE"
        multiply.inputs["Scale"].default_value = 0.5
        add = nodes.new("ShaderNodeVectorMath")
        add.operation = "ADD"
        add.inputs[1].default_value = (0.5, 0.5, 0.5)
        emission = nodes.new("ShaderNodeEmission")
        links.new(geometry.outputs["Normal"], multiply.inputs[0])
        links.new(multiply.outputs[0], add.inputs[0])
        links.new(add.outputs[0], emission.inputs["Color"])
        links.new(emission.outputs["Emission"], output.inputs["Surface"])
        flat_materials["all"] = material
    elif mode == "subject_mask":
        background.inputs["Color"].default_value = hex_rgb(
            palette["night_void"]
        )
        flat_materials["train"] = make_emission(
            "SubjectMaskTrain",
            hex_rgb(palette["brass"]),
        )
        flat_materials["pursuer"] = make_emission(
            "SubjectMaskPursuer",
            hex_rgb(palette["pursuer_rust"]),
        )
    else:
        background.inputs["Color"].default_value = hex_rgb(
            palette["night_void"]
        )
        part_colors = [
            "#D6A04F",
            "#6CA6C6",
            "#A94C44",
            "#7EA36B",
            "#7C3C78",
            "#DF6438",
            "#E8DFC6",
            "#354455",
        ]
        for index, color in enumerate(part_colors):
            flat_materials[str(index)] = make_emission(
                f"MaskPass{index}",
                hex_rgb(color),
            )

    for obj in scene.objects:
        if obj.type != "MESH":
            continue
        if not bool(obj.get("subject", False)):
            obj.hide_render = True
            continue
        obj.data.materials.clear()
        if mode in {"silhouette", "normal"}:
            obj.data.materials.append(flat_materials["all"])
        elif mode == "subject_mask":
            part = str(obj.get("part_id", ""))
            key = "pursuer" if part.startswith("pursuer") else "train"
            obj.data.materials.append(flat_materials[key])
        elif mode == "material":
            role = str(obj.get("style_role", "coal"))
            if role not in flat_materials:
                flat_materials[role] = make_emission(
                    f"MaterialPass_{role}",
                    hex_rgb(role_colors.get(role, palette["coal"])),
                )
            obj.data.materials.append(flat_materials[role])
        else:
            part = str(obj.get("part_id", "part"))
            index = sum(ord(char) for char in part) % len(flat_materials)
            obj.data.materials.append(flat_materials[str(index)])

    render_image(scene, path, size or [1280, 720])
    restore_object_state(state)
    hide_lights(False)
    background.inputs["Color"].default_value = background_color
    background.inputs["Strength"].default_value = background_strength


def scene_metadata(
    scene: bpy.types.Scene,
    treatment: dict[str, Any],
    engine: str,
    config: dict[str, Any],
) -> dict[str, Any]:
    mesh_objects = [obj for obj in scene.objects if obj.type == "MESH"]
    vertices = sum(len(obj.data.vertices) for obj in mesh_objects)
    polygons = sum(len(obj.data.polygons) for obj in mesh_objects)
    anchors: dict[str, dict[str, list[float]]] = {}
    composition = config["composition"]
    world_anchors = {
        "headlight": Vector(
            (
                float(composition["locomotive_x"]) + 1.80,
                -0.02,
                1.66,
            )
        ),
        "track": Vector((0.0, 0.0, 0.18)),
        "signal_lens": Vector(
            (
                float(composition["signal_x"]) + 0.34,
                1.43,
                2.37,
            )
        ),
    }
    for size_name, size in config["sizes"].items():
        set_resolution(scene, size)
        anchors[size_name] = {}
        for anchor_name, world_position in world_anchors.items():
            coordinate = world_to_camera_view(
                scene,
                scene.camera,
                world_position,
            )
            anchors[size_name][anchor_name] = [
                round(float(coordinate.x), 8),
                round(float(1.0 - coordinate.y), 8),
            ]
    return {
        "blender_version": bpy.app.version_string,
        "engine": engine,
        "treatment": treatment,
        "mesh_objects": len(mesh_objects),
        "vertices": vertices,
        "polygons": polygons,
        "camera": {
            "location": list(scene.camera.location),
            "rotation_euler": list(scene.camera.rotation_euler),
            "ortho_scale": scene.camera.data.ortho_scale,
        },
        "screen_anchors": anchors,
    }


def main() -> None:
    args = parse_args()
    config_path = Path(args.config).resolve()
    output_root = Path(args.output_root).resolve()
    config = json.loads(config_path.read_text(encoding="utf-8"))
    treatment = next(
        item
        for item in config["treatments"]
        if item["id"] == args.treatment
    )
    scene, materials = build_scene(config, treatment)
    if args.engine == "canonical":
        scene.render.engine = "CYCLES"
        scene.cycles.device = "CPU"
        scene.cycles.samples = 12
        scene.cycles.use_denoising = True
        scene.cycles.max_bounces = 4
        scene.cycles.diffuse_bounces = 2
        scene.cycles.glossy_bounces = 2
        scene.cycles.transparent_max_bounces = 2
        scene.render.image_settings.compression = 100

    treatment_root = output_root / args.treatment / args.engine
    blend_path = treatment_root / "source" / f"{args.treatment}.blend"
    blend_path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))

    for variant in ("default", "high_contrast"):
        set_palette_variant(config, materials, variant)
        for size_name in ("desktop", "mobile"):
            output = treatment_root / "raw" / variant / f"{size_name}.png"
            render_image(scene, output, config["sizes"][size_name])

    set_palette_variant(config, materials, "default")
    for pass_name in (
        "silhouette",
        "material",
        "normal",
        "part_mask",
        "subject_mask",
    ):
        render_flat_pass(
            scene,
            treatment_root / "raw" / "passes" / f"{pass_name}.png",
            pass_name,
            config["palette"],
        )
    render_flat_pass(
        scene,
        treatment_root / "raw" / "passes" / "subject_mask_mobile.png",
        "subject_mask",
        config["palette"],
        config["sizes"]["mobile"],
    )

    metadata_path = treatment_root / "metadata.json"
    metadata_path.write_text(
        json.dumps(
            scene_metadata(scene, treatment, args.engine, config),
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )
    print(
        "[style-lock-blender] "
        f"treatment={args.treatment} engine={args.engine} "
        f"output={treatment_root}"
    )


if __name__ == "__main__":
    main()
