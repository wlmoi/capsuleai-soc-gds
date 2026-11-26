"""Export selected physical layers for interactive viewing in Tiny Tapeout Explorer."""
from pathlib import Path

import klayout.db as kdb

from floorplan import BOUNDARY, OUTPUT, read_layout, verify

EXPLORER = Path("gds/capsoc_explorer.oas")
STD_CELL_METAL = kdb.LayerInfo(8, 0)
STD_CELL_LABELS = kdb.LayerInfo(8, 25)
SRAM_LAYERS = [kdb.LayerInfo(layer, 0) for layer in (10, 30, 50)]
ROW_SAMPLE_STEP = 24


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
            copy_layer(cell, target, STD_CELL_METAL, representative=True)
        else:
            for layer in SRAM_LAYERS:
                copy_layer(cell, target, layer, representative=kind == "sram_detail")
            if kind == "sram":
                for instance in cell.each_inst():
                    child = copy_master(instance.cell, "sram_detail")
                    if not child.is_empty():
                        put_instance(target, instance, child)
        return target

    def expose_viewer_supply_pins(top, region):
        # The official Explorer requires top-level supply labels to show any geometry.
        # Lift the two existing pin shapes and labels from one sampled cell. This
        # creates no power network and only applies to the separate viewer model.
        instance = next(region.cell.each_inst())
        transform = region.trans * instance.trans
        labels = instance.cell.shapes(source.layer(STD_CELL_LABELS))
        conductor = instance.cell.shapes(source.layer(STD_CELL_METAL))
        pins = {}
        for shape in labels.each():
            if shape.is_text() and shape.text.string in {"VDD", "VSS"}:
                pin = shape.text
                point = pin.trans.disp
                metal = next(
                    polygon.polygon for polygon in conductor.each()
                    if polygon.bbox().contains(point) and polygon.polygon.inside(point)
                )
                pins[pin.string] = pin.transformed(transform), metal.transformed(transform)
        if pins.keys() != {"VDD", "VSS"}:
            raise ValueError("The reference standard cell does not have both supply pins")
        for label, metal in pins.values():
            top.shapes(output.layer(STD_CELL_LABELS)).insert(label)
            top.shapes(output.layer(STD_CELL_METAL)).insert(metal)

    original = source.top_cell()
    top = output.create_cell(original.name)
    logic_counts = {}
    copy_layer(original, top, BOUNDARY)
    for instance in original.each_inst():
        cell = instance.cell
        if cell.name.startswith("logic_"):
            block = output.create_cell(cell.name)
            block.shapes(output.layer(BOUNDARY)).insert(cell.bbox())
            count = 0
            for number, stdcell in enumerate(cell.each_inst()):
                if number % ROW_SAMPLE_STEP == 0:
                    put_instance(block, stdcell, copy_master(stdcell.cell, "stdcell"))
                    count += 1
            logic_counts[cell.name.removeprefix("logic_")] = count
        else:
            block = copy_master(cell, "sram")
        put_instance(top, instance, block)
    expose_viewer_supply_pins(
        top, next(instance for instance in original.each_inst() if instance.cell.name == "logic_soc_control")
    )
    for cell in list(output.top_cells()):
        if cell != top and cell.is_empty():
            output.delete_cell(cell.cell_index())
    options = kdb.SaveLayoutOptions()
    options.set_format_from_filename(str(EXPLORER))
    options.oasis_compression_level = 0
    output.write(str(EXPLORER), options)
    verify(EXPLORER, sampled_logic_counts=logic_counts)


if __name__ == "__main__":
    export()
