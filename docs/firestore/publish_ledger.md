# publishLedger (pub-sub-gateway)

Sibling of `addToEvent`, but the target is NOT Firestore: when a component JSON has
`publishLedger`, the submit ALSO publishes a JSON message to the backend
`pub-sub-gateway` (Cloud Run) over HTTPS POST. Everything else about the submit —
the spreadsheet Event row, `addToTable`, `addToEvent`, push notifications — is
unchanged.

## Flow

`saveSend` (`lib/api.dart`) appends the publish string as the **6th `⬤` segment** of
`tb`. When a publish is present, ALL SIX segments are emitted (empty strings for
absent ones): `add⬤update⬤delete⬤event⬤updateEvent⬤publish`. When it is absent, the
three legacy forms (3 / 4 / 5 segments) are byte-identical to before.

```
saveSend                    buildPublishSegment: ⬤ -> space, append ⭘_k◼<uuid v4>
   │                        (the Idempotency-Key is minted AT TAP TIME)
   ▼
_HISTORY (local queue, offline-safe; images upload first)
   │
   ▼
historySync  tbParts[5] -> enqueueLedgerPublish   (NOT tallied — see "Not tallied")
   │                        buildLedgerEntry: parse, resolve tokens, gs:// photos,
   │                        inject actionAt, encode the body ONCE, validate
   ▼
_LEDGER_OUTBOX (secure storage)
   │
   ▼
drainLedgerOutbox  (kicked once at the end of every historySync, un-awaited)
   ▼
POST {GATEWAY_URL}/v1/ledgers/{ledgerCode}/messages
```

## Config format (final, owned by the config owner)

```
"publishLedger": "<ledgerCode>⭘_v◼<schemaVersion>⭘<field>◼<value>⭘<field>◼<value>…"
```

* `⭘` = `separator[8]`, `◼` = `separator[2]` — the same dialect as `addToEvent`, parsed
  by the same `parseAddToEvent` (`lib/firestore_repository/add_to_event.dart`).
* `<ledgerCode>` must be a **literal** matching `^[A-Z0-9]{4,16}$` (no `◁N▷`, `{…}` or
  `<…>` token). The URL carries a Firebase ID token, so the target must not be
  resolvable at runtime.
* `<value>` may be a literal, a form slot (`◁N▷` = form position N, **no +1**), or a
  system slot (`◀N▶`). Tokens resolve at **sync time** via `resolveValueTokens`,
  exactly as for `addToEvent`.
* Keys starting with `_` are **meta** and never enter `data`:
  * `_v` → `schemaVersion` (must parse as `int`);
  * `_k` → `Idempotency-Key`, appended by the app — do not write it;
  * any other `_x` is ignored.
* `actionAt` is **app-owned**: always injected as the history record time
  (`getRealTime()` at tap: NTP when online, device clock + GPS correction offline),
  string epoch ms. A config-written `actionAt` is overwritten.
* Every `data` value is emitted as a **String**. Type coercion is the gateway's job.

Example:

```
"publishLedger": "TESTMOBILE⭘_v◼1⭘requestType◼leave⭘days◼◁3▷"
```

produces

```json
{"schemaVersion": 1,
 "data": {"requestType": "leave", "days": "2", "actionAt": "1789101600000"}}
```

## Photo references

Every Firebase Storage download URL inside a value becomes
`gs://<bucket>/<decoded path>`. The bucket is always written: uploads go to
`gs://otq-01-ase2` but the app's lost-photo placeholder lives in another project's
bucket.

The `defaultImage` placeholder (`lib/global.dart:552`) is stripped to an **empty
string BEFORE** the URL conversion — it is itself a download URL, so converting first
would publish a real object path in a foreign bucket as if it were the user's photo.
A blanked placeholder is reported to Crashlytics. If the schema makes the photo
required the gateway answers `4xx`, and the entry is marked failed.

The conversion is separator-agnostic: a value holding several photos converts every
URL whether they are space-joined (the shape after `stringCleanUp` replaces `◇` with a
space) or `◇`-joined.

## Entry states (`_LEDGER_OUTBOX`)

| State | Fields | Meaning |
|---|---|---|
| pending | `attempted:false` | queued, never on the network |
| in flight / unknown | `attempted:true` | the bytes reached the network at least once; `attempted` is persisted BEFORE the POST |
| held | `notBefore > now` | 5xx / timeout; `Retry-After` honoured (seconds only) |
| failed | `failed:true`, `error`, `errorId`, `failedAt` | terminal. Never re-sent. Trimmed 30 days after `failedAt` |

`invalid_config` is a failed entry created at enqueue time with an **empty body**: the
ledgerCode did not match, `_v` was missing/not an int, `_k` was missing, or the encoded
body exceeded 256 KiB.

## Decision table

| Status | Outcome | Drain behaviour |
|---|---|---|
| `202`, incl. `duplicate:true` | success | remove entry, continue |
| `400` `404` `405` `409` `413` `422`, any other non-401 4xx | rejected | mark failed, `errorReport`, **continue** to the next entry |
| `401` after ONE forced token refresh | unauthenticated | keep entry, **stop the cycle**, do NOT sign out |
| `500` `503` + any other 5xx, timeout, socket/`ClientException`, non-JSON 5xx | retryable | `notBefore = now + Retry-After`, **stop the cycle** |

A `duplicate:true` answer means the gateway already published this
`(user, ledgerCode, key)` within its 24 h window. It is success, not an error.

## Notes

- **Offline-first.** The Idempotency-Key is minted at tap time and lives inside the `tb`
  segment of the history record, so it survives an app close. The outbox entry itself
  is created the first time `historySync` processes the record, which requires internet
  (the enqueue sits inside `historySync`'s `if (internetConnected())` arm). The action
  is never at risk in the meantime — it is in `_HISTORY`.
- **A failed keystore read costs that one publish, never the whole outbox.**
  `loadLedgerOutbox` reads `storage` DIRECTLY rather than through `secureRead` (which
  returns null for both "key absent" and "read threw"), so a read failure at the enqueue
  moment propagates out of `enqueueLedgerPublish` — reported to Crashlytics by
  `historySync`'s own catch, which names the `historyId` — and leaves `_outbox` null so
  `saveLedgerOutbox` stays a no-op: the accepted cost is losing that single publish
  instead of overwriting the N stored entries with a blank list.
- **The body is encoded once.** Every attempt sends byte-identical bytes. Rebuilding the
  map and re-encoding risks `409 idempotency_conflict`.
- **Not tallied.** `enqueueLedgerPublish` never calls `tally`, never touches
  `opsAttempted` / `opsSucceeded`, and never changes `allFailed` / `partial` /
  `moreHistory`. The history queue's send / retry / partial / drop semantics are
  byte-identical to before (owner decision K4). The call sits BEFORE the CRUD `try`, so
  a CRUD throw cannot skip it.
- **Its own lock.** `ledgerDrainLock` is separate from `historySyncLock`, so a slow or
  down gateway never delays the history queue. `drainLedgerOutbox` is called
  un-awaited via `safeUnawaited` and catches everything internally — an escaping error
  would be recorded as a FATAL by `platformDispatcher.onError`.
- **`GATEWAY_URL` is build-time only**, never from a sheet, config or Firestore: the
  request carries a Firebase ID token and an editable URL would let anyone with sheet
  access redirect it. The compiled-in default is the otq-01 gateway
  `https://pub-sub-gateway-721538991284.asia-southeast2.run.app`, so a plain
  `flutter run` or release build publishes without a flag. Override with
  `--dart-define=GATEWAY_URL=…` (e.g. a local gateway). The value must be a bare
  https origin — a trailing `/` is fine, a path such as `/v1` is not (the client
  builds `/v1/ledgers/…` itself and would silently drop it). An explicitly empty
  define, or a value that fails those checks, turns the feature off → entries stay
  queued, ONE `errorReport` per app session, no crash.
- **Payload stays out of crash reports.** Crashlytics reports carry `ledgerCode`,
  key, status, `error` and `errorId` only. In DEBUG builds only (`devPrint`, silent
  in release) the drain logs `[ledger] request … body=…` before each POST and
  `[ledger] response … body=…` after it, bodies clipped at 2000 chars. The ID token
  is never logged — the drain never sees it.
- **User switching.** An entry is bound to the UID that created it and is only sent while
  that UID is signed in. `signOut` clears the outbox along with `_HISTORY`.
- **Native-submit widgets.** `task_create_submit` and `nota_create_submit` reach
  `saveSend` through `emitSubmitEventRow` → `eventComponent`, which strips the five
  write-DSL verbs and `route` but **not** `publishLedger` — that is intended. On that
  path only the slots the widget seeds itself exist: `task_create_submit` writes
  positions 11–14 (`writeEventSlots`, `lib/widget/task_create_submit.dart:292`) plus
  its `tnm` slot, `nota_create_submit` its number slot. Use `◁N▷` only for those
  positions; otherwise use literals or `◀N▶` system slots.

## Out of scope (phase 1)

- Writing a failed-status document to Firestore for `4xx` (phase 2 — needs the path,
  doc shape and security rules: spec Q3).
- Supersede of `addToEvent` (owner decision O2 open — both verbs run today).
- App Check (`X-Firebase-AppCheck`); the gateway runs `APP_CHECK_MODE=log`.
- `checkerSaveData` (`lib/widget/ftz_checker.dart`) composes its own `tb` and is untouched.
- The approval chain (`createApprovalEvent` passes `tableString: null`) cannot carry a
  publish segment.

## Tests

- `test/gateway_client_test.dart` — HTTP outcome mapping, headers, body bytes, 401
  refresh-once, `Retry-After`, non-JSON 5xx (`MockClient`).
- `test/ledger_publish_build_test.dart` — compose helper, `tb` length guard, builder
  validation, photo conversion.
- `test/ledger_outbox_drain_test.dart` — drain decisions, skips, FIFO, 30-day trim,
  enqueue idempotency.
