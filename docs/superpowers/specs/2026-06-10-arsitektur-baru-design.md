# Arsitektur Project Server-Driven UI Baru — Design Spec

**Tanggal:** 2026-06-10
**Status:** Design (disetujui untuk dipakai sebagai acuan project baru)
**Konteks:** Rekomendasi struktur folder + arsitektur untuk project Flutter **baru** yang
bertipe server-driven UI, berdasarkan stack & pelajaran dari `otonomiq`.

---

## 1. Tujuan & Profil Project

Project baru ini:

- **Server-driven UI** — screen datang sebagai JSON (Google Sheets / proxy Firestore),
  dirender jadi widget saat runtime. Bukan screen yang di-hardcode di Dart.
- **GetX dominan** — GetX dipakai untuk state + routing + dependency injection sekaligus.
- **Offline-first** — aksi user antri lokal (history queue), sync ke Firestore saat online.
- **White-label** — satu basis kode, banyak app bermerek (per-tenant config & theming).

Stack acuan (sama dengan `otonomiq`): Flutter (Dart sdk >=3.3), GetX, Firebase
(Firestore / Auth / Storage / Messaging / Functions), geolocator, mobile_scanner, dll.

### Tujuan arsitektur

Mencegah empat masalah struktural yang muncul di `otonomiq`:

| Masalah `otonomiq` | Penyebab | Fix di arsitektur baru |
|---|---|---|
| God-file (`global.dart` ~2k, `api.dart` ~4.3k, `build_display_component.dart` ~1.2k) | Semua logika menumpuk di satu file | GetX DI (`Get.put`/`Get.find`) → service kecil per-domain |
| `buildDisplayComponent` rantai if/else ~1200 baris | Dispatch `tip == 'txf' … 'drd'` manual | **Component registry** `Map<String, ComponentBuilder>`, 1 file per tipe |
| Custom `routeStack` (reinvent Navigator, footgun) | Routing manual di luar framework | GetX routing (`Get.toNamed` + `Binding` + middleware) yang sudah punya back-stack |
| Encoding `◆` / `_25FC_` tersebar (`diamondTextToList`, `autheniumDecode`) | Decode ad-hoc di banyak tempat | Layer `core/codec/` terpusat; encode/decode hanya di batas |

### Prinsip pemandu

**Batas tegas antar layer.** UI tidak tahu Firestore. Firestore tidak tahu encoding.
Tiap tipe komponen tidak tahu komponen lain. God-file jadi mustahil karena tiap layer
punya satu tanggung jawab.

---

## 2. Struktur Folder

```
lib/
  main.dart
  app/
    app.dart                        # GetMaterialApp, theme, initial route
    bindings/initial_binding.dart   # Get.put core singleton saat boot
    routes/app_pages.dart           # daftar GetPage
    routes/app_routes.dart          # konstanta nama route
    theme/app_theme.dart            # white-label, per-tenant
  core/
    config/                         # env + tenant/white-label config
    network/
      connectivity_service.dart
      firestore_client.dart
    codec/                          # diamond encode/decode, autheniumDecode — TERPUSAT
    errors/
    constants/
    utils/
  data/
    models/                         # DTO: PageSpec, ComponentSpec, Record
    sources/
      remote/                       # firestore repo: proxy, table, generic
      local/                        # secure_storage, shared_prefs, hive/sqlite
    repositories/                   # implementasi
  domain/
    entities/
    repositories/                   # interface abstrak
    usecases/                       # opsional
  sync/                             # ENGINE OFFLINE-FIRST — diisolasi
    models/                         # action.dart, sync_status.dart
    queue/history_queue.dart        # antrian aksi lokal (history log)
    engine/sync_service.dart        # drain queue → firestore saat online
    image/image_sync.dart           # ganti imageMap + retry counter
    codec/table_codec.dart          # merge/split ⬤ di batas Firestore
  sdui/                             # JANTUNG server-driven UI
    engine/
      page_builder.dart             # ganti constructPageElements
      component_registry.dart       # Map<type, ComponentBuilder>
      component_builder.dart        # interface ComponentBuilder
      render_context.dart           # state per-screen (ganti txfController map)
      field_state.dart              # state per-slot, reaktif
    components/                      # SATU FILE PER TIPE
      txf_component.dart
      txt_component.dart
      rbt_component.dart
      drd_component.dart
      ...
  features/                         # screen yang DI-CODE (bukan server-driven)
    login/                          # tiap fitur: bindings/ controllers/ views/
    splash/
  shared/
    widgets/                        # widget reusable non-sdui
    services/                       # gps, device_info, notification
```

Inti pemisahan: `sdui/` (render engine) + `sync/` (offline) + `data/` (Firestore) dipisah
tegas. `core/codec/` terpusat. GetX DI menggantikan singleton global.

---

## 3. Pilar 1 — Component Registry (mematikan if/else 1200 baris)

### Masalah

`buildDisplayComponent` di `otonomiq` adalah satu fungsi raksasa: `if (tip == 'txf') … else
if (tip == 'drd') …`, 30+ cabang, ~1200 baris. Menambah tipe = mengedit fungsi raksasa.
Sulit menguji satu tipe saja. Magnet merge-conflict.

### Solusi: registry + satu file per tipe

**Kontrak** — tiap komponen mengimplementasi interface yang sama:

```dart
// sdui/engine/component_builder.dart
abstract class ComponentBuilder {
  String get type;                                   // 'txf', 'drd', ...
  Widget build(ComponentSpec spec, RenderContext ctx);
}
```

**Registry** — `Map<String, ComponentBuilder>`, diisi sekali saat boot:

```dart
// sdui/engine/component_registry.dart
class ComponentRegistry {
  final _builders = <String, ComponentBuilder>{};

  void register(ComponentBuilder b) => _builders[b.type] = b;

  Widget build(ComponentSpec spec, RenderContext ctx) {
    final b = _builders[spec.type.toLowerCase()];
    if (b == null) return UnknownComponent(spec.type);   // graceful, tidak crash
    return b.build(spec, ctx);
  }
}
```

**Daftar sekali** di `initial_binding.dart`:

```dart
final registry = ComponentRegistry()
  ..register(TxfComponent())
  ..register(TxtComponent())
  ..register(RbtComponent())
  ..register(DrdComponent());
Get.put(registry, permanent: true);
```

**Satu tipe = satu file kecil:**

```dart
// sdui/components/txf_component.dart
class TxfComponent implements ComponentBuilder {
  @override
  String get type => 'txf';

  @override
  Widget build(ComponentSpec spec, RenderContext ctx) {
    final field = ctx.field(spec.position);     // state per-slot, ganti txfController[scr][pos]
    return Obx(() => TextField(
          enabled: field.enabled.value,
          controller: field.controller,
          decoration: InputDecoration(labelText: spec.label),
        ));
  }
}
```

**`page_builder` memakai registry:**

```dart
// sdui/engine/page_builder.dart  (ganti constructPageElements)
List<Widget> buildPage(PageSpec page, RenderContext ctx) {
  final registry = Get.find<ComponentRegistry>();
  return page.components.map((c) => registry.build(c, ctx)).toList();
}
```

### Hasil

| Sebelum | Sesudah |
|---|---|
| if/else 1200 baris | registry ~20 baris + N file kecil |
| tambah tipe = edit god-fungsi | tambah tipe = file baru + 1 baris `register` |
| test = build seluruh page | test = unit test satu `ComponentBuilder` |
| tipe tak dikenal = crash/silent | `UnknownComponent` placeholder |

`components/` boleh berisi ratusan file kecil dan tetap rapi (plugin-style).

---

## 4. Pilar 2 — RenderContext (mengganti `txfController[scrName][position]`)

### Masalah

State field di `otonomiq` tersimpan di map global bertingkat: `txfController[scrName]
[position]` (value, enabled, initial), ditambah `screenUIComponent[scrName]`,
`linkElement[scrName]`, `linkPage[scrName]`. Map global tidak punya pemilik lifecycle —
lupa membersihkan saat pindah screen → memory bocor + state tercampur antar screen.
`position` adalah integer telanjang yang mudah salah index.

> Ini sejalan dengan pedoman yang sudah ada: *screen-specific state di-key per `scrName`,
> dibersihkan saat route berganti.*

### Solusi: satu RenderContext per screen, lifecycle mengikuti route

**RenderContext = GetxController**, hidup-mati mengikuti screen:

```dart
// sdui/engine/render_context.dart
class RenderContext extends GetxController {
  final String scrName;
  final PageSpec page;
  final _fields = <int, FieldState>{};        // position -> state, LOKAL per screen

  RenderContext(this.scrName, this.page);

  FieldState field(int position) =>
      _fields.putIfAbsent(position, () => FieldState(page.specAt(position)));

  /// record yang disubmit, array di-index by position
  List<dynamic> collect() {
    final out = List.filled(page.componentCount, null);
    _fields.forEach((pos, f) => out[pos] = f.value.value);
    return out;
  }

  @override
  void onClose() {                            // GetX panggil OTOMATIS saat screen dibuang
    for (final f in _fields.values) f.dispose();
    _fields.clear();
  }
}
```

**FieldState** — satu slot, reaktif:

```dart
// sdui/engine/field_state.dart
class FieldState {
  final ComponentSpec spec;
  final controller = TextEditingController();
  final value = ''.obs;
  final enabled = true.obs;
  final initial = ''.obs;

  FieldState(this.spec) {
    controller.addListener(() => value.value = controller.text);
  }

  void dispose() => controller.dispose();
}
```

### Lifecycle menempel ke route (kunci anti-bocor)

GetX `Binding` membuat context saat screen masuk, membuangnya saat keluar — otomatis,
tanpa perlu ingat membersihkan:

```dart
// features/.../sdui_page_binding.dart
class SduiPageBinding extends Bindings {
  @override
  void dependencies() {
    final scr = Get.parameters['scr']!;
    Get.lazyPut(() => RenderContext(scr, PageRepo.load(scr)), tag: scr);
  }
}
```

```dart
// app/routes/app_pages.dart
GetPage(
  name: '/sdui',
  page: () => const SduiPageView(),
  binding: SduiPageBinding(),
);
```

View mengambil context-nya per-screen:

```dart
class SduiPageView extends StatelessWidget {
  const SduiPageView({super.key});

  @override
  Widget build(BuildContext context) {
    final scr = Get.parameters['scr']!;
    final ctx = Get.find<RenderContext>(tag: scr);   // di-key per scrName
    return Column(children: buildPage(ctx.page, ctx));
  }
}
```

Saat `Get.back()` / route dibuang → GetX memanggil `onClose()` → controller dibuang, map
dibersihkan. Zero manual cleanup.

### Hasil

| `otonomiq` | Baru |
|---|---|
| `txfController[scr][pos]` map global, manual clear | `RenderContext` per screen, auto-dispose oleh GetX |
| state tercampur kalau lupa clear | tiap screen punya instance sendiri (tag = scrName) |
| widget cache global `linkElement` | rebuild dari `Obx`, tak perlu cache manual |
| `position` integer telanjang | tetap `position`, tapi dibungkus `field(pos)` satu pintu |

State per-screen jadi terisolasi by construction — tidak bisa bocor walau lupa.

---

## 5. Pilar 3 — Sync Engine Offline-First (history queue → Firestore)

### Masalah

Logika sync di `otonomiq` tertelan di `api.dart` (~4.3k baris): `historySync`, merge
`tableString` pakai `separator[0]` (`⬤`), split kembali saat sync, `imageMap` + retry
counter — semua bercampur dengan logika bisnis lain. Sulit menguji jalur offline tanpa
menyalakan seluruh app.

### Solusi: modul `sync/` terisolasi, satu interface masuk-keluar

Aturan: **UI/feature tidak pernah menulis ke Firestore langsung.** Mereka hanya
`enqueue()`. Drain ke Firestore adalah urusan internal `sync/`.

```
sync/
  models/        action.dart, sync_status.dart
  queue/         history_queue.dart   (persist lokal: hive/sqlite)
  engine/        sync_service.dart    (drain saat online)
  image/         image_sync.dart      (ganti imageMap + retry)
  codec/         table_codec.dart     (merge/split ⬤, pakai core/codec)
```

**Satu model aksi bertipe, bukan string mentah:**

```dart
// sync/models/action.dart
enum Op { add, update, delete }

class TableAction {
  final String id;                  // uuid lokal
  final Op op;
  final String table;               // nama tabel
  final String rowId;               // Firestore doc id
  final Map<String, dynamic> data;
  final List<String> localImages;   // path lokal menunggu upload
  int retries;
  SyncStatus status;                // pending | syncing | done | failed
}
```

Encode ke `tableString` hanya di **batas** Firestore (`table_codec.dart`), bukan di seluruh
app.

**Queue = sumber kebenaran lokal:**

```dart
// sync/queue/history_queue.dart
class HistoryQueue {
  final _box = /* Hive box */;                          // survive restart

  Future<void> enqueue(TableAction a) async => _box.put(a.id, a);
  List<TableAction> pending() =>
      _box.values.where((a) => a.status == SyncStatus.pending).toList();
  Future<void> markDone(String id) async { /* ... */ }
  Future<void> markFailed(String id, {required int retries}) async { /* ... */ }
}
```

**Drain — satu service, dipicu konektivitas:**

```dart
// sync/engine/sync_service.dart
class SyncService extends GetxService {
  SyncService(this.queue, this.remote, this.images);

  final HistoryQueue queue;
  final TableRepository remote;        // data/sources/remote
  final ImageSync images;

  @override
  void onInit() {
    super.onInit();
    // reaktif: online -> drain. Ganti polling internet_connection_checker
    ever(Get.find<ConnectivityService>().online, (bool up) {
      if (up) drain();
    });
  }

  Future<void> drain() async {
    for (final a in queue.pending()) {
      try {
        final data = await images.resolve(a);          // upload gambar dulu, tukar path->url
        await remote.apply(a.op, a.table, a.rowId, data);
        await queue.markDone(a.id);
      } catch (e) {
        await queue.markFailed(a.id, retries: a.retries + 1);   // max 5, lalu dead-letter
      }
    }
  }
}
```

**Image sync terpisah (mengganti `imageMap`):**

```dart
// sync/image/image_sync.dart
class ImageSync {
  // path lokal -> url firebase, retry counter, max 5
  Future<Map<String, dynamic>> resolve(TableAction a) async { /* ... */ }
}
```

**Alur fitur jadi satu baris** — fitur tidak tahu Firestore/online/offline:

```dart
syncService.submit(TableAction(op: Op.add, table: 'absensi', data: rec, /* ... */));
// langsung kembali. drain berjalan sendiri saat online.
```

### Hasil

| `otonomiq` | Baru |
|---|---|
| `historySync` di `api.dart` 4.3k | `sync/` modul sendiri, satu tanggung jawab |
| aksi = string merge `⬤`, split rawan | `TableAction` bertipe; encode hanya di batas |
| online check polling tersebar | satu `ConnectivityService.online` reaktif, `ever()` memicu drain |
| `imageMap` global bercampur | `ImageSync` terpisah, retry terkurung |
| test offline = nyalakan app | mock `TableRepository` → unit test `drain()` |

Fitur tidak pernah menyentuh Firestore. Offline jadi default; online hanya memicu drain.

---

## 6. Ringkasan Empat Pilar

```
sdui/   -> render engine (registry, 1 file/tipe)            [bagian 3]
        -> RenderContext per screen, auto-dispose           [bagian 4]
sync/   -> offline queue -> drain, terisolasi               [bagian 5]
core/   -> codec terpusat, GetX DI mengganti global.dart    [bagian 2]
```

---

## 7. Keputusan & Trade-off

- **Tetap GetX dominan** (state + routing + DI). Alasan: familiar, cepat ditulis, kurva
  belajar tim kecil. Risiko GetX (magic, sulit di-test) **dimitigasi** oleh batas layer
  yang tegas + `Binding` per route (bukan `Get.put` sembarangan global).
- **GetX routing menggantikan `routeStack`.** GetX sudah punya back-stack + middleware;
  tidak perlu reinvent Navigator. Ini menutup footgun "push routeStack sebelum gotoRoute".
- **Component registry, bukan if/else.** Penambahan tipe komponen jadi additive
  (file baru + satu baris register), bukan modifikasi fungsi raksasa.
- **Persistence lokal = Hive (atau sqlite).** Untuk queue offline yang harus survive
  restart. `shared_preferences`/`secure_storage` hanya untuk config & secret.
- **Layer `domain/` opsional.** Untuk app berukuran kecil-menengah boleh dilewati
  (langsung `data/` → controller). Disediakan agar ada tempat jika logika tumbuh.

---

## 8. Di Luar Cakupan (YAGNI)

- Tidak memindahkan/menulis ulang `otonomiq`. Ini spec untuk **project baru**; `otonomiq`
  tetap apa adanya.
- Tidak ada multi-state-system (Redux + Bloc + GetX). Satu sistem saja: GetX.
- Tidak ada code generation/DSL untuk komponen di fase awal — registry manual cukup.
- Tidak ada caching widget manual (`linkElement`); andalkan `Obx`/rebuild GetX.

---

## 9. Langkah Berikutnya

Spec ini adalah acuan arsitektur. Saat project baru benar-benar dimulai, susun
implementation plan (urutan: scaffold `app/` + routing → `core/codec` + `data/` →
`sdui/` engine + beberapa komponen dasar → `sync/` engine → fitur login) lewat skill
`writing-plans`.
