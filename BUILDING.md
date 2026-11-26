# Membuka dan membuat ulang layout

Buka `gds/capsoc_floorplan.gds` atau `gds/capsoc_floorplan.oas` di KLayout. Pilih top cell `capsoc_floorplan` dan muat `layout/sg13g2-preview.lyp` untuk memakai palet gambar preview.

Dari root repo, jalankan perintah berikut dengan Python 3.11 dan Yosys 0.51 yang menyertakan ABC.

```sh
python -m pip install -r requirements.txt
python tools/fetch_pdk.py
yosys -l build/synth.log tools/synth.ys
python tools/floorplan.py
python tools/render.py
```

Untuk memindahkan SRAM, ubah `origin_um`, `pitch_um`, atau `row_orientations` di `layout/floorplan.json` dan jalankan ulang dua perintah terakhir. `python tools/floorplan.py --verify` membaca kedua file layout dan memeriksa top cell, jumlah standard cell, serta posisi, orientasi, dan batas makro.

Workflow GDS memublikasikan kedua format layout dan render KLayout sebagai artifact. Workflow Pages menyediakan file OASIS untuk Tiny Tapeout Explorer dan menyediakan GDSII untuk diunduh dari halaman web.

Frame medis dan berkas bobot model tidak termasuk dalam repo. Untuk testbench RTL, gunakan `frame*.mem`, `weights.mem`, dan `requant.mem` dari arsip awal dengan nama dan lokasi yang dirujuk di `tb/tb_soc.v`. Sumber Verilog berada di `verilog/rtl/`.
