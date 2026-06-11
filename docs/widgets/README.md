# Widget Documentation

Documentation for the custom widgets in [lib/widget/](../../lib/widget/).

## How to Add a New Widget Doc

1. Copy [_template.md](_template.md) to `<widget_name>.md` (matching the Dart file name, e.g. `otq_txf_2.md`).
2. Fill in each section based on the widget.
3. Add a new row to the index table below.
4. Remove sections that don't apply to that widget.

## Naming Convention

- The doc file name mirrors the `.dart` file name, with a `.md` extension.
  - Example: `lib/widget/otq_txf_2.dart` → `docs/widgets/otq_txf_2.md`
- Newer widget revisions ending in `_2` get their own doc file separate from the v1 doc, with cross-links in the "See Also" section.

## Widget Index

### Input / Form
| Widget | File | Status | Description |
|---|---|---|---|
| OtqTxf | [otq_txf.md](otq_txf.md) | todo | Text field |
| OtqTxf2 | [otq_txf_2.md](otq_txf_2.md) | example | Text field v2 (full-blown) |
| OtqRdo | [otq_rdo.md](otq_rdo.md) | todo | Radio button |
| OtqRdo2 | [otq_rdo_2.md](otq_rdo_2.md) | draft | Radio button v2 |
| OtqDropdown | [otq_dropdown.md](otq_dropdown.md) | todo | Dropdown |
| OtqDropdown2 | [otq_dropdown_2.md](otq_dropdown_2.md) | draft | Dropdown v2 |
| OtqCheckbox | [otq_checkbox.md](otq_checkbox.md) | todo | Checkbox |
| OtqSwitch | [otq_switch.md](otq_switch.md) | todo | On/off switch |
| OtqPin | [otq_pin.md](otq_pin.md) | todo | PIN input |

### Display
| Widget | File | Status | Description |
|---|---|---|---|
| BuildDisplayComponent | [build_display_component.md](build_display_component.md) | todo | Dynamic display builder |
| DisplayList | [display_list.md](display_list.md) | todo | List display |
| DisplayList2 | [display_list_2.md](display_list_2.md) | todo | List display v2 (source file currently empty — doc is a placeholder) |
| DisplayCard | [display_card.md](display_card.md) | todo | Card display |
| ListMultiplePanelCard | [list_multiple_panel_card.md](list_multiple_panel_card.md) | draft | Reusable card-list with N nav panels, config-driven layout/labels |
| ListStatisticCard | [list_statistic_card.md](list_statistic_card.md) | draft | Per-point patrol/cleaning statistic list with optional typed-location merge |
| TimelinePeriodic | [timeline_periodic.md](timeline_periodic.md) | draft | Config-driven event timeline (TIMELINE variant periodic) with period selector, badge chips, gap pills, image gallery |
| OtqFormattedText | [otq_formatted_text.md](otq_formatted_text.md) | todo | Text with formatter |
| TimePresence | [time_presence.md](time_presence.md) | done | Check-in time, live elapsed counter, and last action in 3-column card |

### Image / Media
| Widget | File | Status | Description |
|---|---|---|---|
| OtqGetImages | [otq_get_images.md](otq_get_images.md) | todo | Image picker/capture |
| OtqGetImages2 | [otq_get_images_2.md](otq_get_images_2.md) | draft | Image picker/capture v2 |
| FtzDisplayImages | [ftz_display_images.md](ftz_display_images.md) | todo | Image display |
| PhotoCamera | [photo_camera.md](photo_camera.md) | todo | Photo camera |

### Scanner / QR
| Widget | File | Status | Description |
|---|---|---|---|
| QrScan | [qr_scan.md](qr_scan.md) | todo | QR scanner |
| FtzMultiScan | [ftz_multi_scan.md](ftz_multi_scan.md) | todo | Multi-scan QR |
| FtzScannerScreen | [ftz_scanner_screen.md](ftz_scanner_screen.md) | todo | Scanner screen |

### Location / GPS
| Widget | File | Status | Description |
|---|---|---|---|
| LocationDetector | [location_detector.md](location_detector.md) | done | GPS location status with inside/outside site detection via LQR reference points |
| QrGps | [qr_gps.md](qr_gps.md) | todo | QR + GPS |
| GpsSend | [gps_send.md](gps_send.md) | todo | Send GPS coordinates |
| AttendanceQrSelfieGpsVerify | [attendance_qr_selfie_gps_verify.md](attendance_qr_selfie_gps_verify.md) | todo | Attendance verification (QR + selfie + GPS) |

### Action / Button
| Widget | File | Status | Description |
|---|---|---|---|
| FtzRowOfButton | [ftz_row_of_button.md](ftz_row_of_button.md) | todo | Button row |
| FtzRowOfButton2 | [ftz_row_of_button_2.md](ftz_row_of_button_2.md) | draft | Button row v2 |
| ChoiceButtonGroup | [choice_button_group.md](choice_button_group.md) | done | Selectable button grid with chain actions (navigation, dialog, API call) |

### Checklist / Progress
| Widget | File | Status | Description |
|---|---|---|---|
| Tasklist | [tasklist.md](tasklist.md) | draft | Single checklist task with bottom-sheet status picker; writes `title:value` to its own `txfController` slot |
| ProgressBar | [progress_bar.md](progress_bar.md) | draft | Visual aggregator over multiple `Tasklist` positions (no `position` field, no submit) |
| TaskProgressStore | [task_progress_store.md](task_progress_store.md) | todo | Singleton `ChangeNotifier` registry shared by `Tasklist` ↔ `ProgressBar` |

### Other
| Widget | File | Status | Description |
|---|---|---|---|
| FtzChecker | [ftz_checker.md](ftz_checker.md) | todo | Generic checker |
| FtzWebview | [ftz_webview.md](ftz_webview.md) | todo | Webview |
| FtzBluetoothPrinter | [ftz_bluetooth_printer.md](ftz_bluetooth_printer.md) | todo | Bluetooth printer |

> Status legend: `todo` = not yet documented, `draft` = in progress, `done` = complete, `example` = template/example doc.
