"""Render the committed GDS in KLayout using a fixed engineering palette."""
from pathlib import Path

import klayout.db as kdb
import klayout.lay as klay

from floorplan import OUTPUT


def render():
    view = klay.LayoutView()
    view.set_config("background-color", "#09111e")
    view.set_config("grid-visible", "false")
    view.set_config("text-visible", "false")
    view.commit_config()
    view.load_layout(str(OUTPUT), False)
    view.max_hier()
    view.clear_layers()
    layers = [
        ("Active", 1, 0, 0x465779, 0),
        ("Poly", 5, 0, 0x815d8e, 0),
        ("Metal1", 8, 0, 0x366eaa, 0),
        ("Metal2", 10, 0, 0x4aaca6, 0),
        ("Metal3", 30, 0, 0xd6a253, 0),
        ("Metal4", 50, 0, 0x90b8e1, 0),
        ("Boundary", 189, 4, 0x6b809f, 1),
    ]
    for name, gds_layer, datatype, color, pattern in layers:
        node = klay.LayerProperties()
        node.source = f"{gds_layer}/{datatype}@1"
        node.name = name
        node.fill_color = color
        node.frame_color = color
        node.dither_pattern = pattern
        view.insert_layer(view.end_layers(), node)
    bbox = view.active_cellview().cell.dbbox()
    target = kdb.DBox(bbox.left - 40, bbox.bottom - 40, bbox.right + 40, bbox.top + 40)
    view.save_image_with_options(str(Path("layout/preview.png")), 1440, 1008, 1, 2, 0.5, target)
    view.save_layer_props(str(Path("layout/sg13g2-preview.lyp")))


if __name__ == "__main__":
    render()
