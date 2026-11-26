# Membuka dan membuat ulang layout

Buka `gds/capsoc_floorplan.gds` atau `gds/capsoc_floorplan.oas` di KLayout. Pilih top cell `capsoc_floorplan` dan muat `layout/sg13g2-preview.lyp` untuk memakai palet gambar preview.

Dari root repo, jalankan perintah berikut dengan Python 3.11 dan Yosys 0.51 yang menyertakan ABC.

```sh
python -m pip install -r requirements.txt
python tools/fetch_pdk.py
yosys -l build/synth.log tools/synth.ys
python tools/floorplan.py
python tools/render.py
python tools/render_3d_layers.py
python tools/export_explorer.py
```

Untuk memindahkan SRAM, ubah `origin_um`, `pitch_um`, atau `row_orientations` di `layout/floorplan.json` lalu jalankan ulang mulai dari `python tools/floorplan.py`. `python tools/floorplan.py --verify` membaca kedua file layout lengkap dan memeriksa top cell, jumlah standard cell, serta posisi, orientasi, dan batas makro.

Workflow GDS memublikasikan kedua format layout dan render KLayout sebagai artifact. Model 3D untuk Tiny Tapeout Explorer mempertahankan lokasi semua makro dan blok logika. Model ini memakai sampel geometri standard cell dan layer terpilih dari makro SRAM. Dua label suplai dari satu standard cell disalin ke top model explorer agar viewer mengenalinya. GDSII dan OASIS lengkap tersedia di GitHub Pages.

Viewer 3D di GitHub Pages menumpuk enam render transparan dari GDSII dengan urutan layer SG13G2. Gambar didaftarkan pada kotak die yang sama. Jarak antar bidang pada layar diperbesar agar layer bisa diperiksa satu per satu.

Frame medis dan berkas bobot model tidak termasuk dalam repo. Untuk testbench RTL, gunakan `frame*.mem`, `weights.mem`, dan `requant.mem` dari arsip awal dengan nama dan lokasi yang dirujuk di `tb/tb_soc.v`. Sumber Verilog berada di `verilog/rtl/`.
