# SignaturePad

Hand-drawn stroke capture widget for P11 DeliveryWorkspace using CustomPaint + GestureDetector.

- **File:** [lib/widget/signature_pad.dart](../../lib/widget/signature_pad.dart)
- **Class:** `SignaturePad` (StatefulWidget)
- **Status:** draft
- **Widget version:** v1

## Purpose

Provides a signature capture area for customer confirmation. Empty state shows a placeholder with a dashed slate border (drawn via a small CustomPaint dashed-border decoration); filled state shows the signature with a solid emerald border and a "Hapus" clear control. No pub package dependency -- uses Flutter's built-in CustomPaint.

## Component JSON

```json
{"type":"SIGNATURE_PAD","optional":true,"position":3,"writeField":"sig","text":"placeholder◆clearLabel◆hintEmpty◆hintFilled"}
```

## DEFERRED

Strokes are LOCAL widget state only. No image-bytes export, no txfController write this round. When writes land, position:3 and writeField:"sig" will be used.
