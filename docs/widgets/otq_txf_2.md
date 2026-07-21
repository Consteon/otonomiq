# OtqTxf2

Full-blown text field, version 2 — text input with support for formatters, validation, contact picker, array search, and GPS integration.

- **File:** [lib/widget/otq_txf_2.dart](../../lib/widget/otq_txf_2.dart)
- **Class:** `OtqTxf2` (StatefulWidget, with `AutomaticKeepAliveClientMixin`)
- **Status:** example (needs to be completed)
- **Widget version:** v2
- **Previous version:** [OtqTxf](otq_txf.md) (`lib/widget/otq_txf.dart`)

## Purpose

The next iteration of `OtqTxf` with extra capabilities and a reworked internal structure. Use this widget for text input on screens that use v2 components (e.g. paired with [OtqRdo2](otq_rdo_2.md), [OtqDropdown2](otq_dropdown_2.md), [OtqGetImages2](otq_get_images_2.md), [DisplayList2](display_list_2.md), [FtzRowOfButton2](ftz_row_of_button_2.md)).

> TODO: Fill in the concrete v1 vs. v2 differences after reading the implementation.

## Signature / Constructor

```dart
const OtqTxf2({
  required Key key,
  required String scrName,
  required dynamic component,
  required double lPad,
  required double tPad,
  required double rPad,
  required double bPad,
  TextEditingController? cnt,
})
```

### Parameters

| Param | Type | Required | Default | Description |
|---|---|---|---|---|
| `key` | `Key` | yes | — | Unique key per instance |
| `scrName` | `String` | yes | — | Name of the screen this widget is mounted on |
| `component` | `dynamic` | yes | — | Component config (Map from the screen definition) |
| `lPad` | `double` | yes | — | Left padding |
| `tPad` | `double` | yes | — | Top padding |
| `rPad` | `double` | yes | — | Right padding |
| `bPad` | `double` | yes | — | Bottom padding |
| `cnt` | `TextEditingController?` | no | `null` | External controller passed in by the parent. `null` = stand-alone widget (controller is created internally). |

### `component` shape

> TODO: List the keys read from `component` (e.g. `name`, `label`, `inputType`, `formatter`, `validator`, `arraySearch`, etc.) after auditing the source.

## Usage Examples

### Stand-alone (no external controller)

```dart
OtqTxf2(
  key: const ValueKey('name'),
  scrName: 'userProfile',
  component: const {
    'name': 'name',
    'label': 'Full Name',
  },
  lPad: 8, tPad: 8, rPad: 8, bPad: 8,
)
```

### With an external controller

```dart
class _FormState extends State<Form> {
  final nameCnt = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return OtqTxf2(
      key: const ValueKey('name'),
      scrName: 'userProfile',
      component: const { 'name': 'name', 'label': 'Full Name' },
      lPad: 8, tPad: 8, rPad: 8, bPad: 8,
      cnt: nameCnt,
    );
  }
}
```

## State / Bloc / Dependencies

Inferred from the file's imports:

- **Bloc:** [`MainBloc`](../../lib/main_bloc/main_bloc.dart), [`TimerBloc`](../../lib/bloc_timer/timer_bloc.dart)
- **Repository:** [`TableRepository`](../../lib/firestore_repository/table_repository.dart), [`Api`](../../lib/api.dart)
- **Sibling widgets:** [`FtzArraySearch`](../../lib/widget/ftz_array_search.dart), [`FtzContactPicker`](../../lib/widget/ftz_contact_picker.dart), [`OtqTxf`](../../lib/widget/otq_txf.dart)
- **Packages:** `flutter_multi_formatter`, `geolocator`, `group_radio_button`, `intl`, `get`, `flutter_bloc`

## Speech-to-text (`stt`)

Per-component opt-in dictation for free-text fields (e.g. "keterangan"), on-device via the platform recognizer (`speech_to_text` package — Android `SpeechRecognizer`, iOS `SFSpeechRecognizer`; no cloud key).

| Key | Type | Default | Description |
|---|---|---|---|
| `stt` | bool/string | `false` | `true` shows a mic button after the field (default variant only — not on contact/tablesearch/barcode/qrscan/date/time variants). |
| `sttLocale` | string | `id_ID` | Locale passed to the recognizer. |

Behavior:

- Tap mic → listen (icon turns red); tap again or pause → stop. Auto-stops via plugin `done`/`notListening` status.
- Speech is **appended** to the text present when the session started (`sttCompose`, live partial results); `maxLength` is enforced manually because input formatters don't apply to programmatic `controller.text` writes.
- Result is written to both `myController.text` and `txfController[scrName][position].finalData` (mirrors the `onChanged` default branch, like the QR handlers).
- One static recognizer shared app-wide; starting dictation on one field stops it on another. Stopped on `dispose`.
- Mic button honors `isEnabled` and is hidden when the field is not `editable`.
- Permissions: Android `RECORD_AUDIO` + `<queries>` RecognitionService (manifest); iOS `NSSpeechRecognitionUsageDescription` + existing mic string (Info.plist).

## Important Behavior

- `with AutomaticKeepAliveClientMixin` → the widget's state survives when scrolled out of the viewport (e.g. inside a `ListView` / `PageView`).
- The `errorCode` field uses the sentinel `emptyString` (from [`init_values.dart`](../../lib/init_values.dart)) — **not** a literal `''` — to indicate "no error".
- The `touch` flag controls whether the field accepts input (defaults to `true`).

> TODO: Add notes on validation, auto-formatting (credit cards?), and `geolocator` integration after reading the rest of the file.

## See Also

- [otq_txf.md](otq_txf.md) — v1 version (`OtqTxf`)
- [otq_rdo_2.md](otq_rdo_2.md), [otq_dropdown_2.md](otq_dropdown_2.md), [otq_get_images_2.md](otq_get_images_2.md) — other v2 components typically used together
- Formatter reference: [flutter_multi_formatter](https://pub.dev/packages/flutter_multi_formatter)
