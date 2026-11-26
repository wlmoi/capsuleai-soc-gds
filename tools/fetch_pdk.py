"""Fetch the pinned, public IHP physical library views."""
from pathlib import Path
from urllib.request import urlretrieve
import json

REVISION = "e73adb4045731ddec21634146d536380057f6a26"
BASE = f"https://raw.githubusercontent.com/IHP-GmbH/IHP-Open-PDK/{REVISION}"


def main():
    target = Path("build/pdk")
    target.mkdir(parents=True, exist_ok=True)
    spec = json.loads(Path("layout/floorplan.json").read_text())
    views = {
        "sg13g2_stdcell": [
            "gds/sg13g2_stdcell.gds",
            "lef/sg13g2_stdcell.lef",
            "lib/sg13g2_stdcell_typ_1p20V_25C.lib",
        ],
        "sg13g2_sram": [
            f"{view}/{master}.{view}"
            for master in sorted({group["master"] for group in spec["sram_groups"]})
            for view in ("gds", "lef")
        ],
    }
    for library, files in views.items():
        for file in files:
            output = target / Path(file).name
            if output.is_file():
                continue
            partial = output.with_suffix(output.suffix + ".part")
            urlretrieve(f"{BASE}/ihp-sg13g2/libs.ref/{library}/{file}", partial)
            partial.replace(output)


if __name__ == "__main__":
    main()
