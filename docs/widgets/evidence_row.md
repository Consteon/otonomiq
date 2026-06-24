# EvidenceRow

Two side-by-side toggle buttons (note/photo) for P11 DeliveryWorkspace.

- **File:** [lib/widget/evidence_row.dart](../../lib/widget/evidence_row.dart)
- **Class:** `EvidenceRow` (StatefulWidget)
- **Status:** draft
- **Widget version:** v1

## Purpose

Provides two toggle buttons for attaching a note and a photo to the delivery. Tap toggles between inactive and active labels (active state shows an indigo check + filled background). LOCAL toggle state only -- no persistence this round.

## Component JSON

```json
{"type":"EVIDENCE_ROW","notePosition":7,"photoPosition":8,"text":"📝◆Tambah Catatan◆Catatan ditambah◆📷◆Ambil Foto◆Foto · 1"}
```

## DEFERRED

Write integration deferred. When writes land, notePosition:7 and photoPosition:8 will write to txfController[scrName][7] and [8].
