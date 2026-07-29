import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../api.dart';
import '../global.dart';
import 'approver_sticky_bar.dart';
import 'driver_home_support.dart';
import 'item_card_detail.dart';
import 'otq_formatted_text.dart';

class OtqTxt extends StatelessWidget {
  const OtqTxt({
    super.key,
    required this.component,
    required this.scrName,
    required this.lPad,
    required this.tPad,
    required this.rPad,
    required this.bPad,
  });
  final dynamic component;
  final String scrName;
  final double lPad;
  final double tPad;
  final double rPad;
  final double bPad;

  @override
  Widget build(BuildContext context) {
    // DriverHome (P4) state-aware label hook.
    //
    // W2 / JSON CONTRACT: this swap ONLY activates when the component carries a
    // `stateSwitch` field (e.g. the op1Screen DriverHome label, row 1010, must
    // be `"stateSwitch":"HARI INI"`). Without that field the check below
    // short-circuits and OtqTxt behaves exactly as before — zero impact on the
    // thousands of other TXT components that lack it. When present, the label
    // shows `component['data']` (pending text, e.g. "SEBELUM BERANGKAT") and
    // swaps to `stateSwitch` once DriverHomeState.confirmed flips true.
    final String switchText = (component['stateSwitch'] ?? '')
        .toString()
        .trim();
    if (switchText.isNotEmpty) {
      // Obx so the label rebuilds when DriverHomeState.confirmed changes.
      // Touch confirmed.value HERE, unconditionally, via getDriverHomeState
      // (which lazily creates + returns a non-null state). _buildContent only
      // reads the observable when driverHomeStates[scrName] is non-null, so on
      // a screen/first-build where the state map has no entry yet the Obx saw
      // ZERO observables and GetX threw its "improper use of a GetX" fatal.
      return Obx(() {
        getDriverHomeState(scrName).confirmed.value;
        return _buildContent(context, switchText);
      });
    }
    return _buildContent(context, '');
  } // end of build

  Widget _buildContent(BuildContext context, String switchText) {
    // Determine display text: if switchText is set and state is confirmed,
    // show switchText; otherwise show component['data'].
    String displayData = (component['data'] ?? '').toString();
    if (switchText.isNotEmpty) {
      final DriverHomeState? state = driverHomeStates[scrName];
      if (state != null && state.confirmed.value) {
        displayData = switchText;
      }
    }

    String searchStr = (component['search'] ?? '').toString().trim();
    if (searchStr.isNotEmpty) {
      List<dynamic> row = ItemCardDetail.currentRow.value;
      if (row.isNotEmpty && !evaluateRbtSearch(searchStr, row)) {
        return const SizedBox.shrink();
      }
    }
    List<double> margin = marginArray(component['margin']);

    // Opt-in presentation variants. A TXT component with no `variant` field
    // takes the original path below, byte-identical — so the thousands of
    // existing TXT components on every other screen are untouched.
    final String variant = (component['variant'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (variant == 'history' || variant == 'section') {
      return Container(
        margin: EdgeInsets.only(top: margin[0], bottom: margin[1]),
        padding: EdgeInsets.fromLTRB(
          lPad + margin[2],
          tPad,
          rPad + margin[3],
          bPad,
        ),
        child: variant == 'history'
            ? _historyRail(context, displayData)
            : _sectionHeader(context, displayData),
      );
    }

    return Container(
      margin: EdgeInsets.only(top: margin[0], bottom: margin[1]),
      padding: EdgeInsets.fromLTRB(
        lPad + margin[2],
        tPad,
        rPad + margin[3],
        bPad,
      ),
      child: SingleChildScrollView(
        child: GestureDetector(
          child: OtqFormattedText(textData: displayData, component: component),
          onTap: () {
            if (component['route'] != null &&
                component['route'] != rootThis.pageName) {
              if (component['route'].length >= 4 &&
                  component['route'].substring(0, 4).toLowerCase() == 'http') {
                openInWebView(context, component['route'], component['title']);
              } // end if route.length
            } // end if route != null
          }, // end of onTap
        ),
      ),
    );
  } // end of _buildContent

  // ---------------------------------------------------------------------------
  // variant: "section" — styled section header (accent bar + small caps).
  // ---------------------------------------------------------------------------
  Widget _sectionHeader(BuildContext context, String data) {
    final Color accent = Theme.of(context).colorScheme.primary;
    final Color body =
        Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Container(
          width: 3,
          height: 15,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 9),
        Flexible(
          child: Text(
            data.trim().toUpperCase(),
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: body.withValues(alpha: 0.75),
            ),
          ),
        ),
      ],
    );
  } // end of _sectionHeader

  // ---------------------------------------------------------------------------
  // variant: "history" — timeline rail. Each non-empty line of `data` becomes
  // one entry; the connector is drawn between entries of the SAME component.
  // Best result: send every record in ONE txt separated by "\n". One record per
  // component also renders fine (dot + text, just no connecting rail).
  // ---------------------------------------------------------------------------
  Widget _historyRail(BuildContext context, String data) {
    final List<String> lines = data
        .split('\n')
        .map((dynamic e) => e.toString().trim())
        .where((String e) => e.isNotEmpty)
        .toList();
    if (lines.isEmpty) return const SizedBox.shrink();

    final Color accent = Theme.of(context).colorScheme.primary;
    final Color body =
        Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (int i = 0; i < lines.length; i++)
          _railRow(lines[i], i == lines.length - 1, accent, body),
      ],
    );
  } // end of _historyRail

  Widget _railRow(String line, bool isLast, Color accent, Color body) {
    final (String stamp, String head, String tail) = parseHistoryLine(line);

    // ponytail: IntrinsicHeight so the connector can Expand to the row height.
    // Fine for the 3-5 rows a home feed shows; switch to a CustomPainter rail
    // if this ever renders a long scrolling list.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            width: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Container(
                  margin: const EdgeInsets.only(top: 5),
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 1.5,
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      color: accent.withValues(alpha: 0.25),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (stamp.isNotEmpty)
                    Text(
                      stamp,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
                    ),
                  if (head.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        head,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: body,
                        ),
                      ),
                    ),
                  if (tail.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        tail,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.3,
                          color: body.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  } // end of _railRow

  /// Splits one server-composed history line into (stamp, head, tail).
  ///
  /// Input looks like:
  ///   "15-Jul 15:42 Sekuriti - absen masuk @ BSD Tech Center #26 - Sampora"
  ///   "06-Jul 11:04 - Pengarahan @ - QA-shared-path - Jalan Horizon Broadway"
  ///
  /// Anything that does not start with a "DD-MMM HH:MM" stamp falls back to
  /// (empty, wholeLine, empty) so a format change degrades to plain text
  /// instead of dropping the record.
  static (String, String, String) parseHistoryLine(String line) {
    final RegExpMatch? m = _stampRe.firstMatch(line.trim());
    if (m == null) return ('', _trimDashes(line), '');
    final String stamp = '${m.group(1)} · ${m.group(2)}';
    final String rest = m.group(3) ?? '';
    final int at = rest.indexOf('@');
    if (at < 0) return (stamp, _trimDashes(rest), '');
    return (
      stamp,
      _trimDashes(rest.substring(0, at)),
      _trimDashes(rest.substring(at + 1)),
    );
  } // end of parseHistoryLine

  static final RegExp _stampRe = RegExp(
    r'^(\d{1,2}-\S{2,9}?)\s+(\d{1,2}[:.]\d{2})\s*(.*)$',
  );

  /// Drops the leading/trailing " - " artifacts left by empty server fields.
  static String _trimDashes(String s) {
    String t = s.trim();
    while (t.startsWith('-')) {
      t = t.substring(1).trim();
    }
    while (t.endsWith('-')) {
      t = t.substring(0, t.length - 1).trim();
    }
    return t;
  } // end of _trimDashes
} // end of class OtqTxt
