# Target inferensi di bawah 15 mW

Target ini berlaku untuk daya rata-rata inti SoC selama inferensi aktif pada konfigurasi awal 25 MHz dan 1,2 V. Pada durasi 6,90 ms, batas energinya sekitar 103,5 µJ per frame. Angka ini adalah anggaran, belum hasil pengukuran.

RTL menghentikan clock PicoRV32 selama akselerator sibuk. CPU menyelesaikan handshake tulis untuk memulai inferensi, lalu bangun ketika akselerator selesai. Parameter `CPU_SLEEP=0` menjalankan mode awal untuk pembandingan. Untuk sintesis SG13G2, RTL menggunakan sel clock gating terintegrasi dari PDK.

`tb/tb_cpu_sleep.v` membandingkan dua konfigurasi tersebut dengan PicoRV32, firmware, dan bus asli. Model register pengganti akselerator menghasilkan respons deterministik. Pada pengujian ini, kedua konfigurasi memberi hasil GPIO yang sama dan jumlah tepi naik clock CPU selama akselerator sibuk turun dari 172.555 menjadi 1. Ini mengukur aktivitas clock CPU, belum daya total.

Simulasi RTL dengan frame 0 juga menghasilkan GPIO, head dan exit logits yang bit-exact terhadap hasil referensi. Akselerator tetap membutuhkan 172.555 siklus. Waktu keseluruhan turun dari 172.869 menjadi 172.857 siklus.

GDSII dan viewer di cabang utama masih menampilkan geometri studi penempatan sebelumnya. Empat antarmuka memori pada RTL sintesis masih berupa black box. Untuk menilai batas daya, hubungkan makro SRAM, selesaikan clock tree dan routing, lalu analisis aktivitas inferensi dengan parasitik, Liberty dan data daya SRAM. Laporkan daya dan energi inferensi termasuk clock, SRAM, dan leakage.
