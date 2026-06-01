# addToEvent (Firestore event ledger)

Sibling of `addToTable`. When a component JSON has `addToEvent`, the submit ALSO
writes a keyed document into a named Firestore collection — in addition to the
existing spreadsheet Event row (unchanged).

## Flow
`saveSend` / `checkerSaveData` append the event string as the **4th `⬤` segment**
of `tb` (`add⬤update⬤delete⬤event`). At `historySync` (online), `tbParts[3]` →
`writeToEvent()`:
1. `autheniumDecode` → split by `◆` (separator[1]) into blocks.
2. `parseAddToEvent` — split `⭘` (sep[8]) → first part = collection, rest split at
   first `◼` (sep[2]) into key/value (`lib/firestore_repository/add_to_event.dart`).
3. `resolveValueTokens` — `◀N▶`=system/ref[0], `◁N▷`=form/ref[1] (shared with
   addToTable; extracted from `parseTableInput`).
4. Build the doc from EXACTLY the DSL fields (token-resolved); `_collection` is
   dropped (it is the write target). No blank-prefill — codes not written in the
   DSL are absent from the document.
5. Write under the same location as `addToTable` (so existing MobileTable rules
   apply): `MobileTable/<tableVid>/tables/<getDocumentName(line1)>/content/<autoId>`,
   batched atomically (`WriteBatch`). `tableVid` comes from the `tablevid` field,
   else the appCode default.

## Notes
- `et/p/ev/ld` (Event-tab cols A–D) are NOT addToEvent fields — they remain on the
  spreadsheet path (`appendToSheet`).
- `rf` `<no_request>` resolves at submit via `_resolveScreenTxMarkers` (screenTx key),
  same as addToTable.
- Token output is string; no type coercion.
- Offline-first: rides the same history queue as addToTable; the write happens at the
  next `historySync` (immediately if online).

## Not yet implemented
- Approval-chain `addToEvent` (FtzRowOfButton2 `_updateApprovalChain` /
  `createApprovalEvent`, parent ref-id for `rf`) — deferred to a separate plan.
