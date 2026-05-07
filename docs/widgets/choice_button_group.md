# ChoiceButtonGroup

A group of selectable buttons with icons, colors, and optional chained actions (navigation, dialogs, API calls).

- **File:** [lib/widget/choice_button_group.dart](../../lib/widget/choice_button_group.dart)
- **Class:** `ChoiceButtonGroup` (StatefulWidget)
- **Status:** done
- **Widget version:** v1
- **Dependencies:** `get`, `http`

## Purpose

Renders a grid of choice buttons (up to 3 per row) where the user selects one option. Each button can:
1. Navigate to a route directly (`do_next`).
2. Show a confirmation/warning dialog first (`do_dialog`) with its own set of action buttons.
3. Call an external API (`hitapi`) before continuing.

Use this widget for status selection flows (e.g. "Good / Warning / Critical") where the choice triggers navigation or side effects.

## Signature / Constructor

```dart
const ChoiceButtonGroup({
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
| `key` | `Key` | yes | — | Unique key per instance |
| `component` | `dynamic` | yes | — | Component config (see shape below) |
| `scrName` | `String` | yes | — | Screen this widget is mounted on |
| `lPad`/`tPad`/`rPad`/`bPad` | `double` | yes | — | Left/top/right/bottom padding |

### `component` shape

| Key | Type | Description |
|---|---|---|
| `label` | `String?` | Group label displayed above the buttons. Hidden if empty. |
| `labelBadge` | `String?` | Red badge text shown next to the label (e.g. "Required"). Hidden if empty. |
| `children` | `List<dynamic>` | Array of button definitions (see button shape below). |
| `beforeSpacing` | `num?` | Top margin in px. Default `0`. |
| `afterSpacing` | `num?` | Bottom margin in px. Default `0`. |
| `leftPadding` | `num?` | Additional left padding (added to `lPad`). Default `0`. |
| `rightPadding` | `num?` | Additional right padding (added to `rPad`). Default `0`. |

### Button shape (each item in `children`)

| Key | Type | Description |
|---|---|---|
| `value` | `String` | Unique identifier for this choice. Used to track selection state. |
| `text` | `String` | Diamond-separated (`◆`). If contains `◆`, part after first diamond is the display label; otherwise entire string is the label. |
| `color` | `String?` | Color keyword: `"green"`, `"yellow"`, `"red"`, `"neutral"`. Default `blueGrey`. |
| `icon` | `String?` | Icon keyword: `"check"`, `"warning"`, `"alert"`, `"siren"`. Default radio button. |
| `route` | `String?` | Route to navigate to after selection (only if chain resolves to `do_next`). |
| `chain` | `String/Map?` | Chain action config — JSON string or Map. See chain section below. |

### Chain action config

The `chain` field controls what happens after a button is tapped. It can be a JSON string or a Map.

| Key | Type | Description |
|---|---|---|
| `type` | `String` | `"do_next"` — navigate immediately. `"do_dialog"` — show confirmation dialog first. |
| `title` | `String` | Dialog title (only for `do_dialog`). |
| `description` | `String` | Dialog body text (only for `do_dialog`). |
| `icon` | `String` | Dialog icon keyword: `"siren"` (🚨), `"warning"`, etc. |
| `buttons` | `List` | Dialog action buttons (see dialog button shape). |

### Dialog button shape (each item in chain `buttons`)

| Key | Type | Description |
|---|---|---|
| `text` | `String` | Button label. `◆` characters are replaced with spaces. |
| `color` | `String?` | Color keyword. `"neutral"` renders as grey. |
| `action` | `String?` | `"hitapi"` — calls external API before continuing. |
| `apiUrl` | `String?` | Full URL for the API call (required when action is `hitapi`). |
| `apiMethod` | `String?` | HTTP method: `"POST"` (default) or `"GET"`. |
| `apiBody` | `dynamic?` | Request body (JSON-encodable). Defaults to `{}`. |
| `next` | `String/Map?` | Nested chain config. If `type` is `"do_next"`, navigates to the original route after dialog closes. |

## Color & Icon Mapping

### Colors

| Keyword | Color | Typical use |
|---|---|---|
| `green` | `Colors.green` | Good / OK / Normal |
| `yellow` | `Colors.amber` | Warning / Caution |
| `red` | `Colors.red` | Critical / Alert / Danger |
| `neutral` | `Colors.grey` | Cancel / Skip |
| (other) | `Colors.blueGrey` | Default fallback |

### Icons

| Keyword | Icon | Typical use |
|---|---|---|
| `check` | `check_circle_outline` | Good / Confirmed |
| `warning` | `warning_amber_rounded` | Warning state |
| `alert` | `cancel_outlined` | Critical / Error |
| `siren` | `campaign` | Emergency / Alarm |
| (other) | `radio_button_unchecked` | Default / unselected |

## Usage Example (Screen JSON)

### Basic 3-button group with direct navigation

```json
{
  "type": "CHOICE_BUTTON_GROUP",
  "label": "Condition Assessment",
  "labelBadge": "Required",
  "children": [
    {
      "value": "good",
      "text": "status◆Good",
      "color": "green",
      "icon": "check",
      "route": "next_screen",
      "chain": { "type": "do_next" }
    },
    {
      "value": "warning",
      "text": "status◆Warning",
      "color": "yellow",
      "icon": "warning",
      "route": "next_screen",
      "chain": { "type": "do_next" }
    },
    {
      "value": "critical",
      "text": "status◆Critical",
      "color": "red",
      "icon": "alert",
      "route": "next_screen",
      "chain": { "type": "do_next" }
    }
  ]
}
```

### With confirmation dialog and API call

```json
{
  "type": "CHOICE_BUTTON_GROUP",
  "label": "Emergency Action",
  "children": [
    {
      "value": "trigger_alarm",
      "text": "action◆Trigger Alarm",
      "color": "red",
      "icon": "siren",
      "route": "alarm_active_screen",
      "chain": {
        "type": "do_dialog",
        "title": "Confirm Emergency",
        "description": "This will trigger the site alarm and notify all personnel. Are you sure?",
        "icon": "siren",
        "buttons": [
          {
            "text": "Cancel",
            "color": "neutral",
            "next": null
          },
          {
            "text": "Confirm◆Alarm",
            "color": "red",
            "action": "hitapi",
            "apiUrl": "https://api.example.com/alarm/trigger",
            "apiMethod": "POST",
            "apiBody": { "site": "warehouse-A", "level": "critical" },
            "next": { "type": "do_next" }
          }
        ]
      }
    }
  ]
}
```

## Flow Diagram

```
User taps button
       │
       ▼
setState(selectedValue)
       │
       ▼
chain exists? ──No──► navigate(route)
       │
      Yes
       │
       ▼
chain.type?
       │
  ┌────┴────┐
  │         │
do_next   do_dialog
  │         │
  ▼         ▼
navigate  Show dialog
(route)     │
            ▼
      User taps dialog button
            │
        ┌───┴───┐
        │       │
   action?    no action
   hitapi       │
        │       ▼
        ▼    next.type == do_next?
   call API     │
        │      Yes → navigate(route)
        ▼
   next.type == do_next?
        │
       Yes → navigate(route)
```

## State / Bloc / Dependencies

- **State:** Local `_selectedValue` — tracks which button is currently selected (highlighted). Resets on widget rebuild.
- **Navigation:** Uses `routeStack.push(route)` + `gotoRoute(route)` from `global.dart`. Only navigates if `routeExist(route)` returns true.
- **HTTP:** Uses `package:http` for API calls. Fire-and-forget — errors are caught and logged via `debugPrint`.
- **GetX:** Uses `Get.dialog()` for showing the chain dialog and `Get.back()` to dismiss it.

## Important Behavior

- **Grid layout** — buttons wrap with max 3 per row. If `children.length ≤ 3`, all fit in one row with equal width. If more than 3, wraps to next row.
- **Selection is visual only** — `_selectedValue` is local state. It does not write to `txfController` or any external store. The meaningful action happens via `chain` (navigation or API call).
- **Chain is optional** — if no `chain` is provided, tapping the button navigates directly to `route`.
- **Dialog blocks navigation** — when `chain.type == "do_dialog"`, the route navigation only happens if the user clicks a dialog button whose `next.type == "do_next"`.
- **API is fire-and-forget** — `_hitApi` does not check response status or report errors to the user. It sends the request and moves on.
- **Diamond in button text** — `◆` in dialog button text is replaced with spaces for display. In choice button text, it splits the string and uses the second part as the visible label.
- **Animated selection** — 200ms transition when a button becomes selected (background fills with full color, icon/text turn white).

## See Also

- [ftz_row_of_button_2.md](ftz_row_of_button_2.md) — submit/action button row (different purpose: form submission vs. choice selection)
