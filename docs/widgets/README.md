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
| AdminActiveTripList | [admin_active_trip_list.md](admin_active_trip_list.md) | draft | Active trip cards (plate, driver, stop progress) for Admin H1 BERJALAN |
| AdminCoordinationHeader | [admin_coordination_header.md](admin_coordination_header.md) | draft | Admin identity header (role, name+plate, translucent count chips) for H1 AdminHome |
| AssetStockList | [asset_stock_list.md](asset_stock_list.md) | draft | Generic pivot-cube stock distribution (entity x pivot x condition) with summary strip, filter tabs, and proportion bar |
| AdminOutstandingList | [admin_outstanding_list.md](admin_outstanding_list.md) | draft | Collapsible outstanding client list with aging-tier badges for Admin H1 PRIORITAS |
| CustomerOutstandingList | [customer_outstanding_list.md](customer_outstanding_list.md) | draft | Full-page customer outstanding lookup with search, category-colored chips, aging tiers, and detail sheet |
| AdminUpcomingTaskList | [admin_upcoming_task_list.md](admin_upcoming_task_list.md) | draft | Upcoming task cards with item roll-up and inline vehiclePicker for Admin H1 AKAN DATANG |
| PickerList | [picker_list.md](picker_list.md) | draft | Generic single-select picker (any collection); capture id→token, optional per-row count badge + ad-hoc row; capture/navigate modes. SDUI `picker_list` (alias `vehicle_picker`) |
| VehiclePickerSheet | [admin_vehicle_picker_sheet.md](admin_vehicle_picker_sheet.md) | draft | Reusable vehicle assign/reassign bottom-sheet (extracted from CoordinationSignalList) |
| CoordinationSignalList | [coordination_signal_list.md](coordination_signal_list.md) | draft | Admin signal list (cross-collection derive + assign/cross-nav actions) for H1 AdminHome |
| CirculationSummary | [circulation_summary.md](circulation_summary.md) | draft | Per-item cross-route circulation totals (Muat/Drop/Pickup) for P5 CustodyNotification |
| ClosingContextRail | [closing_context_rail.md](closing_context_rail.md) | draft | C1 driver + category context strip (green-tint) for WarehouseClosingCheck |
| CustodyCountList | [custody_count_list.md](custody_count_list.md) | draft | Blind stepper list for P6 CustodyCount, filtered by item category |
| CustodyStepHeader | [custody_step_header.md](custody_step_header.md) | draft | Title + plate + STEP badge header and vehicleId publisher for P6 CustodyCount |
| CustodyCountSubmit | [custody_count_submit.md](custody_count_submit.md) | draft | P6 send-button: writes ip[] natively then navigates to custodyReveal |
| CustodyReveal | [custody_reveal.md](custody_reveal.md) | draft | STEP 2/2 reveal + compare + branch (match/mismatch/recount) |
| CustodyConfirmedList | [custody_confirmed_list.md](custody_confirmed_list.md) | draft | P7 read-only list of driver-confirmed items (ip[] + item JOIN) |
| CustodyDiscrepancyList | [custody_discrepancy_list.md](custody_discrepancy_list.md) | draft | P8 read-only discrepancy grid (dp[] Warehouse/Lo Hitung/Selisih) |
| CustodyEventSubmit | [custody_event_submit.md](custody_event_submit.md) | draft | P7/P8 pre-resolve submit (curly tokens) then updateEventRow/addToEvent |
| EvidenceRow | [evidence_row.md](evidence_row.md) | draft | Two toggle buttons (note/photo) for P11 DeliveryWorkspace |
| ExecutorDesignateCard | [executor_designate_card.md](executor_designate_card.md) | draft | O1 driver-picker card (amber unset / teal set + workforce bottom-sheet) for WarehouseOpeningCheck |
| DisplayList | [display_list.md](display_list.md) | todo | List display |
| DisplayList2 | [display_list_2.md](display_list_2.md) | todo | List display v2 (source file currently empty — doc is a placeholder) |
| DisplayCard | [display_card.md](display_card.md) | todo | Card display |
| DriverStopCard | [driver_stop_card.md](driver_stop_card.md) | draft | Stop list + progress card (pending locked-preview / confirmed active) for DriverHome P4 |
| InventoryBucketCard | [inventory_bucket_card.md](inventory_bucket_card.md) | draft | Vehicle stock per condition bucket for DriverHome P4 |
| ItemExecutionList | [item_execution_list.md](item_execution_list.md) | draft | Per-item drop/pickup stepper list with status state-machine for P11 DeliveryWorkspace |
| ItemExecutionSubmit | [item_execution_submit.md](item_execution_submit.md) | draft | Atomic P11 submit: persists stepper actuals to task it[] + tst/tce via writeNativeFields |
| ListMultiplePanelCard | [list_multiple_panel_card.md](list_multiple_panel_card.md) | draft | Reusable card-list with N nav panels, config-driven layout/labels |
| ListStatisticCard | [list_statistic_card.md](list_statistic_card.md) | draft | Per-point patrol/cleaning statistic list with optional typed-location merge |
| NavActionCard | [nav_action_card.md](nav_action_card.md) | draft | Return-vehicle CTA card (muted/active by allClosed) for DriverHome P4 |
| NoticeBar | [notice_bar.md](notice_bar.md) | draft | Notification strip/callout with variant-driven colors, optional icon, up to 3 text tiers |
| OfflineBannerHost | [offline_banner.md](offline_banner.md) | draft | Global offline strip above the MainPage body (Obx on internetConnectionFlag); structural shell widget, not a dispatch branch |
| ReturnHeader | [return_header.md](return_header.md) | draft | Back arrow + label + title header for P12 ReturnVehicle |
| PreconditionGateCard | [precondition_gate_card.md](precondition_gate_card.md) | draft | Custody gate card (pending/confirmed) for DriverHome P4 |
| ReceiptDoc | [receipt_doc.md](receipt_doc.md) | draft | Read-only on-screen nota card (config-named scalar fields + li[] line loop + depo header lookup); SDUI `RECEIPT_DOC` |
| RouteFeedHeader | [route_feed_header.md](route_feed_header.md) | draft | Sticky 3-row route header (identity, progress, drop/pickup stats) and vehicleId publisher for P10 TaskFeed |
| RouteProgressHeader | [route_progress_header.md](route_progress_header.md) | draft | Driver identity header with workforce lookup and vehicle publish |
| TaskCreateSubmit | [task_create_submit.md](task_create_submit.md) | draft | Submit button for Admin create-task wizard (P4) |
| TaskCreateSuccess | [task_create_success.md](task_create_success.md) | draft | P5 success confirmation screen for Admin create-task wizard |
| TaskDraftSummary | [task_draft_summary.md](task_draft_summary.md) | draft | Read-only item preview for Admin create-task wizard (P4) |
| TaskDraftInfo | [task_draft_info.md](task_draft_info.md) | draft | Read-only P4 customer + vehicle info card for Admin create-task wizard |
| TaskFeedList | [task_feed_list.md](task_feed_list.md) | draft | Grouped task card list (assigned/failed/completed) with allDone footer for P10 TaskFeed |
| TaskItemBuilder | [task_item_builder.md](task_item_builder.md) | draft | Item-line builder for Admin create-task wizard (P2) |
| TaskManifestList | [task_manifest_list.md](task_manifest_list.md) | draft | Per-task accordion list with drop/pickup aggregates for P5 CustodyNotification |
| VehicleCargoSummary | [vehicle_cargo_summary.md](vehicle_cargo_summary.md) | draft | Intro paragraph + cargo card (Sisa di Kendaraan) and vehicleId publisher for P12 ReturnVehicle |
| TimelinePeriodic | [timeline_periodic.md](timeline_periodic.md) | draft | Config-driven event timeline (TIMELINE variant periodic) with period selector, badge chips, gap pills, image gallery |
| TimelineLedger | [timeline_ledger.md](timeline_ledger.md) | draft | Config-generic grouped + expandable audit timeline (TIMELINE variant ledger) with category badge palette, period filter, flat/grouped modes |
| OtqFormattedText | [otq_formatted_text.md](otq_formatted_text.md) | todo | Text with formatter |
| TimePresence | [time_presence.md](time_presence.md) | done | Check-in time, live elapsed counter, and last action in 3-column card |
| VehicleCustodyHeader | [vehicle_custody_header.md](vehicle_custody_header.md) | draft | Vehicle custody card (plate/event/loader/loadtime) and vehicleId publisher for P5 CustodyNotification |
| VehicleFeedHeader | [vehicle_feed_header.md](vehicle_feed_header.md) | draft | Sticky checker identity + 3 snapshot count boxes for H1 Warehouse Vehicle Feed |
| VehicleFeedList | [vehicle_feed_list.md](vehicle_feed_list.md) | draft | Tier-grouped vehicle card list with state chips + action buttons for H1 Warehouse Vehicle Feed |
| WorkspaceHeader | [workspace_header.md](workspace_header.md) | draft | Task identity top-bar (stop/customer/Berjalan chip/address) for P11 DeliveryWorkspace |

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
| Scanner | [scanner.md](scanner.md) | draft | In-page live-camera card: auto-detect QR, writes event via saveSend, navigates to route |
| SignaturePad | [signature_pad.md](signature_pad.md) | draft | Hand-drawn stroke capture via CustomPaint for P11 DeliveryWorkspace |

### Location / GPS
| Widget | File | Status | Description |
|---|---|---|---|
| LocationDetector | [location_detector.md](location_detector.md) | done | GPS location status with inside/outside site detection via LQR reference points |
| QrGps | [qr_gps.md](qr_gps.md) | todo | QR + GPS |
| GpsSend | [gps_send.md](gps_send.md) | todo | Send GPS coordinates |
| AttendanceQrSelfieGpsVerify | [attendance_qr_selfie_gps_verify.md](attendance_qr_selfie_gps_verify.md) | draft | Attendance verification (QR + selfie + GPS) |

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
