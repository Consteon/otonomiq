# Minutes of Meeting — 09 June 2026

*Flutter Application — Engineering & Technical Planning Session*

---

## 1. Meeting Information

| Field | Detail |
| --- | --- |
| **Meeting Title** | Technical Planning — Feature Development, Upgrade & Governance |
| **Date** | 09 June 2026 |
| **Location** | Google Meet |
| **Participants** | Pak Hartono Oki Angga |
| **Document Status** | Final |

---

## 2. Agenda

- Pengembangan fitur perpindahan stok ke agent (Agent Stock Transfer).
- Peningkatan dokumentasi proyek (Project Documentation).
- Upgrade Flutter dan dependency management.
- Migrasi state management (Bloc ke GetX).
- Monitoring dan error reporting.
- Standardisasi dan cleanup codebase.

---

## 3. Discussion Summary

Rapat membahas enam area utama yang mencakup pengembangan fitur baru, peningkatan kualitas dokumentasi, pemutakhiran teknologi, migrasi arsitektur, observability, serta tata kelola teknis (technical governance). Pembahasan menekankan aspek maintainability, scalability, dan observability sebagai pijakan pengembangan ke depan.

### 3.1 Agent Stock Transfer Feature

Tim akan mengembangkan widget baru untuk menangani perpindahan jumlah item galon/tabung gas ke agent. Input quantity (qty) menggunakan widget Stepper untuk operasi numerik, dan setiap agent memiliki stok masing-masing.

- Setiap perubahan quantity pada widget Stepper memperbarui data tabel menggunakan mekanisme JSON `updateTableRow`.
- Mekanisme `updateTableRow` digunakan untuk update data sementara pada tabel/grid transaksi yang sedang aktif.
- Setiap transaksi yang telah dikonfirmasi wajib dicatat menggunakan mekanisme `addToTable`.
- Transaction history berfungsi sebagai audit trail untuk seluruh aktivitas perpindahan stok.
- Sinkronisasi antara stok agent dan transaction history harus dipastikan konsisten.

### 3.2 Project Documentation

- Membuat repository khusus dokumentasi di GitHub.
- Repository dokumentasi menjadi single source of truth untuk seluruh dokumentasi proyek.
- Membuat template dokumentasi teknis yang dapat digunakan secara konsisten oleh seluruh tim.

### 3.3 Flutter Upgrade & Dependency Management

- Melakukan upgrade Flutter ke versi terbaru (Flutter 3.44.0).
- Setelah upgrade Flutter selesai, melakukan upgrade plugin secara bertahap.
- Setiap tahapan upgrade wajib melalui proses testing dan validasi.
- Seluruh breaking changes harus didokumentasikan.

**Prioritas upgrade plugin:**

1. Core plugins
2. Firebase plugins
3. Networking plugins
4. Utility plugins
5. UI plugins

### 3.4 State Management Migration

- Melakukan migrasi state management dari Bloc ke GetX.
- Memastikan seluruh fitur existing tetap berjalan dengan baik setelah migrasi.
- Melakukan regression testing pada setiap modul yang telah dimigrasikan.
- Mendokumentasikan perubahan arsitektur dan pattern yang digunakan.
- Menetapkan standar penggunaan GetX untuk project ke depan.

### 3.5 Monitoring & Error Reporting

- Menambahkan Firebase Crashlytics untuk monitoring crash dan error aplikasi.
- Crashlytics menjadi sumber utama error reporting pada production environment.
- Menentukan alur monitoring, triage, dan tindak lanjut terhadap crash yang ditemukan.
- Memastikan crash report dapat digunakan untuk analisis dan perbaikan aplikasi.

### 3.6 Codebase Cleanup & Standardization

- Menghapus file, asset, dan source code yang sudah tidak digunakan.
- Melakukan review terhadap seluruh unused files sebelum penghapusan.
- Menghapus legacy code yang sudah tidak digunakan.
- Mengurangi technical debt pada project.

### 3.7 File Naming Standardization

- Melakukan rename file agar sesuai dengan nama widget, page, screen, controller, service, atau feature yang direpresentasikan.
- Menetapkan standar penamaan file yang konsisten pada seluruh project.
- Menghindari penggunaan nama file yang generik dan tidak merepresentasikan isi file.
- Menggunakan naming convention yang sesuai dengan standar Flutter.
- Memastikan seluruh import, route, dependency injection, dan referensi file tetap berjalan setelah proses rename.

**Contoh standar penamaan:**

| ❌ Tidak Disarankan | ✅ Disarankan |
| --- | --- |
| `login.dart` | `login_page.dart` |
| `home_new.dart` | `home_dashboard_page.dart` |
| `widget1.dart` | `stock_transfer_stepper_widget.dart` |
| — | `stock_transfer_controller.dart` |

---

## 4. Decisions

Berikut keputusan yang disepakati berdasarkan hasil diskusi:

- Disetujui pengembangan fitur Agent Stock Transfer menggunakan widget Stepper, dengan mekanisme `updateTableRow` untuk update sementara dan `addToTable` untuk pencatatan transaksi terkonfirmasi.
- Transaction history ditetapkan sebagai audit trail wajib dengan field minimal: tanggal/waktu, user, agent tujuan, jenis item, quantity, stok sebelum, dan stok sesudah.
- Disetujui pembuatan repository dokumentasi terpusat di GitHub sebagai single source of truth, dilengkapi template dokumentasi teknis standar.
- Disetujui upgrade Flutter ke versi 3.44.0, dilanjutkan upgrade plugin secara bertahap sesuai prioritas dengan testing dan validasi pada setiap tahap.
- Disetujui migrasi state management dari Bloc ke GetX; GetX ditetapkan sebagai standar state management untuk pengembangan ke depan.
- Disetujui integrasi Firebase Crashlytics sebagai sumber utama error reporting pada production environment.
- Disetujui penambahan Incident Runbook dengan klasifikasi severity P1–P4 beserta alur eskalasi dan prosedur recovery.
- Disetujui pelaksanaan codebase cleanup dan standardisasi penamaan file sesuai naming convention Flutter, dengan jaminan seluruh referensi tetap berfungsi.

---

## 5. Next Steps

- Memprioritaskan pengembangan fitur Agent Stock Transfer beserta mekanisme transaction history sebagai deliverable utama.
- Menjalankan upgrade Flutter 3.44.0 dan plugin secara bertahap di branch terisolasi sebelum diintegrasikan.
- Memulai migrasi Bloc ke GetX secara modular disertai regression testing.
- Menyiapkan repository dokumentasi dan template teknis sebagai fondasi technical governance.
- Mengintegrasikan Firebase Crashlytics dan menyiapkan Incident Runbook untuk meningkatkan observability.
- Menjadwalkan review berkala untuk memantau progres seluruh action items.

---

## 6. Conclusion

Rapat menghasilkan kesepakatan yang jelas terkait pengembangan fitur Agent Stock Transfer, peningkatan dokumentasi, pemutakhiran Flutter dan dependency, migrasi state management ke GetX, penguatan monitoring melalui Crashlytics, serta standardisasi dan cleanup codebase. Seluruh inisiatif difokuskan pada peningkatan maintainability, scalability, observability, dan technical governance proyek.

Langkah selanjutnya adalah eksekusi seluruh inisiatif secara bertahap dengan testing dan dokumentasi yang konsisten. Dokumen ini menjadi acuan resmi atas keputusan dan tindak lanjut yang disepakati.

---

*— End of Minutes of Meeting —*

*Confidential — Internal Use Only*
