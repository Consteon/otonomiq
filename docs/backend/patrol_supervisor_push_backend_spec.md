# Backend Dev Spec — Patrol Report → Supervisor Push

**Status:** DRAFT · client side already built & device-confirmed · this spec covers the **server half only**
**Owner of this half:** backend/Cloud Functions team (needs deploy access to Firebase project `otq-01`)
**Date:** 2026-07-16

---

## 1. Goal & scope

**Goal:** when a driver submits a **patrol report**, the driver's **supervisor** receives a push notification (banner + in-app inbox thread + badge), automatically — no manual Firebase Console step.

**In scope (this spec):**
- A backend function that fires on a new patrol-report event, resolves the supervisor, looks up their FCM token, and sends **one data-only FCM message**.

**Out of scope:**
- Any client/Flutter change (client is done — see §2). The only possible client follow-up is a driver-facing `supervisorVid` field on the patrol form, and only if targeting **alt-1** is chosen (the recommended rule needs no form change — see §5).
- Inbox document writes. **The client is the sole writer of inbox docs** — the backend NEVER writes to `msg_*`. It only *sends* the FCM. (Prevents double-write.)

---

## 2. What already exists (client — do NOT rebuild)

Device-confirmed working (Redmi Note 8, Android 11):

| Piece | Where | Behaviour |
|---|---|---|
| FCM token capture | `firebase_notification_handler.dart` `_registerToken` | token → Redux `#FCM_TOKEN`, refreshed on `onTokenRefresh` |
| Token persisted to Firestore | `api.dart:3506-3527` (`launchCheck`, login path) | token written to field **`f`** on the user's **msg owner doc** (see §6.B) |
| Push receiver | `firebase_notification_handler.dart` `onMessage` + `myBackgroundMessageHandler` | foreground + background isolate |
| Bridge push → inbox | `bridgePushToInbox()` | writes the inbox thread + message doc from the FCM `data` payload |
| Banner | `flutter_local_notifications` channel `otonomiq_push_channel` | built from `data['nm']` / `data['dp']` |
| Inbox UI + badge | `notification_list.dart`, `message_list.dart`, bottomBar | streams `snapshots()` live → auto-updates on write |

**Consequence for backend:** the backend's entire job is **send a correctly-shaped data-only FCM to the supervisor's token**. The client does everything after that.

---

## 3. Architecture (end-to-end)

```
Driver submits patrol report (SDUI form)
  → addToEvent bundled into tableString → historySync → Firestore  [EXISTS]
  → callEventFunction() → HTTP ping to backend eventFunction        [EXISTS]
  ───────────────────────── BACKEND (this spec) ─────────────────────────
  → detect new patrol event
  → resolveSupervisorVid(event)                    [DECISION §5]
  → lookup supervisor FCM token (msg_<clt> where v==vid → f)  [§6.B, CONCRETE]
  → messaging().send({ token, data:{threadVid,nm,pp,dp,dt,route} })  [§6.C]
  ────────────────────────────────────────────────────────────────────────
  → supervisor device receives data-only FCM
  → client bridge writes inbox → banner + badge + thread  [EXISTS §2]
```

---

## 4. Prerequisites (blockers)

1. **Deploy access** to Firebase project **`otq-01`** (senderId `721538991284`) Cloud Functions / the existing `eventFunction` backend. Without this, nothing ships.
2. **Admin SDK credentials** (service account) for the function runtime — for both Firestore reads and `admin.messaging()`.
3. A **sample patrol-report event document** from a live tenant, to confirm the event schema (§6.A). The event columns are **tenant-defined** (diamond-separated `◆`), so the field map must be read off a real doc, not assumed.

---

## 5. Decisions required (2)

### Decision 1 — Targeting rule: who is the "supervisor"?

**INVESTIGATED 2026-07-16 (from code) — RESOLVED:** patrol reports do **NOT** carry an approver chain. The approval chain (`chainStr` = `[[level,status,vid,…]]`, `_expandEventLevels` `api.dart:4688`) is a separate multi-level **task-approval** mechanism embedded in approval-flow documents (approval RBTs: `list_item_card.dart:371`, `ftz_row_of_button_2.dart:112`) — never attached to patrol events. A patrol event (`scopePatrolEvents`, `statistic_card_support.dart:107`) carries only: `ty` (type ~"patrol"), **`av` = cost-center vid (`ccVid`)**, `ln` (location), `t` (epoch). There is **no person-level supervisor/approver field** on a patrol event, and **no pre-existing cost-center→supervisor mapping** anywhere in the code.

⇒ **Reusing `approverVid` is NOT viable** — patrol has no approver. The only scope key patrol carries is **`av` (cost-center)**, so the supervisor must be resolved *from the cost-center*.

| Opt | Rule | Cost |
|---|---|---|
| **(REC)** add **`supervisorVid`** on the **cost-center / site doc** that `av` (`ccVid`) points to → CF resolves `event.av → site doc → supervisorVid` | +1 config field per cost-center; **driver form unchanged** |
| alt-1 | `supervisorVid` chosen/inherited on the patrol **form** itself (event carries it directly) | driver-facing field; per report |
| alt-2 | role lookup: workforce `role=='supervisor'` scoped to `av` | needs a supervisor role + scope model |

> **Recommendation:** hang **`supervisorVid`** (or an **array**, if a cost-center has several supervisors) on the **cost-center / site record** keyed by `av`. Config-time (set once per site), invisible to the driver, resolved by CF in one read. Keep `resolveSupervisorVid(event)` swappable.

**CONFIRMED record locations (`list_multiple_panel_card.dart:155-167`):** cost-center/site records and patrol events are **sibling subcollections under one keyed-table doc**:
```
MobileTable/{appVid}/tables/{tableDocId}/site        ← cost-center/site docs  (fields: sv=site vid, av=cost-center vid, ll[]=points{ln,li,la,lo,ra}, + tenant config cols)
MobileTable/{appVid}/tables/{tableDocId}/event       ← patrol events (scoped by av)   ⚠️ CONFIRM this is the patrol write target vs evnt_<clt> (§6.A)
MobileTable/{appVid}/tables/{tableDocId}/workforce   ← people (drivers etc.)
```
- The `site` doc is a **keyed-table row** → a new **`supervisorVid`** column can be added/edited at config time via the normal table CRUD (proxy sheet). **No person/owner field exists on it today** — none to reuse.
- **CF resolution:** patrol `event.av` → query sibling `.../site` where `av == event.av` limit 1 → `supervisorVid`. One read, same `tableDocId`.

### Decision 2 — Thread identity (`threadVid`)
`threadVid` = the inbox thread key in the **supervisor's** inbox. Choose:
- **RECOMMENDED: `threadVid = driverVid`** → supervisor sees one thread per driver ("Budi — Patrol"). Natural grouping.
- Alternative: a constant like `"PATROL_REPORT"` → all patrol reports in one thread. Simpler, but no per-driver separation.

---

## 6. Data contracts

### 6.A — Event input (READ; schema tenant-defined — CONFIRM)
- Collection: **`evnt_<clt>`** (`eventPrefix="evnt_"`, `clt` = tenant cluster, default `DEV2`). Live example: `evnt_DEV2`.
- Patrol report identified by its type field (`ty` contains `"patrol"`).
- The function must extract, from the event: **driver vid** (event owner), **location/summary text** (`ln`), **timestamp** (`t`), and **`av` (cost-center)** for targeting (§5.1). Driver **display name / photo** for the banner can be read from the driver's own msg doc (`msg_<clt>` where `v==driverVid` → `n`,`p`; §6.B) if not present on the event.
- ⚠️ Column positions are **diamond-separated (`◆`) tenant config**. Read them off a real doc + the patrol screen's `addToEvent` template. Do not hardcode indices blindly.

> **Strong recommendation:** implement this **inside the existing `eventFunction`** rather than a fresh Firestore trigger — that backend already parses events and has the schema. See §7.

### 6.B — Supervisor FCM token lookup (READ; CONCRETE ✅)
The live token lives on the **msg owner doc**, NOT the user doc.

```
collection:  msg_<clt>                     // msgPrefix="msg_", e.g. msg_DEV2
query:       where('v', '==', supervisorVid).limit(1)
doc fields:  v = vid (owner)
             f = FCM token          ← THIS
             n = display name
             p = photo url
```
- **Cluster `<clt>`:** the supervisor's cluster. Derive from the supervisor's user doc `users_<fsName>` where `vid == supVid` → field `clt`; or use the deployment's fixed cluster (default `DEV2`) if single-cluster. (`clt` is NOT the same as `appVid` — `appVid` scopes `MobileTable`, `clt` scopes `msg_*`.)
- `msgId` is a **random doc id**, not derivable from vid → you must **query by `v`**, not `.doc(vid)`.
- If no doc, or `f` is null/empty → supervisor has never logged in on a device → **skip silently** (log info).
- ⚠️ **Do NOT** read `fcm` from `users_<fsName>/<vid>` — that field is written by the **deprecated** `userIntegrityCheck` and is unreliable. Use `f` on the msg doc.
- **Single device only in v1:** `f` holds one token (last login wins). Multi-device would need the client to store a token array — out of scope here.

### 6.C — FCM message to send (WRITE; CONCRETE ✅)
**Data-only** message (no `notification` block — the client builds the banner; adding a `notification` block would double-banner on Android because the bg isolate also shows one).

```jsonc
{
  "token": "<supervisor f>",
  "data": {
    "threadVid": "<driverVid>",          // REQUIRED — §5 Decision 2. Missing → client drops silently.
    "nm": "Budi Santoso",                // thread display name (driver)
    "pp": "https://.../driver.jpg",      // driver photo url (may be "")
    "dp": "Laporan patrol baru — Pos 3", // human banner/preview text
    "dt": "{\"eventId\":\"...\",\"type\":\"patrol\"}", // JSON string, app-processed payload (may be "")
    "route": "patrol_detail"             // SDUI screen name to open on tap (may be "" for no deeplink)
  },
  "android": { "priority": "high" }
}
```
- All values must be **strings** (FCM `data` is `map<string,string>`).
- `threadVid` missing/empty → the client's `parseFcmPayload` returns null and drops the message. Always set it.
- `route` must be a screen name present in the supervisor's SDUI cache for the deeplink to navigate; unknown/empty → banner still shows, tap is a no-op (safe).

### 6.D — What the client writes afterward (FYI — backend does NOT write this)
On receipt, the client bridge writes (sole-writer):
```
msg_<clt>/<supMsgId>/io/<threadVid>          → { nm, pp, lm:dp, lt:<now>, urd:++ , la:0 }
msg_<clt>/<supMsgId>/io/<threadVid>/msg/<id> → { dp, dt, tr:<now>, im:true, id, st:0, rt:route }
```
Documented so the backend understands the payload's downstream shape. **Do not replicate on the server.**

---

## 7. Implementation

### Option A (RECOMMENDED) — extend the existing `eventFunction`
`callEventFunction()` (`api.dart:102`) already pings the backend `eventFunction` on every submit (via `Uri.https(functionFront, eventFunctionName)` with `{ssid}`). That backend already parses events. Add a step there:

```
after existing event processing:
  for each newly-processed patrol event (ty ~ "patrol"):
    const supVid = resolveSupervisorVid(event)      // §5.1
    if (!supVid) continue
    const token = await lookupToken(clt, supVid)     // §6.B
    if (!token) continue
    await admin.messaging().send(buildMsg(event, supVid, token))  // §6.C
```
Pros: reuses event schema knowledge; runs exactly when a report is submitted; no new trigger wiring.

### Option B — new Firestore-triggered Cloud Function
If events are readable as discrete Firestore docs and a trigger is preferred:

```ts
// functions/src/patrolPush.ts  (Node 18, firebase-admin)
import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
admin.initializeApp();
const db = admin.firestore();

export const patrolSupervisorPush = functions.firestore
  .document("evnt_{clt}/{docId}")          // CONFIRM exact path/granularity (§6.A)
  .onCreate(async (snap, ctx) => {
    const ev = parseEvent(snap.data());     // CONFIRM diamond-column map
    if (!/patrol/i.test(ev.type)) return;

    const supVid = resolveSupervisorVid(ev); // §5.1 — swappable
    if (!supVid) return;

    const clt = ctx.params.clt;
    const q = await db.collection(`msg_${clt}`)
                      .where("v", "==", supVid).limit(1).get();     // §6.B
    if (q.empty) return;
    const token = q.docs[0].get("f");
    if (!token) return;

    try {
      await admin.messaging().send({
        token,
        data: {
          threadVid: ev.driverVid,           // §5.2
          nm: ev.driverName ?? "",
          pp: ev.driverPhoto ?? "",
          dp: `Laporan patrol — ${ev.location ?? ""}`.trim(),
          dt: JSON.stringify({ eventId: snap.id, type: "patrol", vid: ev.driverVid }),
          route: "patrol_detail",            // or "" — CONFIRM screen name
        },
        android: { priority: "high" },
      });
    } catch (e: any) {
      if (e?.errorInfo?.code === "messaging/registration-token-not-registered") {
        await q.docs[0].ref.update({ f: admin.firestore.FieldValue.delete() }); // §8 stale cleanup
      } else {
        console.error("[patrolPush] send failed", e);
      }
    }
  });
```

> `parseEvent` and `resolveSupervisorVid` are the two adapters to fill in from the confirmed schema + Decision 1. Everything else is final.

---

## 8. Error handling & edge cases

| Case | Handling |
|---|---|
| Supervisor never logged in (no msg doc / no `f`) | skip silently, log info |
| Stale token (`messaging/registration-token-not-registered`) | delete `f` on the msg doc; client rewrites on next login |
| Duplicate/re-fire of the same event | dedup on `eventId` (e.g. write a `pushSent` marker or use a processed-set); onCreate normally fires once |
| Driver == supervisor (self-report) | optional: skip if `supVid === driverVid` |
| Multiple supervisors (option c) | loop tokens; use `sendEachForMulticast` |
| `threadVid` empty | never send — the client would drop it anyway |

---

## 9. Testing

1. **Token lookup:** manually run the `msg_<clt> where v==<supVid>` query in Firebase console → confirm `f` present for a test supervisor who has logged in on a device.
2. **Send path (before wiring the trigger):** the client is already verified via Firebase Console → *Send test message* → **Additional options → Custom data** with keys `threadVid,nm,pp,dp,dt,route` targeting the supervisor's token. This is the exact payload the CF will emit — proves the client half independent of the backend.
3. **End-to-end:** driver submits a real patrol report → supervisor device gets banner + inbox thread + badge within seconds (device online).
4. **Regression:** confirm no double-banner (data-only, no `notification` block) and no duplicate inbox docs (backend never writes `msg_*`).

Device caveats (from client QA): Android **force-stop** kills FCM until manual relaunch (by design); MIUI/Redmi needs Autostart + no battery restriction; data-only is throttled harder in deep background than notification messages.

---

## 10. Open items to confirm before coding

- [ ] **Deploy access** to `otq-01` functions / `eventFunction` (§4).
- [x] **Decision 1 RESOLVED** — patrol has NO approver chain; events scoped by `av` = cost-center. Cost-center/site records CONFIRMED at `MobileTable/{appVid}/tables/{tableDocId}/site` (keyed-table row) — a `supervisorVid` column CAN be added there, no existing person field to reuse. RECOMMENDED rule = `supervisorVid` on that site doc; CF resolves `event.av → sibling /site → supervisorVid`. Remaining: the org must **populate** `supervisorVid` per cost-center. (§5.1, §6.A)
- [ ] **Decision 2** — `threadVid` = driverVid vs constant (§5.2).
- [ ] **Event write target** — patrol events are READ from the keyed-table sibling `.../event` subcollection (`list_multiple_panel_card.dart:164`); confirm the patrol `addToEvent` **writes** there (CF trigger = `MobileTable/{appVid}/tables/{tableDocId}/event/{id}`) vs the `evnt_<clt>` stream — + the diamond-column map for driverVid/name/location/type/`av`, from a live sample. (§6.A)
- [ ] **`route`** — is there a `patrol_detail` SDUI screen to deeplink to, or ship v1 with `route:""` (banner only, no tap-through)?
- [ ] Integration point — extend `eventFunction` (Option A, recommended) vs new Firestore trigger (Option B).
