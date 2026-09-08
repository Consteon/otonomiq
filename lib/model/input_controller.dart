import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';

import '../global2.dart'; // WidgetUpdateController

class InputController {
  int position;
  TextEditingController controller;
  String initialValue;

  String _finalData; // put string here if final output data

  /// The value this slot submits. Read path is unchanged for all ~100 callers.
  String get finalData => _finalData;

  /// Writing a NEW value marks every `visibleWhen` condition on the mounted
  /// page dirty and schedules ONE repaint of their wrappers.
  ///
  /// This setter IS the form-value bus. There was none before: 95 sites in
  /// lib/ assign `.finalData` directly and only 13 route through
  /// `addToTxfController`, so a hook on that helper would have missed almost
  /// everything (spec §10 assumption 1 — false, verified).
  ///
  /// Unchanged value -> no work at all, so `clearData` restoring a slot to the
  /// value it already held costs nothing.
  set finalData(String value) {
    if (_finalData == value) return;
    _finalData = value;
    _scheduleVisibleWhenRebuild();
  }

  /// GetBuilder group id shared by every `visibleWhen` wrapper on the page.
  ///
  /// ONE global id, not one per screen: an InputController does not know its
  /// `scrName`, and threading one in would touch ~25 construction sites
  /// (global2.dart `txfControllerCheck`, attendance_qr_selfie_gps_verify.dart
  /// x15, image_upload.dart x4, gps_send.dart, ...). Only one page is mounted
  /// at a time, and a spurious rebuild of an off-screen `SizedBox.shrink()`
  /// costs nothing.
  ///
  /// Cannot collide with the 12 existing `GetBuilder<WidgetUpdateController>`
  /// ids: every one of those is `'$scrName-$position'` and contains a `-`.
  static const String kVisibleWhenRebuildId = 'visibleWhen';

  /// Debounce latch: collapses every finalData write inside one frame into a
  /// single `update()`.
  static bool _visibleWhenRebuildPending = false;

  /// Post-frame + debounced, and BOTH halves are load-bearing:
  ///
  ///   * Several widgets write `finalData` during `build` — the seed block in
  ///     build_display_component.dart (`ctrl.finalData = initValue;`),
  ///     otq_txf_2.dart's programmatic-.text mirror, selectable_btn.dart's
  ///     `_initController`. Calling `update()` from inside build triggers
  ///     GetBuilder's setState mid-build, a documented fatal shape here.
  ///   * `clearData` (api.dart) rewrites EVERY slot on every route change and
  ///     is itself called from a post-frame callback; the latch turns that
  ///     storm into one repaint.
  ///
  /// `ensureVisualUpdate()` closes the idle case: a post-frame callback
  /// registered while no frame is scheduled would otherwise wait for some
  /// unrelated frame. It is a no-op when a frame is already scheduled or in
  /// flight.
  ///
  /// The whole body is guarded because this runs in unit tests too:
  /// `WidgetsBinding.instance` throws with no binding, and
  /// `Get.find<WidgetUpdateController>()` throws unless `globalInit()` ran
  /// (`Get.put(WidgetUpdateController())`, global.dart). A setter that can
  /// throw would break ~40 unrelated test files.
  static void _scheduleVisibleWhenRebuild() {
    if (_visibleWhenRebuildPending) return;
    _visibleWhenRebuildPending = true;
    try {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _visibleWhenRebuildPending = false;
        try {
          Get.find<WidgetUpdateController>().update(<String>[
            kVisibleWhenRebuildId,
          ]);
        } catch (_) {
          // No WidgetUpdateController registered (bare flutter_test, or app
          // teardown). Nothing to repaint.
        }
      });
    } catch (_) {
      // No binding at all (a unit test that never called
      // TestWidgetsFlutterBinding.ensureInitialized). Nothing was scheduled, so
      // release the latch.
      _visibleWhenRebuildPending = false;
      return;
    }
    // Separate try: the callback IS registered by this point, so a failure here
    // must NOT release the latch (that would let a later write queue a second,
    // redundant update).
    try {
      WidgetsBinding.instance.ensureVisualUpdate();
    } catch (_) {
      // Frame scheduling unavailable; the callback still runs on the next frame.
    }
  }

  List<List<dynamic>?>? execute1;
  List<List<dynamic>?>? execute2; // not used
  // execute1 are used to execute a particular function in a widget. it will be
  // triggered by RBT or other action button
  // execute1 = [
  //   [<GlobalKey<FtzAutoNumberState>>,'generate_number',<template>],
  // ]

  Map<String, dynamic>? table; // optional. it will content the table that
  // need to be created at the saveSend button.
  bool isEnabled;
  bool initialIsEnabled;
  dynamic stateObject; // Holds state for complex widgets
  dynamic initialStateObject; // Initial state for reset purposes

  InputController(
    this.position,
    this.controller,
    this.initialValue,
    String finalData, {
    this.execute1,
    this.execute2,
    this.table, // Added as an optional named parameter
    this.isEnabled = true,
    this.initialIsEnabled = true,
    this.stateObject,
    this.initialStateObject,
  }) : _finalData = finalData;

  void dispose() {
    controller.dispose();
    // stateObject.dispose();
  }
}
