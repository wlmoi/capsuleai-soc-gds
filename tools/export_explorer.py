"""Export selected physical layers for interactive viewing in Tiny Tapeout Explorer."""
from pathlib import Path

import klayout.db as kdb

from floorplan import BOUNDARY, OUTPUT, read_layout, verify

EXPLORER = Path("gds/capsoc_explorer.oas")
METAL1 = kdb.LayerInfo(8, 0)
SRAM_LAYERS = [kdb.LayerInfo(layer, 0) for layer in (10, 30, 50)]


def export():
    source = read_layout(OUTPUT)
    output = kdb.Layout()
    output.dbu = source.dbu
    masters = {}

    def copy_layer(cell, target, layer, representative=False):
        shapes = cell.shapes(source.layer(layer))
        if representative:
            largest = max(shapes.each(), key=lambda shape: shape.bbox().area(), default=None)
            if largest is not None:
                target.shapes(output.layer(layer)).insert(largest)
        else:
            target.shapes(output.layer(layer)).insert(shapes)

    def put_instance(target, instance, cell):
        placement = instance.cell_inst
        placement.cell_index = cell.cell_index()
        target.insert(placement)

    def copy_master(cell, kind):
        key = (cell.cell_index(), kind)
        if key in masters:
            return masters[key]
        target = output.create_cell(cell.name)
        masters[key] = target
        if kind in ("sram", "stdcell"):
            copy_layer(cell, target, BOUNDARY)
        if kind == "stdcell":
            copy_layer(cell, target, METAL1, representative=True)
        else:
            for layer in SRAM_LAYERS:
                copy_layer(cell, target, layer)
            if kind == "sram":
                for instance in cell.each_inst():
                    child = copy_master(instance.cell, "sram_detail")
                    if not child.is_empty():
                        put_instance(target, instance, child)
        return target

    original = source.top_cell()
    top = output.create_cell(original.name)
    copy_layer(original, top, BOUNDARY)
    for instance in original.each_inst():
        cell = instance.cell
        if cell.name.startswith("logic_"):
            block = output.create_cell(cell.name)
            for stdcell in cell.each_inst():
                put_instance(block, stdcell, copy_master(stdcell.cell, "stdcell"))
        else:
            block = copy_master(cell, "sram")
        put_instance(top, instance, block)
    for cell in list(output.top_cells()):
        if cell != top and cell.is_empty():
            output.delete_cell(cell.cell_index())
    options = kdb.SaveLayoutOptions()
    options.set_format_from_filename(str(EXPLORER))
    options.oasis_compression_level = 0
    output.write(str(EXPLORER), options)
    verify(EXPLORER)


if __name__ == "__main__":
    export()
