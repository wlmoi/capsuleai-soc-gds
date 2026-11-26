"""Build a placement-only GDS from mapped CapsuleAI logic and IHP SRAM views."""
import argparse
from collections import Counter
from itertools import combinations
import json
from pathlib import Path
import re

import klayout.db as kdb

SPEC = Path("layout/floorplan.json")
PDK = Path("build/pdk")
NETLIST = Path("build/capsoc_mapped.json")
OUTPUT = Path("gds/capsoc_floorplan.gds")
OASIS = Path("gds/capsoc_floorplan.oas")
MANIFEST = Path("layout/placement.json")
BOUNDARY = kdb.LayerInfo(189, 4)
DBU = 0.001
SITE_X = 480
ROW_Y = 3780
MEMORY_STUBS = {"act_mem", "wrom_m", "qrom_m", "sram32"}


def db_units(value):
    return round(value / DBU)


def lef_sizes(file):
    return {
        name: (db_units(float(width)), db_units(float(height)))
        for name, width, height in re.findall(
            r"^MACRO (\S+).*?^\s+SIZE ([\d.]+) BY ([\d.]+)\s*;",
            file.read_text(), re.MULTILINE | re.DOTALL
        )
    }


def read_layout(file):
    layout = kdb.Layout()
    layout.read(str(file))
    if layout.dbu != DBU:
        raise ValueError(f"{file}: expected {DBU} µm per database unit")
    return layout


def check_disjoint(named_boxes, die):
    for name, box in named_boxes:
        if not box.inside(die):
            raise ValueError(f"{name} is outside the die: {box}")
    for (left, a), (right, b) in combinations(named_boxes, 2):
        if a.overlaps(b):
            raise ValueError(f"{left} overlaps {right}")


def load_std_cells(layout, cells):
    source = read_layout(PDK / "sg13g2_stdcell.gds")
    masters = {}
    for master in sorted({master for group in cells.values() for _, master in group}):
        cell = source.cell(master)
        if cell is None or cell.is_empty():
            raise ValueError(f"Missing GDS geometry for {master}")
        masters[master] = layout.create_cell(master)
        masters[master].copy_tree(cell)
    return masters


def grouped_cells():
    mapped = json.loads(NETLIST.read_text())["modules"]["capsoc_top"]["cells"]
    groups = {"soc_control": [], "picorv32": [], "cnn_engine": []}
    stubs = {}
    for instance, cell in sorted(mapped.items()):
        master = cell["type"]
        if master in MEMORY_STUBS:
            stubs[instance] = master
            continue
        if not master.startswith("sg13g2_"):
            raise ValueError(f"Unexpected unmapped instance {instance}: {master}")
        path = instance.removeprefix("$flatten\\")
        if path.startswith("u_cpu."):
            group = "picorv32"
        elif path.startswith("u_eng."):
            group = "cnn_engine"
        else:
            group = "soc_control"
        groups[group].append((instance, master))
    if set(stubs.values()) != MEMORY_STUBS or not all(groups.values()):
        raise ValueError("Expected four memory stubs and mapped logic in each region")
    return groups, stubs


def place_logic(layout, top, spec, groups):
    sizes = lef_sizes(PDK / "sg13g2_stdcell.lef")
    masters = load_std_cells(layout, groups)
    regions = {}
    for group, cells in groups.items():
        left, bottom, right, limit = map(db_units, spec["logic_regions"][group])
        left = (left + SITE_X - 1) // SITE_X * SITE_X
        bottom = (bottom + ROW_Y - 1) // ROW_Y * ROW_Y
        dest = layout.create_cell(f"logic_{group}")
        top.insert(kdb.CellInstArray(dest.cell_index(), kdb.Trans(left, bottom)))
        row = x = gates_area = 0
        for _, name in cells:
            width, height = sizes[name]
            if height != ROW_Y or width % SITE_X:
                raise ValueError(f"Unexpected site dimensions for {name}")
            if left + x + width > right:
                row += 1
                x = 0
            if bottom + (row + 1) * ROW_Y > limit:
                raise ValueError(f"Placement region is too small for {group}")
            orient = kdb.Trans.M0 if row % 2 else kdb.Trans.R0
            y = (row + row % 2) * ROW_Y
            dest.insert(kdb.CellInstArray(masters[name].cell_index(), kdb.Trans(orient, x, y)))
            x += width
            gates_area += width * height
        regions[group] = {
            "instances": len(cells),
            "stdcell_lef_area_um2": round(gates_area * DBU**2, 3),
            "rows_used": row + 1,
            "region_um": spec["logic_regions"][group],
        }
    return regions


def place_sram(layout, top, spec):
    placed = []
    masters = {}
    for group in spec["sram_groups"]:
        master = group["master"]
        if master not in masters:
            source = read_layout(PDK / f"{master}.gds")
            cell = source.cell(master)
            if cell is None or cell.is_empty():
                raise ValueError(f"Missing GDS geometry for {master}")
            target = layout.create_cell(master)
            target.copy_tree(cell)
            masters[master] = target, lef_sizes(PDK / f"{master}.lef")[master]
        macro, (width, height) = masters[master]
        for number in range(group["count"]):
            row, column = divmod(number, group["columns"])
            ox, oy = group["origin_um"]
            px, py = group["pitch_um"]
            x, y = db_units(ox + column * px), db_units(oy + row * py)
            options = group["row_orientations"]
            orientation = options[row % len(options)]
            transform = {
                "N": kdb.Trans(kdb.Trans.R0, x, y),
                "FS": kdb.Trans(kdb.Trans.M0, x, y + height),
            }[orientation]
            top.insert(kdb.CellInstArray(macro.cell_index(), transform))
            placed.append({
                "name": f"{group['name']}_{number:02d}",
                "master": master,
                "orientation": orientation,
                "bbox_um": [round(z * DBU, 3) for z in (x, y, x + width, y + height)],
            })
    return placed


def verify(file=OUTPUT, manifest_file=MANIFEST):
    manifest = json.loads(manifest_file.read_text())
    layout = read_layout(file)
    die = kdb.Box(0, 0, *map(db_units, manifest["die_um"]))
    top = layout.top_cell()
    if top.name != manifest["design"] or top.bbox() != die:
        raise ValueError("Unexpected GDS top cell or die bounds")
    groups = manifest["logic_regions"]
    direct_shapes = [
        (layer, shape) for layer in layout.layer_indexes() for shape in top.each_shape(layer)
    ]
    if len(direct_shapes) != 1 or direct_shapes[0][0] != layout.layer(BOUNDARY):
        raise ValueError("Expected only the die boundary in the top cell")
    expected = Counter()
    named_boxes = [(name, kdb.Box(*map(db_units, group["region_um"]))) for name, group in groups.items()]
    for entry in manifest["sram"]:
        x, y, right, top_y = map(db_units, entry["bbox_um"])
        named_boxes.append((entry["name"], kdb.Box(x, y, right, top_y)))
        fs = entry["orientation"] == "FS"
        expected[(entry["master"], x, top_y if fs else y, fs)] += 1
    check_disjoint(named_boxes, die)
    actual = Counter()
    inspected = set()
    for instance in top.each_inst():
        cell = instance.cell
        if cell.name.startswith("logic_"):
            group = cell.name.removeprefix("logic_")
            children = list(cell.each_inst())
            if group not in groups or group in inspected:
                raise ValueError(f"Unexpected logic group: {group}")
            if len(children) != groups[group]["instances"] or any(
                not child.cell.name.startswith("sg13g2_") or child.cell.is_empty() for child in children
            ):
                raise ValueError(f"Unexpected GDS logic population for {group}")
            inspected.add(group)
        else:
            transform = instance.trans
            if cell.is_empty() or not instance.bbox().inside(die):
                raise ValueError(f"Empty or out-of-die SRAM: {cell.name}")
            actual[(cell.name, transform.disp.x, transform.disp.y, transform.is_mirror())] += 1
    if actual != expected or inspected != set(groups):
        raise ValueError("GDS instances differ from the placement manifest")
    print(f"{top.name}: {sum(actual.values())} SRAM macros, "
          f"{sum(group['instances'] for group in groups.values()):,} standard cells. "
          "GDS hierarchy and macro placement verified.")


def build():
    spec = json.loads(SPEC.read_text())
    cells, stubs = grouped_cells()
    layout = kdb.Layout()
    layout.dbu = DBU
    top = layout.create_cell(spec["design"])
    top.shapes(layout.layer(BOUNDARY)).insert(kdb.Box(0, 0, *map(db_units, spec["die_um"])))
    manifest = {
        "design": spec["design"],
        "stage": "unrouted placement preview",
        "die_um": spec["die_um"],
        "logic_regions": place_logic(layout, top, spec, cells),
        "rtl_memory_blackboxes": stubs,
        "sram": place_sram(layout, top, spec),
    }
    options = kdb.SaveLayoutOptions()
    options.gds2_max_cellname_length = 128
    options.gds2_write_timestamps = False
    layout.write(str(OUTPUT), options)
    MANIFEST.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    export_oasis()


def export_oasis():
    verify()
    layout = read_layout(OUTPUT)
    options = kdb.SaveLayoutOptions()
    options.set_format_from_filename(str(OASIS))
    options.oasis_compression_level = 0
    layout.write(str(OASIS), options)
    verify(OASIS)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--verify", action="store_true", help="check the committed layout files")
    mode.add_argument("--export-oasis", action="store_true", help="convert the committed GDS to OASIS")
    args = parser.parse_args()
    if args.verify:
        verify()
        verify(OASIS)
    elif args.export_oasis:
        export_oasis()
    else:
        build()
