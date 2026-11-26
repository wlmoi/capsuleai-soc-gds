# CapsuleAI SoC · IHP SG13G2

PicoRV32, akselerator CNN, dan 26 makro SRAM pada die 4.040 × 2.800 µm. Struktur repo mengikuti [Tiny Tapeout IHP 26b](https://github.com/TinyTapeout/tinytapeout-ihp-26b/tree/main).

[Layout 3D di GitHub Pages](https://wlmoi.github.io/capsuleai-soc-gds/#viewer-3d) · [Tiny Tapeout Explorer](https://gds-explorer.tinytapeout.com/viewer?file=https%3A%2F%2Fwlmoi.github.io%2Fcapsuleai-soc-gds%2Ftinytapeout-view.oas&pdk=ihp-sg13g2) · [GDSII](gds/capsoc_floorplan.gds) · [OASIS lengkap](gds/capsoc_floorplan.oas)

| Direktori | Isi |
|---|---|
| [gds/](gds/) | Layout CapsuleAI dalam GDSII dan OASIS |
| [lef/](lef/) | Abstrak fisik tiga jenis makro SRAM IHP |
| [verilog/](verilog/) | RTL PicoRV32 dan akselerator CNN |
| [projects/](projects/) | Metadata proyek CapsuleAI |
| [docs/](docs/) | Desain, penempatan SRAM, dan status verifikasi |

![Render KLayout dari GDSII CapsuleAI](layout/preview.png)

Layout ini adalah **preview penempatan**. Makro SRAM belum terhubung ke logika, dan routing serta sign-off masih terbuka. Repo ini adalah proyek mandiri. Untuk melihat atau membuat ulang layout, buka [BUILDING.md](BUILDING.md).
