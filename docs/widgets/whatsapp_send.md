# WhatsAppSend

Generic WhatsApp message sender: reads a doc by search, renders a configurable message template, normalizes the phone number, and opens wa.me via url_launcher. Optionally writes a marker field (e.g. `iv=sent`) on successful launch.

- **File:** [lib/widget/whatsapp_send.dart](../../lib/widget/whatsapp_send.dart)
- **Class:** `WhatsAppSend` (StatefulWidget)
- **Status:** draft
- **Widget version:** v1

## Purpose

Allows admin to send a pre-formatted WhatsApp message (invoice, reminder, confirmation) to a customer. The widget shows a button; tapping it opens a bottom sheet with editable phone number and message fields. On "Buka WhatsApp", it launches the wa.me deep link and writes a marker to Firestore only on successful launch.

## Signature / Constructor

```dart
WhatsAppSend({
  required Key key,
  required dynamic component,
  required String scrName,
  required double lPad,
  required double tPad,
  required double rPad,
  required double bPad,
})
```

### Parameters

| Param | Type | Required | Default | Description |
|---|---|---|---|---|
| `key` | `Key` | yes | -- | Unique key per instance |
| `component` | `dynamic` | yes | -- | Component config (see below) |
| `scrName` | `String` | yes | -- | Screen name |
| `lPad`/`tPad`/`rPad`/`bPad` | `double` | yes | -- | Padding |

### `component` shape

| Key | Type | Description |
|---|---|---|
| `vidtable` | `String` | App VID for Firestore subscription |
| `phoneField` | `String` | Field in doc for phone number (e.g. `hpic`) |
| `phoneFallback` | `String` | Token fallback if phoneField empty (e.g. `{custPhone}`) |
| `phoneTable` | `String` | **Optional.** Collection that holds the phone number when it is NOT on the message doc (e.g. `84214220504259//stock_location`). Requires `phoneSearch`. |
| `phoneSearch` | `String` | **Optional.** `field◼value` search for that collection. May reference a field of the MAIN (`messageTable`) doc: `lv◼{kl}` where `kl` is the customer FK on the `task`. Requires `phoneTable`. |
| `allowContactPick` | `String` | `TRUE` to show contact picker button |
| `countryCode` | `String` | Phone locale; only `62` implemented (YAGNI) |
| `messageTable` | `String` | Collection path for message source doc (e.g. `84214220504259//nota`) |
| `messageSearch` | `String` | Search condition (e.g. `ref◼{taskVid}`) |
| `messageTemplate` | `String` | Template string (see Template Syntax) |
| `logTable` | `String` | Collection path for marker write (e.g. task collection) |
| `logSearch` | `String` | Search for marker write using `◼` (U+25FC) separator (e.g. `tnm◼{taskVid}`). Must NOT use `★` -- that is the `updateEventRow` dialect, a different parser (see `coordination_signal_list.md:107`). `writeNativeFields` splits on `◼`; a `★` is silently dropped. |
| `logField` | `String` | Field to set (e.g. `iv`) |
| `logValue` | `String` | Value to set (e.g. `sent`) |
| `text` | `String` | Diamond-separated labels (9 slots; spec defines 0-6, plan adds 7-8) |

### text[] slots

Spec section 3.1 defines slots 0-6. Slots 7 (write-fail error) and 8 (sheet title) are plan additions for completeness. All slots are length-guarded via `_t(i, def)` so runtime is safe with any count of segments.

| Index | Meaning | Default |
|---|---|---|
| 0 | Main button label | `Kirim WhatsApp` |
| 1 | Phone number label | `Nomor WhatsApp` |
| 2 | Contact pick button | `Pilih Kontak` |
| 3 | Message label | `Pesan` |
| 4 | Open-WA button | `Buka WhatsApp` |
| 5 | Invalid number error | `Nomor tidak valid` |
| 6 | Sent badge | `Terkirim WA` |
| 7 | Write fail error | `Gagal menyimpan` |
| 8 | Sheet title | `Kirim WhatsApp` |

### Template Syntax

Mirrors `template_printer.dart` dialect (same for sheet authors):

- `{{field}}` -- doc field value
- `{{field|idr}}` -- dot-thousands formatted
- `<LOOP source='li'>...{{item.x}}...</LOOP>` -- iterate array field. This is
  the `template_printer.dart` (PRN) dialect, so operators author ONE syntax for
  both thermal print and WhatsApp. `source="li"` and unquoted `source=li` work
  too, matching `_parseAttributes`. The bare `<LOOP li>` shorthand is also
  accepted for back-compat. An unknown source renders nothing — a raw `<LOOP>`
  tag must never reach the customer's message.
- `<IFSET source='tot'>...</IFSET>` -- emit the body **only when `doc['tot']` is
  SET**; otherwise the whole block disappears, literal text (separators, labels)
  included. "Set" means: not `null`, not blank after `trim()`, **and not
  numerically zero** (`0`, `'0'`, `0.0` all count as unset). A non-numeric value
  such as `LUNAS` is SET — the zero test runs only after `num.tryParse`
  succeeds, so a String field is never silently dropped.
  - Purpose: a pickup-only task (purchase/refill only) has `tot == 0`, and
    `*Perkiraan total: Rp 0*` must not reach a customer. One template serves
    every task on the destination page, so wrapping the line is the only fix
    that leaves priced tasks intact.
  - Same attribute grammar as `<LOOP>` (`source='x'`, `source="x"`, `source=x`,
    and the bare `<IFSET x>` shorthand). A missing or empty `source=` drops the
    block — fail-closed on a typo.
  - Runs **BEFORE** the `<LOOP>` pass and before `{{field}}` substitution — one
    reason covers both: any value an earlier pass substitutes into the string
    becomes control flow for a later one. Control structure therefore comes only
    from the TEMPLATE, never from doc data — for top-level fields *and* for
    `{{item.*}}` values.
  - Not the reason: "a kept body still gets its `{{tot|idr}}` filled in". It
    does, but that is true under every pass order — kept- and dropped-body
    output is byte-identical whether `<IFSET>` runs before `<LOOP>`, between
    `<LOOP>` and `{{field}}`, or after `{{field}}`. Only the injection
    behaviour below distinguishes them.
  - **This ordering was changed on purpose.** While `<IFSET>` ran after
    `<LOOP>`, the `<LOOP>` pass had already substituted item values into the
    string, so a catalog item whose name contained a literal
    `<IFSET …>…</IFSET>` was **executed** and could delete itself from the
    customer's message silently. Running first makes such a tag leak verbatim
    into the editable preview sheet, where the admin can see it.
  - **Nesting:** `<IFSET>` inside a `<LOOP>` body, and `<LOOP>` inside an
    `<IFSET>` body, both render exactly as they did before the pass order
    changed. Note an `<IFSET>` inside a `<LOOP>` body is evaluated **once,
    against the top-level doc** — it cannot test a per-item field.
  - **Do not INTERLEAVE tags** — `<IFSET …>A<LOOP …>B</IFSET>C</LOOP>` is
    undefined: the lazy `*?` pairs the first `</IFSET>` with the first
    `<IFSET>`. Close each tag inside the block that opened it.
- `\n` -- newline

## State / Dependencies

- **State:** `_sent` keyed by resolved `messageSearch` in `static final Map<String, bool> _sentBySearch` on `WhatsAppSend`. Cleared per-`scrName` by `WhatsAppSend.clearSentState(scrName)`, wired at TWO call sites:
  - **Primary — `clearData(scrName)` in `lib/api.dart`.** This is the one that fires on navigation. `gotoRoute` → `reloadPage` calls `clearData` and then returns the *cached* `linkElement[page]`, so `buildPage` never runs on a route change. The call sits in the unconditional reset block ahead of `clearData`'s `txfController[scrName] == null` early return, alongside `CustodyCountList.clearCountStore` and siblings.
  - **Secondary — `buildPage(clear: true)` in `ui_component.dart`.** Covers the `constructPageElements` / `readSettings` refresh path.

  Both are kept; several widgets are registered in both lists. No Redux, no GetX controller, no global.dart.
- **Repository:** `subscribeToMapCollection` for live nota reads. Not cancelled in `dispose()` -- matches `receipt_doc.dart`, which has no `dispose()` override at all.
- **Side effects:** `writeNativeFields` (online-only set-merge) for marker -- only after successful launch. `launchUrl` for wa.me.
- **Imports:** `url_launcher`, `ftz_contact_picker`, `driver_home_support`, `panel_card_support` (`parseTablePath`/`TablePath`), `statistic_card_support`.

## Important Behavior

- **Phone resolution order** (spec (3) §6b-2.1). 1. `phoneTable` **and** `phoneSearch` both non-empty → read `phoneField` from the doc found in `phoneTable`. 2. Either empty → read `phoneField` from the `messageTable` doc (the original behaviour; every pre-2026-08-27 config takes this path). 3. Still empty → `phoneFallback` token → manual entry / `allowContactPick`.
- **`phoneSearch` token resolution** is main-doc-first: `resolveSearchWithRow` runs `autheniumDecode` → `resolveRowCurlyTokens(mainDoc)` → `resolveDriverCurlyTokens` → `resolveScreenTxTokens`, stopping as soon as no `{` remains. That is what lets `lv◼{kl}` read the customer FK off the `task` doc rather than off a route parameter.
- **The phone lookup is SKIPPED entirely when the main doc was not found.** A `{kl}` that cannot resolve from a row would otherwise fall through to a stale bare screenTx `kl` and prefill the previous customer's number. Blank is the safe failure.
- A configured phone lookup that finds no doc **degrades to rule 2**, not to "no number" — for a `task` main doc that reads an absent `hpic` and lands on rule 3.
- Phone normalization via `phoneCanonical62` (global.dart). Empty result disables launch button.
- Launch-first order: `launchUrl` is called BEFORE `writeNativeFields`. On launch failure (throw or `false`), the sheet stays open, no marker is written, no badge shows. The admin's edited message is preserved for retry.
- `writeNativeFields` failure shows a snackbar but does NOT undo the sent badge. **Nothing is queued for later** -- `writeNativeFields` is online-only and returns `false` on a 0-match or >1-match search, so `iv` stays empty and the coordination tier KEEPS showing the signal. This is deliberate: the admin sees the signal again and retries, and a duplicate WhatsApp message beats a lost invoice. The badge is session-local feedback only, not a durable state claim.
- No `canLaunchUrl` call -- avoids Android `<queries>` / iOS `LSApplicationQueriesSchemes` requirements.
- **Known limitation (v1, accepted):** on a device without WhatsApp installed, the https `wa.me` link is handled by a browser, `launchUrl` reports success, and `iv=sent` is written -- clearing the coordination signal for an invoice that was never delivered. This follows from the deliberate decision to skip `canLaunchUrl` (which would require `<queries>` / `LSApplicationQueriesSchemes` platform edits). Mitigation deferred; the admin sees a browser open instead of WhatsApp, which is the practical detection signal.
- The `|idr` formatter passes unparseable input through unchanged. A tenant sheet that already stores `tot` dot-formatted (`1.250.000`) renders correctly rather than collapsing to `0`.
- `countryCode` param accepted but only `62` implemented. Same YAGNI precedent as RECEIPT_DOC `money` param.

## See Also

- [receipt_doc.md](receipt_doc.md) -- sibling nota card on same page
- [coordination_signal_list.md](coordination_signal_list.md) -- invoice tier that navigates to this widget's page
