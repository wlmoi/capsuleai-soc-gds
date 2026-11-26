# CapsuleAI SoC

CapsuleAI menggabungkan PicoRV32 dengan akselerator CNN. Firmware memulai inferensi melalui register akselerator, membaca logits, dan mengeluarkan keputusan lewat GPIO. Sintesis SG13G2 yang menjadi dasar layout ini menghasilkan 78.477 standard cell dengan empat antarmuka memori yang masih berupa black box.

## Penempatan SRAM

Layout menempatkan bank aktivasi di kanan logika CNN, bank bobot dan requant di ujung kanan, dan SRAM firmware di bawah PicoRV32. [Koordinat dan orientasi tiap makro](../layout/placement.json) berasal dari manifest yang dipakai untuk memeriksa GDSII dan OASIS.

| Kelompok | Makro IHP | Posisi | Alokasi |
|---|---|---|---|
| Firmware | 2 × 2048 × 32 bit | Kiri bawah | 16 KiB untuk firmware dan stack |
| Aktivasi | 16 × 2048 × 32 bit | Tengah kanan | 8 bank per buffer ping-pong, 16 bit data per word |
| Bobot | 5 × 4096 × 16 bit | Kanan | 20.480 word untuk 18.608 word bobot |
| Requant | 3 × 512 × 32 bit | Kanan | 3 bagian × 32 bit untuk setiap record 96 bit |

Jumlah makro mengikuti kapasitas per kelompok. Port paralel memerlukan pemetaan alamat, penanganan konflik baca, dan penyesuaian latensi SRAM sinkron. Bobot, konstanta requant, firmware, dan frame juga membutuhkan jalur inisialisasi saat chip dinyalakan.

## Status fisik

GDSII dan OASIS berisi geometri standard cell hasil sintesis dan makro SRAM IHP. Standard cell ditempatkan dalam row tanpa optimasi konektivitas. Routing, jaringan daya, clock tree, timing, DRC, dan LVS masih terbuka. Ukuran die 4.040 × 2.800 µm dipakai untuk studi penempatan CapsuleAI.

[Tiny Tapeout IHP 26b](https://github.com/TinyTapeout/tinytapeout-ihp-26b/tree/main) menjadi acuan struktur repo. [IHP PRISM](https://github.com/kdp1965/ihp-um-janestreet-prism) menjadi acuan penyajian render dan viewer. Geometri dan LEF berasal dari [IHP Open PDK](https://github.com/IHP-GmbH/IHP-Open-PDK/tree/e73adb4045731ddec21634146d536380057f6a26), dengan [lisensi PDK](../reference/LICENSE-IHP-Open-PDK). Pemberitahuan lisensi PicoRV32 tersedia di file sumbernya.
