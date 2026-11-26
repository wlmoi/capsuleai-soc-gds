"""Render selected GDSII layers as registered transparent images for the web viewer."""
from pathlib import Path
from tempfile import TemporaryDirectory

import klayout.db as kdb
import klayout.lay as klay
from PIL import Image

from floorplan import OUTPUT

DESTINATION = Path("layout/layers")
LAYERS = (
    ("active", 1, "#ac8de7"),
    ("poly", 5, "#ec8bc1"),
    ("metal1", 8, "#7db8ff"),
    ("metal2", 10, "#56dbc1"),
    ("metal3", 30, "#f0bd6b"),
    ("metal4", 50, "#d1e4ff"),
)


def render_layers():
    DESTINATION.mkdir(parents=True, exist_ok=True)
    view = klay.LayoutView()
    view.set_config("background-color", "#000000")
    view.set_config("grid-visible", "false")
    view.set_config("text-visible", "false")
    view.commit_config()
    view.load_layout(str(OUTPUT), False)
    view.max_hier()
    bounds = view.active_cellview().cell.dbbox()
    target = kdb.DBox(bounds.left - 40, bounds.bottom - 40, bounds.right + 40, bounds.top + 40)
    alpha_lookup = [round(255 * (value / 255) ** 0.85) for value in range(256)]

    with TemporaryDirectory() as scratch:
        for name, layer_number, color in LAYERS:
            view.clear_layers()
            properties = klay.LayerProperties()
            properties.source = f"{layer_number}/0@1"
            properties.name = name
            properties.fill_color = properties.frame_color = 0xFFFFFF
            properties.dither_pattern = 0
            view.insert_layer(view.end_layers(), properties)
            mask = Path(scratch) / f"{name}.png"
            view.save_image_with_options(str(mask), 1440, 1008, 1, 2, 0.5, target)
            with Image.open(mask) as rendered:
                coverage = rendered.convert("L").point(alpha_lookup)
                if coverage.getextrema()[0] != 0 or coverage.getextrema()[1] < 128:
                    raise ValueError(f"Unexpected raster for {name}: {coverage.getextrema()}")
                image = Image.new("RGBA", rendered.size, color)
                image.putalpha(coverage)
                image.save(DESTINATION / f"{name}.png", optimize=True)


if __name__ == "__main__":
    render_layers()
