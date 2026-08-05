import 'dart:convert'; // Added for jsonDecode/jsonEncode

import 'package:cloud_firestore/cloud_firestore.dart'; // Required for DocumentReference
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
// import 'package:share_plus/share_plus.dart';
import 'package:get/get.dart';

import '../api.dart';
import '../bloc_timer/timer_bloc.dart';
import '../bloc_timer/timer_event.dart';
import '../bloc_timer/timer_state.dart';
import '../firestore_repository/table_repository.dart';
import '../global.dart';
import '../global2.dart';
import '../login/bloc_authentication/authentication_bloc.dart';
import '../login/bloc_authentication/authentication_event.dart';
import '../model/connection_data.dart';
import '../model/otq_state.dart';
import '../redux/screen_transaction.dart';
import 'do_chain.dart';
import 'driver_home_support.dart';
import 'item_execution_list.dart';
import 'item_execution_submit.dart';
import 'where_eq_type_tolerant.dart';

// display a row of buttons

class FtzRowOfButton2 extends StatefulWidget {
  const FtzRowOfButton2({
    required Key key,
    required this.component,
    required this.scrName,
    required this.lPad,
    required this.tPad,
    required this.rPad,
    required this.bPad,
    this.dialog,
  }) : super(key: key);
  final dynamic component;
  final String scrName;
  final double lPad;
  final double tPad;
  final double rPad;
  final double bPad;
  final bool? dialog;

  @override
  State<FtzRowOfButton2> createState() => _FtzRowOfButton2State();
}

class _FtzRowOfButton2State extends State<FtzRowOfButton2>
    with AutomaticKeepAliveClientMixin<FtzRowOfButton2> {
  dynamic allOtqData;

  @override
  void initState() {
    super.initState();
    // This ensures their controllers are initialized with the correct isEnabled state.
    if (canInitializePage(widget.scrName)) {
      final children = widget.component['children'] as List<dynamic>? ?? [];
      for (final buttonData in children) {
        final int? position = buttonData['position'] as int?;
        if (position != null) {
          txfControllerCheck(widget.scrName, position);
          final bool isEnabled =
              (buttonData['isEnabled']?.toString().toLowerCase() ?? 'true') !=
              'false';
          txfController[widget.scrName]![position]!.isEnabled = isEnabled;
        }
      }
    }
  }

  Future<void> _updateApprovalChain(
    String actionsStr,
    Map<dynamic, dynamic> screenTx,
    String scrName,
  ) async {
    try {
      List<String> tabs = [];
      if (screenTx['approval_tabs'] is List) {
        tabs = (screenTx['approval_tabs'] as List)
            .map((e) => e.toString())
            .toList();
      }
      int myApprovalLevel =
          int.tryParse((screenTx['approval_level'] ?? '').toString()) ?? -1;
      int statusFieldIndex =
          int.tryParse((screenTx['approval_status_field'] ?? '').toString()) ??
          2;
      String tableRaw = (screenTx['approval_table'] ?? '').toString();
      String vid = (screenTx['approval_vidtable'] ?? '').toString();
      String requestDocT = (screenTx['request_doc_t'] ?? '').toString();

      String decodedTable = autheniumDecode(tableRaw) ?? tableRaw;
      String tableCode = normalizeTableName(decodedTable);
      List<dynamic> allData = List.from(tableContent[tableCode] ?? []);

      List<dynamic>? row;
      for (var r in allData) {
        if (r.isNotEmpty && r[0].toString() == requestDocT) {
          row = r;
          break;
        }
      }
      if (row == null) {
        debugPrint(
          '[FtzRowOfButton2] approval row not found for docT=$requestDocT',
        );
        return;
      }

      int chainColIdx = -1;
      String chainStr = '';
      for (int i = 0; i < row.length; i++) {
        String s = row[i].toString().trim();
        if (s.startsWith('[[') && s.contains(',')) {
          chainColIdx = i;
          chainStr = s;
          break;
        }
      }
      if (chainColIdx < 0) {
        debugPrint('[FtzRowOfButton2] no chain field found in row');
        return;
      }

      String inner = chainStr.substring(1, chainStr.length - 1);
      List<List<String>> steps = [];
      for (var stepStr in inner.split(RegExp(r'\]\s*,\s*\['))) {
        stepStr = stepStr.replaceAll('[', '').replaceAll(']', '').trim();
        steps.add(stepStr.split(',').map((e) => e.trim()).toList());
      }

      String defaultStatus = tabs.isNotEmpty
          ? tabs[0].toUpperCase()
          : 'PENDING';
      int targetIdx = steps.indexWhere(
        (s) => s.length > 1 && s[1].toUpperCase() == defaultStatus,
      );
      if (targetIdx < 0) {
        debugPrint('[FtzRowOfButton2] no $defaultStatus step found in chain');
        return;
      }

      List<String> newStep = List<String>.from(steps[targetIdx]);
      for (var part in actionsStr.split('⭘')) {
        List<String> kv = part.split('◼');
        if (kv.length < 2) continue;
        String key = kv[0].trim();
        String value = kv.sublist(1).join('◼').trim();
        if (key.startsWith('<') && key.endsWith('>')) {
          try {
            int pos = int.parse(key.substring(1, key.length - 1)) - 1;
            while (newStep.length <= pos) {
              newStep.add('');
            }
            newStep[pos] = value;
          } catch (_) {}
        }
      }
      steps[targetIdx] = newStep;

      String newChainStr =
          '[${steps.map((s) => '[${s.join(', ')}]').join(', ')}]';

      String actionStatus = newStep.length > 1
          ? newStep[1].trim().toUpperCase()
          : '';
      String continueStatus = tabs.length > 1 ? tabs[1].toUpperCase() : '';
      bool isLastLevel = myApprovalLevel > 0 && myApprovalLevel == steps.length;
      bool updateOverallStatus = isLastLevel || actionStatus != continueStatus;

      debugPrint(
        '[FtzRowOfButton2] actionStatus=$actionStatus | myLevel=$myApprovalLevel | totalSteps=${steps.length} | isLastLevel=$isLastLevel | updateOverall=$updateOverallStatus',
      );

      String noRequest = row.length > 1 ? row[1].toString() : '';
      String input =
          '$tableRaw⭘tablevid◼$vid⭘search◼1${separator[3]}$noRequest⭘<$chainColIdx>◼$newChainStr';
      if (updateOverallStatus) {
        input += '⭘<$statusFieldIndex>◼$actionStatus';
      }

      int nowMs = DateTime.now().millisecondsSinceEpoch;
      List<String> contentParts = [
        '${separator[7]}$nowMs',
        scrName,
        row.length > 1 ? row[1].toString() : '',
        row.length > 2 ? row[2].toString() : '',
        '$nowMs',
      ];
      for (int i = 3; i < row.length; i++) {
        contentParts.add(row[i].toString());
      }
      String eventContent = '0${contentParts.join(separator[1])}';
      String eventRowString = jsonEncode([nowMs, scrName, eventContent]);

      debugPrint('[FtzRowOfButton2] approval input: $input');
      List<String> result = await updateTableRow(input, eventRowString);
      debugPrint('[FtzRowOfButton2] approval chain update result: $result');

      // Create approval event for spreadsheet recording
      String eventFlag = (screenTx['approval_flag'] ?? '').toString();
      if (eventFlag.isNotEmpty &&
          result.isNotEmpty &&
          result[0].startsWith('OK')) {
        int appVid = defaultVid();
        if (vid.isNotEmpty) {
          appVid = int.tryParse(vid) ?? defaultVid();
        }
        createApprovalEvent(
          row: row,
          scrName: scrName,
          eventFlag: eventFlag,
          actionStatus: actionStatus,
          updateOverallStatus: updateOverallStatus,
          steps: steps,
          targetIdx: targetIdx,
          nowMs: nowMs,
          appVid: appVid,
        );
      }
    } catch (e) {
      debugPrint('[FtzRowOfButton2] approval chain update error: $e');
    }
  }

  List<Widget> buildButtonList(
    List<dynamic> children,
    String scrName, {
    bool? dialog,
  }) {
    List<Widget> bannerComponent = [];
    var state = transactionStore.state.screenTx;

    void saveData(
      int timeStamp,
      String scrName,
      dynamic component,
      String locString, {
      bool send = true,
    }) {
      TimerBloc timerBloc = transactionStore.state.screenTx['#TIMER_BLOC'];
      String route = component['route'] ?? scrName;
      rootThis.setState(() {
        rootThis.wait = true;
      });
      timerBloc.add(
        const Start(duration: 5),
      ); //  get timerBloc from transactionStore
      transactionStore.dispatch(
        UpdateScreenTxAction(
          ScreenTransaction({
            '#NEXTROUTE': route,
            '#TIMER_CONTEXT': context,
            '#TIMER_DURATION': component['delay'] ?? 5,
          }),
        ),
      ); // set state #NEXTROUTE route that will be displayed after waitScreen
      saveSend(
        timeStamp,
        scrName,
        component,
        locString,
        defaultVid(),
        send: send,
      );
    } // end of saveData

    Future doSaveProcedure(int i, {bool send = true}) async {
      await ConnectionData().getConnection(false, false);
      try {
        try {
          // update process
          // 1. Resolve Table VID
          String com = children[i]['com'] ?? '';
          int tableVid = getTableVid(com);

          // 2. Resolve Table Name & Update Instruction
          // Input format: "$vtl/request//request_master⭘<12>◼approved"
          var updateTable = children[i]['updateTable'] ?? {};
          if (updateTable.isNotEmpty) {
            String rawTable = updateTable['table'] ?? '';
            String cleanTableNameStr = autheniumDecode(rawTable) ?? '';

            // Separators based on user prompt
            final String updateSep = separator[1]; // black diamond
            final String valueSep = ':';
            final String updateInstruction =
                autheniumDecode(updateTable['update']) ?? '';

            // List<String> splitTable = decodedTable.split(updateSep);
            // String cleanTableNameStr = splitTable.isNotEmpty
            //     ? splitTable[0]
            //     : '';

            String tableName = normalizeTableName(cleanTableNameStr);
            // int separatorIndex = tableName.indexOf(separator[2]);
            // if (separatorIndex != -1) {
            //   tableName =
            //       tableName.substring(0, separatorIndex); // get only table name
            // }

            // 3. Parse Search Key
            // Input format: "1:16" (Field '1', Controller Index 16)
            String tableKey = updateTable['tableKey'] ?? '';
            List<String> keyParts = tableKey.split(':');

            if (keyParts.length == 2 && updateInstruction.isNotEmpty) {
              String searchField = keyParts[0];
              int? controllerPos = int.tryParse(keyParts[1]);

              if (controllerPos != null) {
                txfControllerCheck(widget.scrName, controllerPos);
                String searchValue =
                    txfController[widget.scrName]?[controllerPos]?.finalData ??
                    '';

                if (searchValue.isNotEmpty) {
                  DocumentReference parentRef = FirebaseFirestore.instance
                      .collection('MobileTable/$tableVid/tables')
                      .doc(tableName);
                  DocumentSnapshot parentSnapshot = await parentRef.get();
                  if (parentSnapshot.exists) {
                    Map<String, dynamic> parentData =
                        parentSnapshot.data() as Map<String, dynamic>;
                    int d = 1;
                    if (parentData['tt'] == 'A') {
                      // todo: handle table type A
                    } else {
                      // table type D, dynamic
                      // 4. Query Firestore
                      CollectionReference contentRef = FirebaseFirestore
                          .instance
                          .collection(
                            'MobileTable/$tableVid/tables/$tableName/content',
                          );

                      QuerySnapshot querySnapshot = await whereEqTypeTolerant(
                        contentRef,
                        searchField,
                        searchValue,
                      ).limit(1).get();

                      if (querySnapshot.docs.isNotEmpty) {
                        DocumentSnapshot doc = querySnapshot.docs.first;
                        Map<String, dynamic> data =
                            doc.data() as Map<String, dynamic>;

                        // 5. Parse Content and Update
                        String jsonContent = data['c'] ?? '[]';
                        List<dynamic> contentList = jsonDecode(jsonContent);

                        // Parse instruction: <12>◼approved
                        List<String> updateInstructionParts = updateInstruction
                            .split(updateSep);
                        Map<String, dynamic> updateData = {};
                        for (String inst in updateInstructionParts) {
                          if (inst.trim().isEmpty) continue;
                          List<String> instructionParts = inst.split(valueSep);
                          if (instructionParts.length >= 2) {
                            Map<String, String> positionMap = parsePosition(
                              instructionParts[1],
                            );
                            int indexStart =
                                widget.component['indexStart'] ?? 1;
                            String newValue = instructionParts[1];
                            if (positionMap['type'] == 'string') {
                              newValue = positionMap['val'] ?? '';
                            } else if (positionMap['type'] == 'position') {
                              int? positionRef = int.tryParse(
                                positionMap['val'] ?? '',
                              );
                              if (positionRef != null) {
                                newValue =
                                    txfController[widget.scrName]?[positionRef]
                                        ?.finalData ??
                                    '';
                              } else {
                                newValue = '';
                              }
                            } else if (positionMap['type'] == 'table') {
                              int? positionRef = int.tryParse(
                                positionMap['val'] ?? '',
                              );
                              if (positionRef != null) {
                                newValue =
                                    contentList[positionRef - indexStart];
                              } // end if positionRef != null
                            } else if (positionMap['type'] == 'left') {
                              newValue =
                                  '${instructionParts[1]} not implemented';
                              debugPrint(newValue);
                              // todo: implement left side of event as newValue
                            } else {
                              newValue = instructionParts[1];
                            } // end of determining newValue

                            positionMap = parsePosition(instructionParts[0]);
                            String indexStr = '';
                            if (positionMap['type'] == 'table') {
                              indexStr = positionMap['val'] ?? '';
                              int targetIndexRaw = int.tryParse(indexStr) ?? 0;
                              int arrayIndex = targetIndexRaw - indexStart;
                              if (arrayIndex >= 0 &&
                                  arrayIndex < contentList.length) {
                                String fieldName = targetIndexRaw.toString();
                                contentList[arrayIndex] =
                                    newValue; // update table content
                                if (data.containsKey(fieldName)) {
                                  updateData[fieldName] =
                                      newValue; // update extra field if exists
                                }
                              } else {
                                debugPrint(
                                  'Update failed: Index $arrayIndex out of bounds (Size: ${contentList.length})',
                                );
                              } // end if arrayIndex
                            } else if (positionMap['type'] == 'position') {
                              indexStr = positionMap['val'] ?? '';
                              int positionIndex = int.tryParse(indexStr) ?? 0;
                              if (positionIndex > 0) {
                                txfControllerCheck(
                                  widget.scrName,
                                  positionIndex,
                                );
                                txfController[widget.scrName]![positionIndex]!
                                        .controller
                                        .text =
                                    newValue;
                                txfController[widget.scrName]![positionIndex]!
                                        .finalData =
                                    newValue;
                                debugPrint(
                                  'Update successful: Position $positionIndex to "$newValue".',
                                );
                              } else {
                                debugPrint(
                                  'Update failed: Position $positionIndex out of bounds',
                                );
                              } // end if arrayIndex
                            } // end if positionMap['type'] == 'table'
                          } // end if instructionParts.length >= 2
                          // 6. Write back to Firestore
                        } // end for inst
                        updateData['c'] = jsonEncode(contentList);
                        await Future.wait([
                          doc.reference.update(
                            updateData,
                          ), // update content array
                          parentRef.update({
                            'u': DateTime.now().millisecondsSinceEpoch,
                            // update parent 'u' timestamp
                          }),
                        ]);
                      } else {
                        debugPrint(
                          'Update failed: Document not found for $searchField = $searchValue',
                        );
                      } // end if querySnapshot.docs.isNotEmpty
                    } // end else tt != A
                  } // end if parentSnapshot.exists
                } // end if searchValue.isNotEmpty
              } // end if controllerPos != null
            } // end if keyParts.length == 2
          } // end if updateTable.isNotEmpty
        } catch (eUpdate) {
          // do nothing right now
        } // end of try update process
        late int timeStamp;
        late String locString;
        int gpsPosition = 0;
        if (children[i]['gpsPosition'] is String) {
          gpsPosition = int.parse(children[i]['gpsPosition']);
        } else {
          gpsPosition = children[i]['gpsPosition'] ?? 0; // 0 = no gps
        }
        if (gpsPosition > 0 ||
            children[i]['action'].toString().trim().toLowerCase() ==
                'resetvid') {
          allOtqData = await OtqState().setAllDataAsync();
          timeStamp = allOtqData.nowTime.millisecondsSinceEpoch;
          locString = getLocationString('', '', '', allOtqData);
        } else {
          timeStamp = await getRealTime();
          locString = '${separator[1]}$timeStamp';
          locString +=
              '${separator[1] * 3}$invalidLocation${separator[1]}$invalidLocation${separator[1] * 10}';
        }
        if (children[i]['type'] == null) {
          children[i]['type'] = 'rbt';
        }
        // ── Actual-write hook ──────────────────────────────────────────
        // Persist ITEM_EXECUTION_LIST stepper actuals to task.it[]
        // atomically with tst=completed BEFORE the offline updateEventRow
        // submit, so CF OnTaskCompleted reads actuals (ad/ap) not plan.
        // No-op if no LIST registered for this screen (guard is airtight:
        // only ITEM_EXECUTION_LIST initState populates submitComponentByScr).
        dynamic componentForSave = children[i];
        if (ItemExecutionList.submitComponentByScr.containsKey(scrName)) {
          final bool ok = await ItemExecutionSubmit.runActualWrite(scrName);
          if (!ok) {
            devPrint('[doSaveProcedure] actual-write failed for $scrName');
            setDataOK('2'); // release the action lock so the driver can retry
            // (mirrors the doSaveProcedure catch; spec §6 still
            // honored — tst is NOT flipped, saveSend not called)
            return; // bail -- do NOT saveSend, do NOT flip tst
          }
          // Strip tst/tce from this submit's updateEventRow so saveSend
          // doesn't double-write them (native write already owns them).
          // Operate on a COPY -- do not mutate the shared children[i].
          componentForSave = Map<String, dynamic>.from(children[i] as Map);
          final String rawUER = (componentForSave['updateEventRow'] ?? '')
              .toString();
          if (rawUER.isNotEmpty) {
            final String stripped = stripTstFromUpdateEventRow(rawUER);
            if (updateEventRowHasBody(stripped)) {
              componentForSave['updateEventRow'] = stripped;
            } else {
              // Only header survived the strip (live P11 form: tst+tce are the
              // only body clauses). Remove updateEventRow entirely so saveSend
              // skips the segment and historySync does no redundant query.
              componentForSave.remove('updateEventRow');
            }
          }
        }
        // ── New-customer id-gen hook (B1-A) ───────────────────────────
        // Generate a unique customer id (lv) and dispatch it into screenTx
        // BEFORE saveData so the addToEvent `lv◼{newCustomerId}` resolves
        // in saveSend (api.dart:4278 resolveDriverCurlyTokens). Also sets
        // screenTx['kl'] so _republishClient + P4 submit carry the new id.
        // Gate: only the N2 "Daftarkan" button carries this marker token;
        // no custody/item-execution/other RBT addToEvent contains it.
        if (hasNewCustomerIdMarker(componentForSave)) {
          generateAndDispatchNewCustomerId();
        }
        saveData(timeStamp, scrName, componentForSave, locString, send: send);
        if (routeExist(children[i]['route'])) {
          if (children[i]['route'] == scrName) {
            String pageToGo = children[i]['route'] ?? scrName;
            gotoRoute(pageToGo);
          } else {
            String pageToGo = children[i]['route'] ?? scrName;
            routeStack.push(pageToGo);
            gotoRoute(pageToGo);
          }
        } // end if routeExist
      } catch (e) {
        setDataOK('2');
        errorReport(e);
      } // end of try
    } // end of doSaveProcedure

    for (var i = 0; i < children.length; i++) {
      final buttonData = children[i];
      final int? position = buttonData['position'] as int?;

      // This function builds the actual button widget. It's separated so it can be called
      // either directly (for static buttons) or inside a GetBuilder (for dynamic buttons).
      Widget buildActualButton(bool isEnabled) {
        // per-button (was a shared buildButtonList-scope var → last button's
        // value leaked to every button's onTap, firing doChain on chainless
        // buttons → null-chain crash / real chains silently not firing).
        final bool hasChain =
            buttonData['chain'] != null &&
            buttonData['chain'].toString().trim().isNotEmpty;
        try {
          final buttonColorStr = buttonData['buttonColor'] as String?;
          final textColorStr = buttonData['textColor'] as String?;

          final buttonColor =
              buttonColorStr != null && buttonColorStr.isNotEmpty
              ? stringToColor(buttonColorStr)
              : null;
          final textColor = textColorStr != null && textColorStr.isNotEmpty
              ? stringToColor(textColorStr)
              : null;

          final width = buttonData['width'];
          final height = buttonData['height'];

          double minWidth = (width is num) ? width.toDouble() : 0;
          double minHeight = (height is num) ? height.toDouble() : 48;

          final double screenWidth = MediaQuery.of(context).size.width;
          final ButtonStyle style = ElevatedButton.styleFrom(
            backgroundColor: buttonColor,
            foregroundColor: textColor,
            disabledBackgroundColor: Colors.grey.shade300,
            disabledForegroundColor: Colors.grey.shade500,
            minimumSize: Size(minWidth, minHeight),
            maximumSize: Size(screenWidth, double.infinity),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8.0),
            ),
          );

          return Theme(
            data: transactionStore.state.screenTx['#THEME'],
            child: ElevatedButton(
              style: style,
              onPressed: isEnabled
                  ? () async {
                      final String runCommand =
                          (autheniumDecode(buttonData['run'] as String?) ?? '')
                              .trim()
                              .toLowerCase();
                      if (runCommand.isNotEmpty) {
                        final commands = runCommand.split('◆');
                        final List<String> widgetsToUpdate = [];

                        for (final cmd in commands) {
                          final parts = cmd.split(':');
                          if (parts.length == 2) {
                            final int? targetPosition = int.tryParse(
                              parts[0].trim(),
                            );
                            final String action = parts[1].trim().toLowerCase();

                            if (targetPosition != null) {
                              txfControllerCheck(scrName, targetPosition);
                              final controller =
                                  txfController[scrName]?[targetPosition];
                              if (controller == null) continue;
                              if (action == 'get_radius') {
                                allOtqData ??= await OtqState()
                                    .setAllDataAsync();
                                String content = '${allOtqData.accuracy} m';
                                controller.finalData = action;
                                controller.controller.text = content;
                                controller.finalData = content;
                                widgetsToUpdate.add('$scrName-$targetPosition');
                              } else if (action == 'get_address') {
                                allOtqData ??= await OtqState()
                                    .setAllDataAsync();
                                String content = getAddressFromOtqState(
                                  allOtqData,
                                );
                                controller.finalData = action;
                                controller.controller.text = content;
                                controller.finalData = content;
                                widgetsToUpdate.add('$scrName-$targetPosition');
                              } else if (action == 'get_gps') {
                                allOtqData ??= await OtqState()
                                    .setAllDataAsync();
                                String content =
                                    '${allOtqData.latitude},${allOtqData.longitude}';
                                controller.finalData = action;
                                controller.controller.text = content;
                                controller.finalData = content;
                                widgetsToUpdate.add('$scrName-$targetPosition');
                              } else if (action == 'enable') {
                                controller.isEnabled = true;
                                widgetsToUpdate.add('$scrName-$targetPosition');
                                debugPrint(
                                  "&&&&&&&&&&&& set $scrName-$targetPosition to TRUE",
                                );
                              } else if (action == 'disable') {
                                controller.isEnabled = false;
                                widgetsToUpdate.add('$scrName-$targetPosition');
                                debugPrint(
                                  "&&&&&&&&&&&& set $scrName-$targetPosition to FALSE",
                                );
                              } else if (action == 'toggle') {
                                controller.isEnabled = !controller.isEnabled;
                                widgetsToUpdate.add('$scrName-$targetPosition');
                              } else if (action == 'generate_number') {
                                // Find the specific 'generate_number' action in execute1
                                final execute1Actions =
                                    controller.execute1
                                        ?.where(
                                          (item) =>
                                              item != null &&
                                              item.length >= 2 &&
                                              item[1]
                                                      .toString()
                                                      .toLowerCase() ==
                                                  'generate_number',
                                        )
                                        .toList() ??
                                    [];

                                for (final actionItem in execute1Actions) {
                                  if (actionItem!.length >= 3) {
                                    final String template =
                                        actionItem[2] as String;
                                    final generatedString =
                                        await generateAutoNumber(
                                          template,
                                          scrName,
                                        );
                                    addToTxfController(
                                      targetPosition,
                                      scrName,
                                      generatedString,
                                    );
                                    widgetsToUpdate.add(
                                      '$scrName-$targetPosition',
                                    );
                                  }
                                }
                              }
                            }
                          }
                        }
                        // Update all affected widgets at once
                        if (widgetsToUpdate.isNotEmpty) {
                          Get.find<WidgetUpdateController>().update(
                            widgetsToUpdate,
                          );
                        }
                      } // end of runCommand

                      // await executeWidgets(scrName,
                      //     (buttonData['exe'] ?? emptyString).toLowerCase());

                      // -- routeParams: dispatch resolved params into screenTx
                      // before any action (route / savesend / resetvid) so the
                      // destination page can resolve {key} tokens.
                      writeRouteParams(
                        buttonData['routeParams']?.toString(),
                        scrName,
                      );

                      switch ((buttonData['action'] ?? emptyString)
                          .toString()
                          .trim()
                          .toLowerCase()) {
                        case 'clear':
                          clearData(scrName);
                          // historyClear(); // clear history
                          // Get.defaultDialog(
                          //   title: "History",
                          //   content: const Text("History cleared."),
                          // );
                          break;

                        case 'clearhistory':
                          historyClear(); // clear history
                          Get.defaultDialog(
                            title: "History",
                            content: const Text("History cleared."),
                          );
                          break;

                        case 'sendhistory':
                          historySync(
                            'rbt sendhistory',
                            true,
                          ); // force send history
                          Get.defaultDialog(
                            title: "History",
                            content: const Text("History synced."),
                          );
                          break;

                        case 'archivehistory':
                          archiveHistory(); // archive history to firestore proxy h2
                          Get.defaultDialog(
                            title: "History",
                            content: const Text("History archived."),
                          );
                          break;

                        case 'share':
                          break;

                        case 'savesend':
                          {
                            if (await dataOk(context)) {
                              final List<String> btnTextArray =
                                  (autheniumDecode(
                                            buttonData['text']?.toString(),
                                          ) ??
                                          '')
                                      .split(separator[1]);
                              final bool fakeGpsAllowed =
                                  (buttonData['fakeGpsAllowed']
                                          ?.toString()
                                          .toLowerCase() ??
                                      'true') !=
                                  'false';
                              if (!fakeGpsAllowed) {
                                allOtqData ??= await OtqState()
                                    .setAllDataAsync();
                                if (allOtqData.mock) {
                                  if (mounted) {
                                    await showDialog(
                                      context: context,
                                      builder: (BuildContext ctx) {
                                        return AlertDialog(
                                          title: Text(
                                            btnTextArray.length > 1
                                                ? btnTextArray[1]
                                                : 'Lokasi tidak valid',
                                          ),
                                          content: Text(
                                            btnTextArray.length > 2
                                                ? btnTextArray[2]
                                                : 'Nonaktifkan Fake GPS',
                                          ),
                                          actions: [
                                            TextButton(
                                              child: const Text('OK'),
                                              onPressed: () =>
                                                  Navigator.of(ctx).pop(),
                                            ),
                                          ],
                                        );
                                      },
                                    );
                                  }
                                  return;
                                }
                              }
                              final bool outPositionAllowed =
                                  (buttonData['outPositionAllowed']
                                          ?.toString()
                                          .toUpperCase() ??
                                      'TRUE') !=
                                  'FALSE';
                              bool outBlocked = false;
                              if (!outPositionAllowed) {
                                allOtqData ??= await OtqState()
                                    .setAllDataAsync();
                                final dynamic lqrList = transactionStore
                                    .state
                                    .screenTx['#LQR_LIST'];
                                final bool hasLqrList =
                                    lqrList != null &&
                                    lqrList is Map &&
                                    lqrList.isNotEmpty;
                                if (hasLqrList) {
                                  try {
                                    final double gpsAccuracy =
                                        allOtqData.accuracy;
                                    bool insideAny = false;
                                    double minDistance = double.infinity;
                                    double matchZone2 = 0;
                                    for (final entry in lqrList.values) {
                                      final List data = entry as List;
                                      final double targetLat = (data[1] as num)
                                          .toDouble();
                                      final double targetLng = (data[2] as num)
                                          .toDouble();
                                      final double tolerance = (data[3] as num)
                                          .toDouble();
                                      final double zone2 =
                                          tolerance + gpsAccuracy * 2;
                                      final double distance =
                                          Geolocator.distanceBetween(
                                            targetLat,
                                            targetLng,
                                            allOtqData.latitude,
                                            allOtqData.longitude,
                                          );
                                      if (distance < minDistance) {
                                        minDistance = distance;
                                        matchZone2 = zone2;
                                      }
                                      if (distance <= zone2) {
                                        insideAny = true;
                                        break;
                                      }
                                    }
                                    debugPrint(
                                      '[savesend/ftz_row_of_button_2] insideAny=$insideAny, minDistance=${minDistance.toStringAsFixed(1)}m, zone2=${matchZone2.toStringAsFixed(1)}m',
                                    );
                                    if (!insideAny) {
                                      outBlocked = true;
                                      if (mounted) {
                                        await Get.dialog(
                                          AlertDialog(
                                            title: Text(
                                              btnTextArray.length > 3
                                                  ? btnTextArray[3]
                                                  : 'Diluar Area Absensi',
                                            ),
                                            content: Text(
                                              btnTextArray.length > 4
                                                  ? btnTextArray[4]
                                                  : 'Silahkan menuju lokasi yang ditentukan',
                                            ),
                                            actions: [
                                              TextButton(
                                                child: const Text('OK'),
                                                onPressed: () => Get.back(),
                                              ),
                                            ],
                                          ),
                                        );
                                      }
                                    }
                                  } catch (eLoc) {
                                    debugPrint(
                                      '[savesend/ftz_row_of_button_2] parse error: $eLoc — bypass pengecekan',
                                    );
                                  }
                                } else {
                                  if (!internetConnected()) {
                                    debugPrint(
                                      '[savesend/ftz_row_of_button_2] offline & #LQR_LIST kosong/null — block absensi',
                                    );
                                    outBlocked = true;
                                    if (mounted) {
                                      await Get.dialog(
                                        AlertDialog(
                                          title: Text(
                                            btnTextArray.length > 3
                                                ? btnTextArray[3]
                                                : 'Diluar Area Absensi',
                                          ),
                                          content: Text(
                                            btnTextArray.length > 4
                                                ? btnTextArray[4]
                                                : 'Silahkan menuju lokasi yang ditentukan',
                                          ),
                                          actions: [
                                            TextButton(
                                              child: const Text('OK'),
                                              onPressed: () => Get.back(),
                                            ),
                                          ],
                                        ),
                                      );
                                    }
                                  } else {
                                    debugPrint(
                                      '[savesend/ftz_row_of_button_2] online & #LQR_LIST kosong/null — bypass pengecekan',
                                    );
                                  }
                                }
                              }
                              if (outBlocked) return;
                              actionLock('savesend case ftz_row_of_button');
                              await doSaveProcedure(i);
                            } // end if dataOk
                          } // end of case saveSend
                          break;

                        case 'update':
                          {
                            if (await dataOk(context)) {
                              actionLock('update case ftz_row_of_button');
                              try {
                                // 1. Resolve Table VID
                                String com = buttonData['com'] ?? '';
                                int tableVid = getTableVid(com);

                                // 2. Resolve Table Name & Update Instruction
                                // Input format: "$vtl/request//request_master⭘<12>◼approved"
                                String rawTable = buttonData['table'] ?? '';
                                String decodedTable =
                                    autheniumDecode(rawTable) ?? '';

                                // Separators based on user prompt
                                const String updateSep = '⭘'; // U+2B58
                                const String valueSep = '◼'; // U+25FC

                                List<String> splitTable = decodedTable.split(
                                  updateSep,
                                );
                                String cleanTableNameStr = splitTable.isNotEmpty
                                    ? splitTable[0]
                                    : '';
                                String updateInstruction = splitTable.length > 1
                                    ? splitTable[1]
                                    : '';

                                String tableName = normalizeTableName(
                                  cleanTableNameStr,
                                );
                                int separatorIndex = tableName.indexOf(
                                  separator[2],
                                );
                                if (separatorIndex != -1) {
                                  tableName = tableName.substring(
                                    0,
                                    separatorIndex,
                                  ); // get only table name
                                }

                                // 3. Parse Search Key
                                // Input format: "1:16" (Field '1', Controller Index 16)
                                String tableKey = buttonData['tableKey'] ?? '';
                                List<String> keyParts = tableKey.split(':');

                                if (keyParts.length == 2 &&
                                    updateInstruction.isNotEmpty) {
                                  String searchField = keyParts[0];
                                  int? controllerPos = int.tryParse(
                                    keyParts[1],
                                  );

                                  if (controllerPos != null) {
                                    txfControllerCheck(
                                      widget.scrName,
                                      controllerPos,
                                    );
                                    String searchValue =
                                        txfController[widget
                                                .scrName]?[controllerPos]
                                            ?.finalData ??
                                        '';

                                    if (searchValue.isNotEmpty) {
                                      DocumentReference parentRef =
                                          FirebaseFirestore.instance
                                              .collection(
                                                'MobileTable/$tableVid/tables',
                                              )
                                              .doc(tableName);
                                      DocumentSnapshot parentSnapshot =
                                          await parentRef.get();
                                      if (parentSnapshot.exists) {
                                        Map<String, dynamic> parentData =
                                            parentSnapshot.data()
                                                as Map<String, dynamic>;
                                        int d = 1;
                                        if (parentData['tt'] == 'A') {
                                          // todo: handle table type A
                                        } else {
                                          // table type D, dynamic
                                          // 4. Query Firestore
                                          CollectionReference
                                          contentRef = FirebaseFirestore
                                              .instance
                                              .collection(
                                                'MobileTable/$tableVid/tables/$tableName/content',
                                              );

                                          QuerySnapshot querySnapshot =
                                              await whereEqTypeTolerant(
                                                contentRef,
                                                searchField,
                                                searchValue,
                                              ).limit(1).get();

                                          if (querySnapshot.docs.isNotEmpty) {
                                            DocumentSnapshot doc =
                                                querySnapshot.docs.first;
                                            Map<String, dynamic> data =
                                                doc.data()
                                                    as Map<String, dynamic>;

                                            // 5. Parse Content and Update
                                            String jsonContent =
                                                data['c'] ?? '[]';
                                            List<dynamic> contentList =
                                                jsonDecode(jsonContent);

                                            // Parse instruction: <12>◼approved
                                            List<String> instructionParts =
                                                updateInstruction.split(
                                                  valueSep,
                                                );
                                            if (instructionParts.length >= 2) {
                                              String indexStr =
                                                  instructionParts[0]
                                                      .replaceAll('<', '')
                                                      .replaceAll('>', '');
                                              int targetIndexRaw =
                                                  int.tryParse(indexStr) ?? 0;
                                              String newValue =
                                                  instructionParts[1];

                                              int indexStart =
                                                  widget
                                                      .component['indexStart'] ??
                                                  1;
                                              int arrayIndex =
                                                  targetIndexRaw - indexStart;

                                              if (arrayIndex >= 0 &&
                                                  arrayIndex <
                                                      contentList.length) {
                                                // Capture index before update to check for field existence
                                                String fieldName =
                                                    targetIndexRaw.toString();

                                                // Update the array content
                                                contentList[arrayIndex] =
                                                    newValue;

                                                // Prepare the update payload
                                                Map<String, dynamic>
                                                updateData = {
                                                  'c': jsonEncode(contentList),
                                                };

                                                // Check if a field with the same name as the OLD content exists
                                                // The user requested to check for the field matching the *content* at the array index.
                                                // Example: if content at index is "12", check for field "12".
                                                if (data.containsKey(
                                                  fieldName,
                                                )) {
                                                  updateData[fieldName] =
                                                      newValue;
                                                }

                                                // 6. Write back to Firestore
                                                await Future.wait([
                                                  doc.reference.update(
                                                    updateData,
                                                  ), // update content array
                                                  parentRef.update({
                                                    'u': DateTime.now()
                                                        .millisecondsSinceEpoch, // update parent 'u' timestamp
                                                  }),
                                                ]);
                                                debugPrint(
                                                  'Update successful: Index $arrayIndex to "$newValue". Extra field "$fieldName" updated: ${data.containsKey(fieldName)}',
                                                );
                                              } else {
                                                debugPrint(
                                                  'Update failed: Index $arrayIndex out of bounds (Size: ${contentList.length})',
                                                );
                                              }
                                            }
                                          } else {
                                            debugPrint(
                                              'Update failed: Document not found for $searchField = $searchValue',
                                            );
                                          } // end if querySnapshot.docs.isNotEmpty
                                        } // end else tt != A
                                      } // end if parentSnapshot.exists
                                    } // end if searchValue.isNotEmpty
                                  } // end if controllerPos != null
                                }
                              } catch (e) {
                                errorReport(e);
                              }
                              actionUnLock('update case ftz_row_of_button');
                            }
                          }
                          break;

                        case 'resetvid':
                          {
                            int resetStatus = -99;
                            if (await dataOk(context)) {
                              if (buttonData['reference'] != null &&
                                  buttonData['reference'] > 0) {
                                String vid = emptyString;
                                String invitation = emptyString;
                                try {
                                  vid =
                                      txfController[widget
                                              .scrName]![buttonData['reference']]!
                                          .finalData;
                                } catch (e) {
                                  vid = emptyString;
                                }
                                if (vid == emptyString) {
                                  resetStatus = -1;
                                } else {
                                  invitation = '';
                                  try {
                                    invitation =
                                        txfController[widget
                                                .scrName]![buttonData['invitationReference']]!
                                            .finalData;
                                  } catch (e) {
                                    invitation = '';
                                  }
                                  String tc = '';
                                  try {
                                    tc =
                                        stringCleanUp(
                                          txfController[widget
                                                  .scrName]![buttonData['tableContentReference']]!
                                              .finalData,
                                        ) ??
                                        '';
                                  } catch (e) {
                                    tc = '';
                                  }
                                  resetStatus = await resetVid([
                                    [vid, invitation, tc],
                                  ]);
                                  if (resetStatus > 0) {
                                    actionLock(
                                      'resetvid case ftz_row_of_button',
                                    );
                                    await doSaveProcedure(i);
                                  }
                                }
                              } else {
                                resetStatus = -3;
                              }
                            }
                          }
                          break;

                        case 'reset':
                          {
                            if (await dataOk(context)) {
                              actionLock('reset case ftz_row_of_button');
                              resetVidUid(state['#FIREBASE_USER'].uid);
                            }
                          }
                          break;

                        case 'signout':
                          {
                            // No blocking ConnectionData().getConnection(false,
                            // false) here: that call did a synchronous
                            // InternetAddress.lookup('google.com') DNS probe plus
                            // sendImagesInImageMap() + historySync() (verified in
                            // lib/model/connection_data.dart), stalling the logout
                            // 1-3s before the login page appeared. Logout safety
                            // does NOT depend on it — the dataOk() guard below
                            // (transactionOK() → #DATA_OK) already blocks logout
                            // while local history is unsynced; image/history sync
                            // run on their own triggers (connectivity listener,
                            // app resume, timer).
                            if (await dataOk(context)) {
                              actionLock('signout case ftz_row_of_button');
                              // Order matters. signOut() resets the shell to the
                              // login page (guest-snapshot swap → showSignInPage)
                              // while keeping the CURRENT page visible until it
                              // completes. add(LoggedOut()) yields Unauthenticated,
                              // which rebuilds LinkReduxApp → MainPage(UniqueKey())
                              // → a FRESH MainPageState whose pageName field-inits
                              // to `home`. Firing it FIRST would paint the
                              // authenticated home page for a beat (before
                              // screenUIComponent is swapped to the guest UI) — the
                              // "jumps to home before login" flash. So swap the UI
                              // first, THEN trigger the auth-state rebuild (which
                              // also does the real FirebaseAuth/Google signOut via
                              // systemSignOut()), landing straight on login.
                              //
                              // Capture the bloc BEFORE awaiting: signOut()'s
                              // showSignInPage() swaps this page's widgets out,
                              // unmounting this button's `context`. The
                              // AuthenticationBloc is provided above MainPage
                              // (main.dart), so the captured ref stays valid.
                              final authBloc =
                                  BlocProvider.of<AuthenticationBloc>(context);
                              await signOut();
                              authBloc.add(LoggedOut());
                            }
                          }
                          break;

                        default:
                          {
                            if (routeExist(buttonData['route'])) {
                              String pageToGo = buttonData['route'] ?? scrName;
                              routeStack.push(pageToGo);
                              gotoRoute(pageToGo);
                            } // end if routeExist
                          }
                      } // end switch
                      var approvalScreenTx = transactionStore.state.screenTx;
                      String approvalRole =
                          (approvalScreenTx['approval_role'] ?? '')
                              .toString()
                              .toUpperCase();
                      if (approvalRole == 'APPROVER' ||
                          approvalRole == 'MAKER') {
                        String rawActions = (buttonData['actions'] ?? '')
                            .toString();
                        String actionsStr =
                            autheniumDecode(rawActions) ?? rawActions;
                        if (actionsStr.isNotEmpty) {
                          await _updateApprovalChain(
                            actionsStr,
                            approvalScreenTx,
                            scrName,
                          );
                        }
                      }

                      if (hasChain) {
                        await doChain(context, scrName, buttonData['chain']);
                      }
                      if (dialog ?? false) {
                        Get.back();
                      }
                    }
                  : null,
              child: Text(
                (autheniumDecode(buttonData['text']?.toString()) ?? "").split(
                  separator[1],
                )[0],
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ), // on pressed
            ),
          );
        } catch (er) {
          return ElevatedButton(
            child: Text("--Button-- $er"), // error in button
            onPressed: () {},
          );
        }
      }

      Widget buttonToShow;
      if (position != null) {
        // This is a state-managed button, wrap it in a GetBuilder.
        buttonToShow = GetBuilder<WidgetUpdateController>(
          id: '${widget.scrName}-$position',
          builder: (_) {
            txfControllerCheck(widget.scrName, position);
            final controller = txfController[widget.scrName]![position]!;
            return buildActualButton(controller.isEnabled);
          },
        );
      } else {
        // This is a static button, build it directly.
        final bool isEnabled =
            (buttonData['isEnabled']?.toString().toLowerCase() ?? 'true') ==
            'true';
        buttonToShow = buildActualButton(isEnabled);
      }

      if (buttonData['width'] is num) {
        bannerComponent.add(buttonToShow);
      } else if (children.length > 1) {
        bannerComponent.add(Expanded(child: buttonToShow));
      } else {
        bannerComponent.add(
          SizedBox(width: double.infinity, child: buttonToShow),
        );
      }
    } // end for loop
    return bannerComponent;
  } // end of buildButtonList

  WrapAlignment _toWrapAlignment(String? alignment) {
    switch ((alignment ?? 'start').toLowerCase()) {
      case 'end':
        return WrapAlignment.end;
      case 'center':
      case 'centre':
        return WrapAlignment.center;
      case 'spacebetween':
        return WrapAlignment.spaceBetween;
      case 'spaceevenly':
        return WrapAlignment.spaceEvenly;
      case 'spacearound':
        return WrapAlignment.spaceAround;
      default:
        return WrapAlignment.start;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Container(
      margin: EdgeInsets.only(
        top: (widget.component['beforeSpacing'] ?? 0.0).toDouble(),
        bottom: (widget.component['afterSpacing'] ?? 0.0).toDouble(),
      ),
      padding: EdgeInsets.fromLTRB(
        widget.lPad + (widget.component['leftPadding'] ?? 0.0).toDouble(),
        widget.tPad,
        widget.rPad + (widget.component['rightPadding'] ?? 0.0).toDouble(),
        widget.bPad,
      ),
      child: BlocBuilder<TimerBloc, TimerState>(
        builder: (context, state) {
          final List<dynamic> btns = widget.component['children'] ?? [];
          final bool useRow =
              btns.length > 1 && btns.every((b) => b['width'] is! num);
          final buttonWidgets = buildButtonList(
            btns,
            widget.scrName,
            dialog: widget.dialog,
          );
          if (useRow) {
            return Row(spacing: 8, children: buttonWidgets);
          }
          return Wrap(
            alignment: _toWrapAlignment(widget.component['alignment']),
            children: buttonWidgets,
          );
        },
      ),
    );
  }

  @override
  // implement wantKeepAlive
  bool get wantKeepAlive => true;
}
