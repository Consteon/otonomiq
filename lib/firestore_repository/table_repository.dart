import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import '../redux/screen_transaction.dart';
import '../global.dart';
import '../global2.dart';
import 'package:intl/intl.dart';
import '../api.dart';
import '../crypto/auth_crypto.dart';
import '../states/mobile_table_controller.dart';
import 'firestore_generic_repository.dart';
import '../model/ftz_scanned_code.dart';

/// Returns the number of seconds from the epoch time, modulo 86400.
/// The documentName parameter is ignored for now.
Future<int> firestoreSequential(String documentName) async {
  // Add a delay to simulate a network request
  // await Future.delayed(const Duration(milliseconds: 500));
  // Get the current time in milliseconds since epoch
  // final int millisecondsSinceEpoch = DateTime.now().millisecondsSinceEpoch;
  // Convert to seconds
  // final int secondsSinceEpoch = (millisecondsSinceEpoch / 1000).round();
  // Return the modulo of 86400
  // return secondsSinceEpoch % 86400;
  // return secondsSinceEpoch % 99;
  final int returnValue = await getNumber(documentName);
  return returnValue;
} // End of firestoreSequential

Future<int> getNumber(String documentName) async {
  int currentTableVid = consteonVid;
  String collectionPath = 'MobileTable/$currentTableVid/counters';
  final docRef =
  FirebaseFirestore.instance.collection(collectionPath).doc(documentName);

  try {
    // Run a transaction to ensure atomic increment.
    final newCounterValue =
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);

      if (!snapshot.exists) {
        // If the document doesn't exist, create it with the initial value.
        transaction.set(docRef, {'c': 1});
        return 1;
      }

      // If the document exists, increment the counter.
      final newCounter = (snapshot.data()!['c'] ?? 0) + 1;
      transaction.update(docRef, {'c': newCounter});
      return newCounter;
    });

    return newCounterValue;
  } catch (e) {
    debugPrint("Error getting new number: $e");
    // Return a default or error value.
    return 0;
  }
} // End of getNumber

/// Fetches a static table from Firestore, processes it, and returns the
/// content of the specified table.
///
/// - [tableCode]: The base name of the document in Firestore.
/// - [index]: An optional integer.
/// - [indexTableString]: An optional filter string for 'D' type tables.
///
/// Returns the content of the indexed table if an index is provided,
/// otherwise returns the content of the base table. Returns null if
//  the document doesn't exist or an error occurs.

Future<List<dynamic>?> readFromFirestoreTable(
    int tableVid,
    String tableCode,
    String internalTableCode, {
      int? index,
      String indexTableString = '', // Add new parameter
    }) async {
  try {
    String collectionPath = 'MobileTable/$tableVid/tables';
    DocumentReference tableDocRef =
    FirebaseFirestore.instance.collection(collectionPath).doc(tableCode);

    DocumentSnapshot documentSnapshot = await tableDocRef.get();

    if (documentSnapshot.exists) {
      Map<String, dynamic> data =
      documentSnapshot.data() as Map<String, dynamic>;
      String headerString = data['hd'] ?? '0${separator[6]}';
      final String indexString = (index != null) ? (index - 1).toString() : '';

      if (data['tt'] == 'D') {
        // If the table is a dynamic table, pass the filter string.
        await createInternalTableDynamic(
            internalTableCode, documentSnapshot, headerString,
            index: indexString,
            indexTableString: indexTableString); // Pass the filter string
      } else {
        // static array table data ['tt] == 'A'
        String arrayString = data['tc'] ?? '[]';
        // This function populates the local `tableContent` map.
        createInternalTable(
          internalTableCode,
          arrayString,
          headerString,
          index: indexString,
        );
      } // end if (data['tt'] == 'D')
      return tableContent[internalTableCode];
    } else {
      devPrint(
          'Error: Document with tableCode "$collectionPath/$tableCode" does not exist.');
      return null; // Document not found
    }
  } catch (e) {
    devPrint(
        'An error occurred while reading from static table "$tableCode": $e');
    return null; // Error occurred
  }
} // end readFromFirestoreTable

// Future<List<dynamic>?> readFromFirestoreTable(
//   int tableVid,
//   String tableCode,
//   String internalTableCode, {
//   int? index,
// }) async {
//   try {
//     String collectionPath = 'MobileTable/$tableVid/tables';
//     DocumentReference tableDocRef =
//         FirebaseFirestore.instance.collection(collectionPath).doc(tableCode);
//
//     DocumentSnapshot documentSnapshot = await tableDocRef.get();
//
//     if (documentSnapshot.exists) {
//       Map<String, dynamic> data =
//           documentSnapshot.data() as Map<String, dynamic>;
//       String headerString = data['hd'] ?? '0${separator[6]}';
//       final String indexString = (index != null) ? (index - 1).toString() : '';
//       String returnTableKey =
//           index != null ? '$tableCode$indexString' : tableCode;
//       if (data['tt'] == 'D') {
//         // If the table is a static table, we can directly return the content.
//         await createInternalTableDynamic(
//             internalTableCode, documentSnapshot, headerString,
//             index: indexString);
//       } else {
//         // static array table data ['tt] == 'A'
//         String arrayString = data['tc'] ?? '[]';
//         // This function populates the local `tableContent` map.
//         createInternalTable(
//           internalTableCode,
//           arrayString,
//           headerString,
//           index: indexString,
//         );
//       } // end if (data['tt'] == 'D')
//       return tableContent[internalTableCode];
//     } else {
//       devPrint(
//           'Error: Document with tableCode "$collectionPath/$tableCode" does not exist.');
//       return null; // Document not found
//     }
//   } catch (e) {
//     devPrint(
//         'An error occurred while reading from static table "$tableCode": $e');
//     return null; // Error occurred
//   }
// } // end readFromStaticTable

/// An asynchronous function to handle writing the scanned data to a single static table.
/// This will now write an empty list if provided, which can be used to clear a table.
Future<void> writeToStaticTable(
    int tableVid, String tableCode, Map<String, dynamic> dataRows) async {
  if (tableCode.isEmpty) {
    return;
  }
  try {
    devPrint('⚠️ try to save to $tableCode');
    Map<String, dynamic> data = Map.from(dataRows);
    data['cr'] = DateTime.now().millisecondsSinceEpoch;
    // Ensure the tableName is valid and not empty.
    if (tableCode.isEmpty) {
      devPrint('Table name cannot be empty.');
      return;
    }
    // If dataRows is empty, we can clear the table or write an empty list.
    if (dataRows.isEmpty) {
      devPrint('No data to write to table: $tableCode, skipping write.');
      return;
    }
    String collectionPath = 'MobileTable/$tableVid/tables';
    DocumentReference tableDocRef =
    FirebaseFirestore.instance.collection(collectionPath).doc(tableCode);
    // tableDocRef.set(data);
    _writeWithRetry(tableDocRef, data, maxRetries: 3);
  } catch (e) {
    devPrint('Error in writeToStaticTable: $e');
    return; // Exit if there's an error
  }
} // end writeToStaticTable

/// Private helper function that performs the write and retries on failure.
void _writeWithRetry(
    DocumentReference docRef,
    Map<String, dynamic> data, {
      required int maxRetries,
      int attempt = 1,
      Duration delay = const Duration(seconds: 1),
    }) {
  docRef.set(data).then((_) {
    // SUCCESS CASE
    devPrint('✅ Successfully wrote to ${docRef.path} on attempt #$attempt.');
  }).catchError((error) {
    // FAILURE CASE
    devPrint('⚠️ Write failed on attempt #$attempt for ${docRef.path}: $error');

    if (attempt < maxRetries) {
      // --- RETRY LOGIC ---
      final nextDelay =
      Duration(seconds: delay.inSeconds * 2); // Exponential backoff
      devPrint('Retrying in ${nextDelay.inSeconds} seconds...');

      // Wait for the delay, then call this function again
      Future.delayed(nextDelay, () {
        _writeWithRetry(
          docRef,
          data,
          maxRetries: maxRetries,
          attempt: attempt + 1, // Increment the attempt counter
          delay: nextDelay, // Pass the new, longer delay
        );
      });
    } else {
      // --- FINAL FAILURE ---
      devPrint(
          '❌ All $maxRetries attempts to write to ${docRef.path} have failed.');
    }
  });
}

/// Parses the targetTable string and returns a map of tables to be created,
/// instead of writing them directly.
///
/// - `targetTableConfig`: A string defining the mapping of groups to table names.
/// - `groupedCodes`: A map where keys are group names and values are lists of ScannedCode objects.
///
/// Returns a map where keys are table names and values are the structured table content.
Map<String, dynamic> writeMultipleTablesTemporary(
    String targetTableConfig, Map<String, List<ScannedCode>> groupedCodes) {
  final Map<String, dynamic> result = {};

  if (targetTableConfig.isEmpty || groupedCodes.isEmpty) {
    return result;
  }

  // 1. Parse the targetTableConfig string.
  final Map<String, List<String>> groupToTableMap = {};
  final mainParts = targetTableConfig.split('◆');
  for (final part in mainParts) {
    final subParts = part.split('◇');
    if (subParts.length == 2) {
      final groupKey = subParts[0].trim();
      final tableName = normalizeTableName(subParts[1].trim());
      if (groupToTableMap.containsKey(groupKey)) {
        groupToTableMap[groupKey]!.add(tableName);
      } else {
        groupToTableMap[groupKey] = [tableName];
      }
    }
  }

  if (groupToTableMap.isEmpty) {
    devPrint('Could not parse targetTable config: $targetTableConfig');
    return result;
  }

  // 2. Iterate over the provided groups.
  groupedCodes.forEach((groupName, codes) {
    // final validDataRows = codes
    //     .where(
    //         (c) => c.status == ValidationStatus.valid && c.refDataRow != null)
    //     .map((c) => c.refDataRow!)
    //     .toList();
    // for (var innerList in validDataRows) {
    //   if (innerList.isNotEmpty) {
    //     innerList.removeAt(0);
    //   }
    // }
    final validDataRows = codes
        .where(
            (c) => c.status == ValidationStatus.valid && c.refDataRow != null)
        .map((c) {
      final row = c.refDataRow!;
      // Use sublist(1) to create a new list containing all elements
      // except the first. Handle the empty list case.
      return row.isNotEmpty
          ? row.sublist(1)
          : <dynamic>[]; // Or a more specific type
    }).toList();

    final targetTables = groupToTableMap[groupName];
    if (targetTables != null) {
      final checksum = createChecksumSha3(validDataRows).checksum;
      final headerString = '${checksum.toString().padLeft(14, '0')}☆☆☆';

      final tableData = {
        'tc': jsonEncode(validDataRows),
        'cs': checksum,
        'hd': headerString,
        'st': 'A',
        'tt': 'A',
      };

      for (final tableName in targetTables) {
        result[tableName] = tableData;
      }
    }
  });

  // 3. Handle the special 'all' case.
  final allTableNames = groupToTableMap['all'];
  if (allTableNames != null) {
    final allValidScannedCodes = groupedCodes.values
        .expand((codeList) => codeList)
        .where((sc) =>
    sc.status == ValidationStatus.valid && sc.refDataRow != null)
        .toList();

    final uniqueCodes = <String>{};
    final uniqueValidDataRows = <List<dynamic>>[];
    for (final sc in allValidScannedCodes) {
      if (uniqueCodes.add(sc.code)) {
        uniqueValidDataRows.add(sc.refDataRow!.sublist(1));
      }
    }

    final checksum = createChecksumSha3(uniqueValidDataRows).checksum;
    final headerString = '${checksum.toString().padLeft(14, '0')}☆☆☆';

    final allTableData = {
      'tc': jsonEncode(uniqueValidDataRows),
      'cs': checksum,
      'hd': headerString,
      'st': 'A',
      'tt': 'A',
    };

    for (final tableName in allTableNames) {
      result[tableName] = allTableData;
    }
  } // end 'all' case

  return result;
} // end writeMultipleTablesTemporary

/// Parses the targetTable string and writes ONLY THE VALID codes from each group to their corresponding table(s).
/// If a group has no valid codes, an empty list will be written to the target table(s).
///
/// - `targetTableConfig`: A string defining the mapping of groups to table names.
///   A group key can appear multiple times.
///   Example: 'all◇warehouse_inventory◆CNG12◇stock_12◆CNG16◇stock_16◆CNG16◇stock2_16'
/// - `groupedCodes`: A map where keys are group names and values are lists of ScannedCode objects.
Future<void> writeMultipleTables(String targetTableConfig,
    Map<String, List<ScannedCode>> groupedCodes) async {
  if (targetTableConfig.isEmpty || groupedCodes.isEmpty) {
    return;
  }

  // 1. Parse the targetTableConfig string into a map of {groupName: [tableName1, tableName2, ...]}
  final Map<String, List<String>> groupToTableMap = {};
  final mainParts = targetTableConfig.split('◆');
  for (final part in mainParts) {
    final subParts = part.split('◇');
    if (subParts.length == 2) {
      final groupKey = subParts[0].trim();
      final tableName = subParts[1].trim();
      if (groupToTableMap.containsKey(groupKey)) {
        groupToTableMap[groupKey]!.add(tableName);
      } else {
        groupToTableMap[groupKey] = [tableName];
      }
    }
  }

  if (groupToTableMap.isEmpty) {
    debugPrint('Could not parse targetTable config: $targetTableConfig');
    return;
  }

  // 2. Iterate over the provided groups and write to the corresponding table(s)
  groupedCodes.forEach((groupName, codes) {
    // MODIFIED: Filter for valid codes with data rows and extract the full row.
    final validDataRows = codes
        .where(
            (c) => c.status == ValidationStatus.valid && c.refDataRow != null)
        .map((c) => c.refDataRow!)
        .toList();

    // Find the list of tables for the current group
    final targetTables = groupToTableMap[groupName];
    if (targetTables != null) {
      // Write the codes to each table associated with the group
      for (final tableName in targetTables) {
        // MODIFIED: Pass the list of rows to the updated function.
        // writeToStaticTable(tableName, validDataRows);
      }
    }
  });

  // 3. Handle the special 'all' case separately
  final allTableNames = groupToTableMap['all'];
  if (allTableNames != null) {
    // MODIFIED: Get all valid codes with data rows.
    final allValidScannedCodes = groupedCodes.values
        .expand((codeList) => codeList) // Flatten the list of lists
        .where((sc) =>
    sc.status == ValidationStatus.valid && sc.refDataRow != null)
        .toList();

    // MODIFIED: Deduplicate based on the code string to avoid saving the same item multiple times.
    final uniqueCodes = <String>{};
    final uniqueValidDataRows = <List<dynamic>>[];
    for (final sc in allValidScannedCodes) {
      // .add() returns true if the element was added (i.e., was not already present)
      if (uniqueCodes.add(sc.code)) {
        uniqueValidDataRows.add(sc.refDataRow!);
      }
    }

    for (final tableName in allTableNames) {
      // MODIFIED: Pass the deduplicated list of rows.
      // writeToStaticTable(tableName, uniqueValidDataRows);
    }
  }
} // end writeMultipleTables

String stringFormat(String? stringInp, Map<String, dynamic>? fieldArray) {
  // format inpTime into formatted string with timeZone calculation
  Intl.defaultLocale = transactionStore.state.screenTx['#LOCALE'];
  final double deviceTimeZone = DateTime.now().timeZoneOffset.inSeconds / 3600;
  String result = formatErrorString;
  if (stringInp != null) {
    if (fieldArray != null) {
      double? timeZone = fieldArray['t'];
      String? format = fieldArray['f'];
      String? formatType = fieldArray['type']; // d = date; n = number

      if (formatType == null) {
        result = stringInp;
      } else {
        double inp = double.parse(stringInp);
        switch (formatType) {
          case 'd':
            double myTimeZone = (timeZone ?? deviceTimeZone) - deviceTimeZone;
            int myTime = (inp + (myTimeZone) * 3600000).truncate();
            if (format == null || format.trim().isEmpty) {
              result = myTime.toString();
            } else {
              try {
                result = DateFormat(format)
                    .format(DateTime.fromMillisecondsSinceEpoch(myTime));
              } catch (e) {
                result = formatErrorString;
              } // end try
            } // end if (format == null || format.trim().isEmpty)
            break;

          case 'n':
            NumberFormat formatter = NumberFormat(format);
            result = formatter.format(inp);
            break;
        }
      } // end if (formatType != null)
    } // end if (fieldArray == null)
  } // end if (inpTime == null)
  return result;
} // end of stringFormat

Map<String, dynamic> parseField(String? inp) {
  // parse inp separated by | into
  // c (content) : %timeReceived% , %appVid%, %vid%, %receivingPage% integer.integer
  // , t (timezone), f (format)
  // output sample:
  //   {c: %timeReceived%, t: 7, f: dd MM yyyy hh:mm}
  Map<String, dynamic> result = {};
  if (inp != null) {
    List<String> inpArray1 = inp.split('|');
    for (int i = 0; i < inpArray1.length; i++) {
      switch (inpArray1[i][0]) {
        case 'T':
          try {
            result['t'] = double.parse(inpArray1[i].substring(1));
          } catch (e) {
            // do nothing
          }
          break;

        case 'D':
          result['f'] = inpArray1[i].substring(1);
          result['type'] = 'd';
          break;

        case 'N':
          result['f'] = inpArray1[i].substring(1);
          result['type'] = 'n';
          break;

        default:
          result['c'] = inpArray1[i];
      } // end switch (inpArray1[i][0])
    } // end for inpArray1
  } // end  if (inp != null)
  return result;
} // end of parseField

/// Parses a string like "{key1:val1;key2:val2}" into a Map.
Map<String, String> _parsePriceMap(String coreString) {
  final Map<String, String> priceMap = {};
  final pairs = coreString.split(';');
  for (final pair in pairs) {
    final parts = pair.split(':');
    if (parts.length == 2) {
      priceMap[parts[0]] = parts[1];
    }
  }
  return priceMap;
} // end of _parsePriceMap

// Add this new function inside table_repository.dart

/// Handles the creation of a summary table from a master and detail table.
Future<String> _handleSummaryTableCreation(
    int tableVid,
    String tableName,
    List<dynamic> definition,
    ) async {
  try {
    // 1. Get required parameters from the definition

    // if (masterTableName == '' || detailTableName == '') {
    //   return 'Error: Master or Detail table not defined.';
    // }

    // 2. Fetch the source table data from the local cache
    final masterTableData = tableContent['masterArray'] ?? [];
    final detailTableData = tableContent['detailArray'] ?? [];
    // Write the header/metadata document
    int retention = retentionDefault;
    String description = 'Summary Table';
    String flag = '';
    int priceMapColumnIndex = 1;
    int groupingColumnIndex = 1;
    final Map<int, String> columnRules = {};
    int maxColumnIndex = 0;

    for (var field in definition) {
      if (field.length > 1) {
        String key = field[0].toString();
        if (key.startsWith('<') && key.endsWith('>')) {
          try {
            // Parse column definitions like '<1>', '<2>'
            int index = int.parse(key.substring(1, key.length - 1)) - 1;
            if (index >= 0) {
              columnRules[index] = field[1].toString();
              if (index > maxColumnIndex) {
                maxColumnIndex = index;
              }
            }
          } catch (e) {
            // Ignore if parsing fails
          }
        } else {
          switch (field[0]) {
            case 'master':
              priceMapColumnIndex = int.parse(field[2] ?? '1');
              break;
            case 'detail':
              groupingColumnIndex = int.parse(field[2] ?? '1');
              break;
            case 'retention':
              retention = int.tryParse(field[1]) ?? 30160;
              break;
            case 'description':
              description = field[1];
              break;
            case 'flag':
              flag = field[1];
              break;
          } // end switch (field[0]
        } //
      } // end if (field.length > 1
    } // end for field in definition

    final Map<String, int> groupedCounts = {};
    for (final row in detailTableData) {
      // Assuming detail table rows are like [id, code, name]
      if (row.length > groupingColumnIndex) {
        final key = row[groupingColumnIndex].toString();
        groupedCounts[key] = (groupedCounts[key] ?? 0) + 1;
      }
    }

    // Master table is expected to have only one row of data
    final masterRow = masterTableData[0];
    if (masterRow.length <= priceMapColumnIndex) {
      return 'Error: Price map column index is out of bounds for master table.';
    }

    final priceMap = _parsePriceMap(masterRow[priceMapColumnIndex].toString());

    // 5. Build the summary rows
    final List<List<dynamic>> summaryRows = [];
    groupedCounts.forEach((key, count) {
      final price = priceMap[key] ?? '0.00'; // Default price if not found
      // Build the row according to the column definitions
      // This is hardcoded to your example for simplicity but could be made dynamic
      // final newRow = [key, count.toString(), price];
      // Initialize a new row with the correct size
      final newRow = List<dynamic>.filled(maxColumnIndex + 1, null);
      // Populate the row based on the parsed column rules
      columnRules.forEach((index, rule) {
        dynamic value;
        switch (rule) {
          case '★detail.key★':
            value = key;
            break;
          case '★detail.count★':
            value = count.toString();
            break;
          case '★master.contentNumber★':
            value = price;
            break;
          default:
            value = rule; // Treat as a literal string
            break;
        }
        if (index < newRow.length) {
          newRow[index] = value;
        }
      });
      summaryRows.add(newRow);
    });

    // 6. Write the result to a new Firestore table
    // For a dynamic table (type 'D'), we write each row as a document.
    // The document name can be the item name (the key).
    // final Map<String, dynamic> documentsToWrite = {};
    // for (var row in summaryRows) {
    //   final docName = getDocumentName(row[0].toString());
    //   documentsToWrite[docName] = {
    //     'c': jsonEncode(row.sublist(1))
    //   }; // content is count and price
    // }

    String collectionPath = 'MobileTable/$tableVid/tables';
    DocumentReference tableDocRef =
    FirebaseFirestore.instance.collection(collectionPath).doc(tableName);
    String contentString = jsonEncode(summaryRows);
    final checksum = createChecksumSha3(contentString).checksum;
    final headerString = '${checksum.toString().padLeft(14, '0')}☆☆☆';
    await tableDocRef.set({
      'tt': 'A', // Array table
      'd': description,
      'f': flag,
      'r': retention,
      'cs': checksum,
      'hd': headerString,
      'cr': DateTime.now().millisecondsSinceEpoch,
      'tc': jsonEncode(summaryRows),
      'st': 'A', // active
    });

    // Write each summary row as a document in the 'content' subcollection
    // final contentCollection = tableDocRef.collection('content');
    // for (final contentRow in summaryRows) {
    //   final contentMap = {
    //     'c': jsonEncode(contentRow),
    //     't': DateTime.now().millisecondsSinceEpoch,
    //   };
    //   await contentCollection.add(contentMap);
    // }
    return 'Ok';
  } catch (e) {
    debugPrint('Error creating summary table "$tableName": $e');
    return 'Error: $e';
  }
} // end of _handleSummaryTableCreation

Future<List<String>> writeToTable(String? inp, String eventRowString) async {
  /*
  saveToTable⬤appendToTable⬤addToTable (deprecated)
  saveToTable = overwrite existing table (table type A)
  appendToTable = add to existing table (table type D)
  saveToTable = overwrite existing table (table type A), backward compatible
  write to firestore table in collection MobileTable/<appVid>/tables
  format inp :
    "tableName1
    ☆vid◼<vid>
    ☆retention◼<retention>
    ☆description◼<description>
    ☆flag◼<flag>
    ☆<1>◼field1Content
    ☆<2>◼field2Content

    ★tableName2
    ☆<1>◼field1Content
    ☆<2>◼field2Content

    default retention = 20160 (14 days)
    example of inp:
    'MobileTableTest1.reporttest☆retention◼30160☆description◼This is a test table☆flag◼flagabc☆<1>◼%timestamp%☆<2>◼◀2▶☆<3>◼test ◀3▶ me☆<4>◼https://www.google.com/maps/place/◀5.3▶=◀5.1▶<(◀1▶)☆<5>◼%vid%★test.something☆<1>◼cost centre 1☆<2>◼◀1▶☆<3>◼◀3▶☆<4>◼site satu'
  ref: reference array
  timestamp: content for %timestamp%
  vid: content cor %VID%

  output:
  [status table1,status table2,etc]
  Ok = successfully
  other = error message from system
  example:
  [Ok,Permission error...]

  example of writeToTable
    String result = writeToTable(inp,ref,11111111,7777777,defaultAppVid);
  */
  debugPrint('writeToTable inp = $inp, eventRowString = $eventRowString');
  int vid = appCodeController.applicationTableVid;
  int tableVid = vid;
  //final int vid = transactionStore.state.screenTx['#VID'];
  List<String> result = [];
  try {
    List<dynamic> eventRow = jsonDecode(eventRowString);
    if (inp != null && inp.isNotEmpty) {
      List<dynamic> ref = parseEventString(eventRow);
//   print ('ref=$ref');
      String decodedInp = autheniumDecode(inp) ?? '';
      List<dynamic> splitInput = splitTableInput(decodedInp ?? '');
      List<Future> tableWriteList = [];
      for (int i = 0; i < splitInput.length; i++) {
        String tempResult = '';
        String tableCollection = '';
        try {
          Map<String, dynamic> data = {'st': 'A', 'r': retentionDefault};
          dynamic tableProcessed = splitInput[i];
          for (dynamic element in splitInput[i]) {
            if (element.length > 1) {
              switch (element[0].toString().trim().toLowerCase()) {
                case 'tablevid':
                  try {
                    tableVid = int.parse(element[1].toString().trim());
                  } catch (eVid) {
                    vid = appCodeController.applicationTableVid;
                  }
                  break;
                case 'retention':
                  data['r'] = int.tryParse(element[1]) ?? retentionDefault;
                  break;
                case 'description':
                  data['d'] = element[1];
                  break;
                case 'flag':
                  data['f'] = element[1];
                  break;
              } // end switch
            } // end if
          } // end for

          List<dynamic> stringResult = [];
          String tableName = '';
          if (splitInput[i][0].length > 1) {
            if (splitInput[i][0][1].trim() == 'A') {
              // write to static / array table\
              stringResult = await parseTableInput(
                  splitInput[i],
                  ref,
                  tableVid,
                  appCodeController.applicationTableVid,
                  eventRow[0],
                  eventRow[1]);
              // modify stringResult[0] to determine the table type
              stringResult[0] = getDocumentName(stringResult[0]);
              tableName = stringResult[0];
              devPrint(
                  "Writing 'A' table = MobileTable/$tableVid/tables/$tableName");
              List<dynamic> dataRows = [];
              final checksum = createChecksumSha3(stringResult[4]).checksum;
              final headerString = '${checksum.toString().padLeft(14, '0')}☆☆☆';
              data['tt'] = splitInput[i][0][1]; // 'A' for array table
              data['tc'] = "[${stringResult[4]}]";
              data['cs'] = checksum;
              data['hd'] = headerString;
              tableWriteList.add(writeToStaticTable(tableVid, tableName, data));
              continue;
            } else if (splitInput[i][0][1].trim() == 'S') {
              // This is a summary task, delegate to the new handler
              // summary table should be defined after master and detail table
              // and wait until the master and detail table are written to firestore
              await Future.wait(tableWriteList);
              stringResult = await parseTableInput(
                  splitInput[i],
                  ref,
                  tableVid,
                  appCodeController.applicationTableVid,
                  eventRow[0],
                  eventRow[1]);
              // modify stringResult[0] to determine the table type
              stringResult[0] = getDocumentName(stringResult[0]);
              tableName = stringResult[0];
              devPrint("Writing summary table = $consteonVid/$tableName");
              final List<dynamic> definitionArray =
              List<dynamic>.from(splitInput[i]);
              // for (final field in splitInput[i]) {
              //   if (field.length > 1) {
              //     final key = field[0].toString();
              //     // final value = field.sublist(1).map((e) => e.toString()).toList();
              //     final value = List<String>.from(
              //         field.sublist(0).map((e) => e.toString()));
              //     definitionArray.add(value);
              //     // definitionMap[field[0].toString()] = field[1].toString();
              //   }
              // }
              final status = await _handleSummaryTableCreation(
                  tableVid, tableName, definitionArray);
              result.add(status);
              continue; // Skip to the next table definition
            } // end if (splitInput[i][0][1] == 'A')
          } // end if (splitInput[i][0].length > 1)
          // stringResult = await parseTableInput(splitInput[i], ref, vid,
          //     appCodeController.applicationVid, eventRow[0], eventRow[1]);

          stringResult = await parseTableInput(splitInput[i], ref, tableVid,
              appCodeController.applicationTableVid, eventRow[0], eventRow[1]);
          // modify stringResult[0] to determine the table type
          stringResult[0] = getDocumentName(stringResult[0]);
          tableName = stringResult[0];
          tempResult += stringResult.toString();
          // tableCollection =
          //     'MobileTable/${appCodeController.applicationTableVid.toString()}/tables';
          tableCollection = 'MobileTable/$tableVid/tables';
          devPrint('table = $tableCollection/$tableName');
          // 0=table name; 1 = retention in minute; 2 = Description;
          // 3 = flag; 4 = content (string)
          MobileTableController mtc = MobileTableController();
          mtc.setApplicationTableVid(appCodeController.applicationTableVid);
          mtc.setApplicationTableVid(tableVid);
          mtc.setTableRetention(int.parse(stringResult[1]));
          mtc.setTableDescription(stringResult[2]);
          mtc.setTableFlag(stringResult[3]);
          result.add(await mtc.addContent(
              tableName, stringResult[4], stringResult[5]));
          mtc.dispose();
          // add parameter to mtc for retention, description, and flag
          // result.add('Ok');
        } catch (e) {
          devPrint('error in writeToTable loop $e');
          tempResult = e.toString();
          result.add(tempResult);
        }
        devPrint("parseTableInput$i=$tempResult");
      } // end  for (inp in splitInput)
    } // end if (inp != null && inp.isNotEmpty)
  } catch (e) {
    devPrint('error in writeToTable outer try $e');
  }
  return result;
} // end of writeToTable

/// Auto-detect type of a raw search value string.
/// Order: bool ('true'/'false') → num → string fallback.
dynamic _parseSearchValue(String raw) {
  final trimmed = raw.trim();
  final lower = trimmed.toLowerCase();
  if (lower == 'true') return true;
  if (lower == 'false') return false;
  return num.tryParse(trimmed) ?? raw;
}

/// Update existing row(s) in dynamic table, partial column patch.
/// Input format mirrors addToTable but with a `search` directive identifying
/// the row to update. Only columns explicitly listed in input get patched;
/// other columns retain their current value in Firestore.
Future<List<String>> updateTableRow(
    String? inp, String eventRowString) async {
  debugPrint('updateTableRow inp = $inp');
  int vid = appCodeController.applicationTableVid;
  int tableVid = vid;
  List<String> result = [];
  try {
    if (inp == null || inp.isEmpty) {
      return result;
    }
    List<dynamic> eventRow = jsonDecode(eventRowString);
    List<dynamic> ref = parseEventString(eventRow);
    String decodedInp = autheniumDecode(inp) ?? '';
    List<dynamic> splitInput = splitTableInput(decodedInp);

    for (int i = 0; i < splitInput.length; i++) {
      String tempResult = '';
      try {
        // Pull tablevid override if present (mirrors writeToTable).
        for (dynamic element in splitInput[i]) {
          if (element.length > 1 &&
              element[0].toString().trim().toLowerCase() == 'tablevid') {
            try {
              tableVid = int.parse(element[1].toString().trim());
            } catch (_) {
              tableVid = appCodeController.applicationTableVid;
            }
          }
        }

        // Run full parseTableInput to get substituted values + indexContent.
        List<dynamic> stringResult = await parseTableInput(
            splitInput[i],
            ref,
            tableVid,
            appCodeController.applicationTableVid,
            eventRow[0],
            eventRow[1]);
        stringResult[0] = getDocumentName(stringResult[0]);
        String tableName = stringResult[0];
        List<dynamic> contentArray = jsonDecode(stringResult[4]);
        Map<String, dynamic> indexContent =
        (stringResult[5] as Map<String, dynamic>);

        // Identify positions explicitly listed by user (no padded slots).
        Set<int> explicitPositions = {};
        String? searchField;
        dynamic searchValue;
        for (int j = 1; j < splitInput[i].length; j++) {
          if (splitInput[i][j].length < 2) continue;
          String key = splitInput[i][j][0].toString().trim();
          if (key.toLowerCase() == 'search') {
            List<String> parts =
            splitInput[i][j][1].toString().split(separator[3]);
            if (parts.length >= 2) {
              searchField = parts[0].trim();
              String rawValue =
              parts.sublist(1).join(separator[3]).trim();
              searchValue = _parseSearchValue(rawValue);
            }
            continue;
          }
          int openIdx = key.indexOf('<');
          int closeIdx = key.indexOf('>');
          if (openIdx >= 0 && closeIdx > openIdx) {
            try {
              int colNum =
              int.parse(key.substring(openIdx + 1, closeIdx));
              explicitPositions.add(colNum - 1);
            } catch (_) {}
          }
        }

        if (searchField == null) {
          tempResult = 'Error: missing search';
          result.add(tempResult);
          continue;
        }

        Map<int, String> partialFields = {};
        for (int idx in explicitPositions) {
          if (idx >= 0 && idx < contentArray.length) {
            partialFields[idx] = contentArray[idx].toString();
          } else {
            partialFields[idx] = '';
          }
        }

        // Filter index updates to only columns the user actually patched.
        Map<String, dynamic> indexFieldUpdates = {};
        indexContent.forEach((colKey, val) {
          int idx0 = (int.tryParse(colKey) ?? 0) - 1;
          if (explicitPositions.contains(idx0)) {
            indexFieldUpdates[colKey] = val;
          }
        });

        MobileTableController mtc = MobileTableController();
        mtc.setApplicationTableVid(tableVid);
        String opResult = await mtc.updateContent(
          tableName,
          searchField,
          searchValue,
          partialFields,
          indexFieldUpdates: indexFieldUpdates.isEmpty
              ? null
              : indexFieldUpdates,
        );
        mtc.dispose();
        result.add(opResult);
      } catch (e) {
        tempResult = e.toString();
        result.add(tempResult);
        devPrint('error in updateTableRow loop: $e');
      }
    }
  } catch (e) {
    devPrint('error in updateTableRow outer try: $e');
  }
  return result;
} // end of updateTableRow

/// Delete row(s) in dynamic table by query.
/// Input format mirrors addToTable header but only requires `tablevid` and
/// a `search` directive identifying the row(s) to delete.
Future<List<String>> deleteFromTable(
    String? inp, String eventRowString) async {
  debugPrint('deleteFromTable inp = $inp');
  int vid = appCodeController.applicationTableVid;
  int tableVid = vid;
  List<String> result = [];
  try {
    if (inp == null || inp.isEmpty) {
      return result;
    }
    List<dynamic> eventRow = jsonDecode(eventRowString);
    parseEventString(eventRow); // validate format, ref unused for delete
    String decodedInp = autheniumDecode(inp) ?? '';
    List<dynamic> splitInput = splitTableInput(decodedInp);

    for (int i = 0; i < splitInput.length; i++) {
      try {
        String tableName = getDocumentName(
            splitInput[i][0][0].toString().trim());
        String? searchField;
        dynamic searchValue;
        for (int j = 1; j < splitInput[i].length; j++) {
          if (splitInput[i][j].length < 2) continue;
          String key = splitInput[i][j][0].toString().trim().toLowerCase();
          if (key == 'tablevid') {
            try {
              tableVid = int.parse(splitInput[i][j][1].toString().trim());
            } catch (_) {
              tableVid = appCodeController.applicationTableVid;
            }
          } else if (key == 'search') {
            List<String> parts =
            splitInput[i][j][1].toString().split(separator[3]);
            if (parts.length >= 2) {
              searchField = parts[0].trim();
              String rawValue =
              parts.sublist(1).join(separator[3]).trim();
              searchValue = _parseSearchValue(rawValue);
            }
          }
        }

        if (searchField == null) {
          result.add('Error: missing search');
          continue;
        }

        MobileTableController mtc = MobileTableController();
        mtc.setApplicationTableVid(tableVid);
        String opResult =
        await mtc.deleteContent(tableName, searchField, searchValue);
        mtc.dispose();
        result.add(opResult);
      } catch (e) {
        result.add(e.toString());
        devPrint('error in deleteFromTable loop: $e');
      }
    }
  } catch (e) {
    devPrint('error in deleteFromTable outer try: $e');
  }
  return result;
} // end of deleteFromTable

List<dynamic> parseEventString(dynamic inp) {
  final mainSeparator = forbiddenCharacter[3]; // black big circle
  final subSeparator1 = forbiddenCharacter[0]; // black diamond
  final subSeparator2 = forbiddenCharacter[13]; // black star
  List<dynamic> result = [];
  String eventContent = inp[2];
  List<String> inpSplit = eventContent.substring(1).split(mainSeparator);
  if (inpSplit.isNotEmpty) {
    List<String> subEvent = inpSplit[0].split(subSeparator1);
    result.add(subEvent);
  } else {
    result.add([]);
  } // if (inpSplit.isNotEmpty)

  if (inpSplit.length > 1) {
    List<String> subEvent = inpSplit[1].split(subSeparator2);
    result.add(subEvent);
  } else {
    result.add([]);
  } // if (inpSplit.isNotEmpty)
  return result;
} // end of parseEventString

Future<List<dynamic>> parseTableInput(List<dynamic> inpArray, List<dynamic> ref,
    int tableVid, int appVid, int timeReceived, String receivingPage,
    {int sourceIndex = 0}) async {
  const vidNotation = '%vid%';
  const appVidNotation = '%appVid%';
  const timeReceivedNotation = '%timeReceived%';
  const receivingPageNotation = '%receivingPage%';
  const errorNotation = '*';
  final openNotation = forbiddenCharacter[7]; // black left triangle
  final closeNotation = forbiddenCharacter[9]; // black right triangle
  final openNotation2 = forbiddenCharacter[8]; // white left triangle
  final closeNotation2 = forbiddenCharacter[10]; // white right triangle
  const openReplacement = '<<||'; // must be in sync with expression in RegExp
  const closeReplacement = '||>>'; // must be in sync with expression in RegExp
  const openField = '<';
  const closeField = '>';
  const subSourceSeparator = '.';
  final dataSeparator = forbiddenCharacter[0]; // black diamond
  final RegExp exp = RegExp(
      r'<<\|\|(.*?)\|\|>>'); // must be in sync with openReplacement and closeReplacement
  List<dynamic> result = [
    inpArray[0][0].toString().trim(),
    '20160',
    'desc',
    'flag',
    'content',
    {},
  ]; // table name,retention,description,flag,content
  List<String> tempResult = [];
  List<dynamic> masterArray = [];
  List<dynamic> detailArray = [];
  List<List<dynamic>> indexArray = [];

  for (int i = 1; i < inpArray.length; i++) {
    if (inpArray[i].length > 1) {
      switch (inpArray[i][0].toString().trim().toLowerCase()) {
        case 'index':
        // dynamic indexTemp = inpArray[i][1].split(separator[3]);
          for (int j = 1; j < inpArray[i].length; j++) {
            late List<dynamic> indexTemp;
            try {
              indexTemp = inpArray[i][j].split(separator[3]);
              int indexInt = int.parse(indexTemp[0]);
              indexArray.add([indexInt, indexTemp[1]]);
            } catch (e) {
              // do nothing
              devPrint('error in parseTableInput index $e');
            }
          }
          int d = 1;
          break;
        case 'retention':
          result[1] = inpArray[i][1];
          break;
        case 'description':
          result[2] = inpArray[i][1];
          break;
        case 'flag':
          result[3] = inpArray[i][1];
          break;
        case 'master':
          String tableName = normalizeTableName(inpArray[i][1]);
          masterArray =
              await readFromFirestoreTable(tableVid, tableName, tableName) ??
                  [];
          tableContent['masterArray'] = masterArray;
          break;
        case 'detail':
          String tableName = normalizeTableName(inpArray[i][1]);
          detailArray =
              await readFromFirestoreTable(tableVid, tableName, tableName) ??
                  [];
          tableContent['detailArray'] = detailArray;
          break;
        case 'tablevid':
        case 'search':
        // skip, do nothing here
          break;
        default:
          int start = inpArray[i][0].toString().trim().indexOf(openField);
          int end = inpArray[i][0].toString().trim().indexOf(closeField);
          int tableIndex =
              int.parse(inpArray[i][0].substring(start + 1, end)) - 1;
          String notation = inpArray[i][1].toString();
          // notation = notation.replaceAll(vidNotation, vid.toString());
          notation = notation.replaceAll(
              '$openNotation$receivingPageNotation$closeNotation',
              receivingPage);
          notation = notation.replaceAll(
              '$openNotation2$receivingPageNotation$closeNotation2',
              receivingPage);
          notation = notation
              .replaceAll(openNotation, openReplacement)
              .replaceAll(closeNotation, closeReplacement);
          String origin = notation;
          Iterable<RegExpMatch> matches = exp.allMatches(origin);
          for (Match match in matches) {
            String contentString = match.group(1) ?? '';
            String replacement = errorNotation;
            try {
              replacement = ref[sourceIndex][int.parse(contentString) - 1];
            } catch (e) {
              try {
                Map<String, dynamic> fieldMap = parseField(contentString);
                String? sourceValue;
                switch (fieldMap['c']) {
                  case vidNotation:
                    sourceValue = tableVid.toString();
                    break;
                  case appVidNotation:
                    sourceValue = appVid.toString();
                    break;
                  case timeReceivedNotation:
                    sourceValue = timeReceived.toString();
                    break;
                  default:
                    int dotPosition = fieldMap['c']
                        .toString()
                        .trim()
                        .indexOf(subSourceSeparator);
                    if (dotPosition < 0) {
                      sourceValue = ref[0]
                      [int.parse(fieldMap['c'].toString().trim()) - 1];
                    } else {
                      List<String> eventArray = fieldMap['c']
                          .toString()
                          .trim()
                          .split(subSourceSeparator);
                      if (eventArray.length > 1) {
                        int index = int.parse(eventArray[0]) - 1;
                        int subIndex = int.parse(eventArray[1]) - 1;
                        List<String> dataArray =
                        ref[0][index].toString().split(dataSeparator);
                        sourceValue = dataArray[subIndex];
                      } // end if (eventArray.length > 1)
                    } // end if (dotPosition < 0)
                } // end switch (fieldMap['c'])
                replacement = stringFormat(sourceValue, fieldMap);
              } catch (e) {
                replacement = errorNotation;
              } // end of try eventArray
            } // end try
            if (replacement != errorNotation) {
              notation =
                  notation.replaceAll(match.group(0).toString(), replacement);
            }
          } // end for (Match match in matches)

          notation = notation
              .replaceAll(openNotation2, openReplacement)
              .replaceAll(closeNotation2, closeReplacement);
          origin = notation;
          matches = exp.allMatches(origin);
          for (Match match in matches) {
            String substring = match.group(1) ?? '';
            String replacement = errorNotation;
            try {
              if (substring.startsWith('%')) {
                final String indexStr = substring.substring(1); // Remove '%'
                final int refIndex = int.parse(indexStr) - 1;
                final String valueToProcess = ref[1][refIndex];
                replacement = getDocumentName(valueToProcess);
              } else {
                // Original logic for placeholders like ◁8▷
                replacement = ref[1][int.parse(substring) - 1];
              }
            } catch (e) {
              try {
                // Fallback for when int.parse fails (e.g., for "6|T7|D...")
                try {
                  // This logic mirrors the formatting capability of the ◀...▶ placeholder
                  // but uses the second data source (ref[1]).
                  Map<String, dynamic> fieldMap = parseField(substring);
                  String? sourceValue;

                  int dotPosition = fieldMap['c']
                      .toString()
                      .trim()
                      .indexOf(subSourceSeparator);
                  if (dotPosition < 0) {
                    // Simple index, e.g., '6' from "6|T7|..."
                    sourceValue =
                    ref[1][int.parse(fieldMap['c'].toString().trim()) - 1];
                  } else {
                    // Dot notation, e.g., '8.1'
                    List<String> eventArray = fieldMap['c']
                        .toString()
                        .trim()
                        .split(subSourceSeparator);
                    if (eventArray.length > 1) {
                      int index = int.parse(eventArray[0]) - 1;
                      int subIndex = int.parse(eventArray[1]) - 1;
                      List<String> dataArray =
                      ref[1][index].toString().split(dataSeparator);
                      sourceValue = dataArray[subIndex];
                    }
                  }
                  replacement = stringFormat(sourceValue, fieldMap);
                } catch (e2) {
                  replacement = errorNotation;
                }
                // List<String> eventArray =
                //     substring.trim().split(subSourceSeparator);
                // if (eventArray.length > 1) {
                //   int index = int.parse(eventArray[0]) - 1;
                //   int subIndex = int.parse(eventArray[1]) - 1;
                //   List<String> dataArray =
                //       ref[1][index].toString().split(dataSeparator);
                //   replacement = dataArray[subIndex];
                // } // end if (eventArray.length > 1)
              } catch (e) {
                replacement = errorNotation;
              } // end of try eventArray
            } // end try
            notation =
                notation.replaceAll(match.group(0).toString(), replacement);
          } // end for (Match match in matches)

          int maxIndex = tempResult.length - 1;
          if (maxIndex < tableIndex) {
            for (int c = maxIndex; c < tableIndex; c++) {
              tempResult.add('');
            }
          } // end if (tableIndex > len)
          tempResult[tableIndex] = notation;
      } // end switch
    } // end if (inpArray[i].length > 1)
  } // end for inpArray
  result[4] = json.encode(tempResult);
  Map<String, dynamic> indexContent = {};
  for (int i = 0; i < indexArray.length; i++) {
    if (indexArray[i].length > 1) {
      switch (indexArray[i][1].toString().trim().toUpperCase()) {
        case 'S': // String
          indexContent[indexArray[i][0].toString()] =
              tempResult[indexArray[i][0] - 1].toString();
          break;
        case 'B': // boolean
          indexContent[indexArray[i][0].toString()] =
              bool.tryParse(tempResult[indexArray[i][0] - 1].toString());
          break;
        case 'N': // number
          indexContent[indexArray[i][0].toString()] =
              double.tryParse(tempResult[indexArray[i][0] - 1].toString());
          break;
      } // end switch
    }
  }
  result[5] = indexContent;
  return result;
} // end of parseTableInput

void createInternalTable(
    String tableCode,
    String arrayString,
    String headerString, {
      String index = '', // Optional: e.g., '1' or '1◆2◆3'
    }) {
  // 1. Determine all table codes that need to be managed.
  // This includes the base table (e.g., 'myTable') and any indexed tables (e.g., 'myTable1').
  final List<String> allTableCodes = [tableCode];
  if (index.isNotEmpty) {
    allTableCodes.addAll(index.split('◆').map((i) => '$tableCode$i'));
  }

  // 2. Check which of these tables actually need to be rebuilt based on the checksum.
  final int checksum = int.parse(headerString.split(separator[6])[0]);
  final List<String> codesToRebuild = [];

  for (final currentCode in allTableCodes) {
    final Map<String, dynamic>? table =
    transactionStore.state.screenTx['#TABLE$currentCode'];
    if (table == null || table[currentCode] != checksum) {
      codesToRebuild.add(currentCode);
    } else {
      devPrint('same checksum for table $currentCode = $checksum');
    }
  }

  // 3. If no tables need rebuilding, exit early.
  if (codesToRebuild.isEmpty) {
    return;
  }

  // 4. If we are here, at least one table needs rebuilding.
  // Prepare the content ONCE, as it's the same for all tables.
  devPrint('rebuilding tables: ${codesToRebuild.join(', ')}');

  // Process the content array for the `tableContent` map.
  final List<dynamic> tempContent = jsonDecode(arrayString);
  final List<dynamic> processedContent = [];
  for (int i = 0; i < tempContent.length; i++) {
    // Create a mutable copy to avoid modifying the original list if it's reused.
    List<dynamic> member = List.from(tempContent[i]);
    member.insert(0, i.toString()); // Insert sequence number at the beginning.
    processedContent.add(member);
  }

  // Process the array for the `screenTx` store.
  final dynamic tableArrayForTx = jsonDecode(arrayString);

  // 5. Loop ONLY through the codes that need rebuilding and apply the changes.
  for (final currentCode in codesToRebuild) {
    // a. Create the table structure for the screen transaction state.
    final Map<String, dynamic> newTableForTx = {currentCode: checksum};
    for (int i = 0; i < tableArrayForTx.length; i++) {
      newTableForTx[tableArrayForTx[i][0].toString()] = tableArrayForTx[i];
    }

    // b. Dispatch the update to the Redux/Bloc store.
    transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
      '#TABLE$currentCode': newTableForTx,
    })));

    // c. Update local cache/content maps.
    tableContent[currentCode] = processedContent;
    tableHeader[currentCode] = headerString;
    tableType[currentCode] = 'A';
  }
} // end of createInternalTable

// void createInternalTable(
//     String tableCode,
//     String arrayString,
//     String headerString, {
//       String index = '', // Optional named parameter with a default value
//     }) {
//   // setting #TABLE$tableCode in ScreenTransaction
//   // setting tableContent[tableCode] & tableHeader[tableCode]
//   bool needToRebuild = false;
//   Map<String, dynamic>? table =
//       transactionStore.state.screenTx['#TABLE$tableCode'];
//   int checksum = int.parse(headerString.split(separator[6])[0]);
//   if (table == null) {
//     needToRebuild = true;
//   } else if (table[tableCode] != checksum) {
//     needToRebuild = true;
//   } // end if (table == null)
//   if (needToRebuild) {
//     devPrint('rebuild table $tableCode');
//     table = {tableCode: checksum};
//     dynamic tableArray = jsonDecode(arrayString);
//     for (int i = 0; i < tableArray.length; i++) {
//       // table[tableArray[i][0].toString()] = tableArray[i].sublist(1);
//       table[tableArray[i][0].toString()] = tableArray[i];
//     } // end for tableArray
//     transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
//       '#TABLE$tableCode': table,
//     })));
//     List<dynamic> temp = jsonDecode(arrayString);
//     List<dynamic> result = [];
//     for (int i = 0; i < temp.length; i++) {
//       List<dynamic> member = temp[i];
//       member.insert(0, i.toString()); // insert sequence in the front
//       result.add(member);
//     } // end for (int i=0; i<temp.length; i++)
//     // tableContent[tableCode] = jsonDecode(arrayString);
//     tableContent[tableCode] = result;
//     tableHeader[tableCode] = headerString;
//   } else {
//     devPrint('same checksum table = $checksum');
//   } // end if (needToRebuild)
// } // end of createInternalTable

// Future<void> createInternalTableDynamic(
//   String tableCode,
//   DocumentSnapshot documentSnapshot,
//   String headerString, {
//   String index = '',
// }) async {
//   // setting #TABLE$tableCode in ScreenTransaction
//   // setting tableContent[tableCode] & tableHeader[tableCode]
//   // in dynamic table checksum = String (from sha3)
//   List<dynamic> result = [];
//   Map<String, dynamic>? table =
//       transactionStore.state.screenTx['#TABLE$tableCode'];
//   String checksum = headerString.split(separator[6])[0];
//   String lastChecksum = (tableHeader[tableCode] ?? '').split(separator[6])[0];
//   bool needToRebuild = (table == null || lastChecksum != checksum);
//   if (needToRebuild) {
//     int numOfField = -1;
//     devPrint('rebuild table $tableCode');
//     QuerySnapshot querySnapshot;
//     try {
//       // final query = documentSnapshot.reference.collection('content');
//       querySnapshot =
//           await documentSnapshot.reference.collection('content').get();
//       table = {tableCode: checksum};
//       for (DocumentSnapshot documentSnapshot in querySnapshot.docs) {
//         dynamic rowData = documentSnapshot.data();
//         dynamic newRow = jsonDecode(rowData['c']);
//         table[rowData['t'].toString()] = newRow;
//         if (numOfField < 0) {
//           numOfField = newRow.length;
//         } // end if (numOfField < 0)
//         newRow.insert(0, rowData['t'].toString()); // add timestamp in the front
//         result.add(newRow);
//       } // end for (DocumentSnapshot documentSnapshot in querySnapshot.docs)
//       String sep = separator[6]; // white star
//       String header = '$checksum$sep$lastChecksum$sep';
//       String numberOfField = '00000$numOfField';
//       List<String> nameArray = tableCode.split('.');
//       if (nameArray.length < 2) {
//         nameArray.add('mobileTable');
//       }
//       header += '${numberOfField.substring(numberOfField.length - 5)}$sep';
//       header += '00200$sep{}$sep${nameArray[1]}$sep${nameArray[0]}';
//       String sep2 = separator[1]; // black diamond
//       for (int i = 1; i <= numOfField; i++) {
//         header += '$sep2$i${sep}text${sep}left';
//       } // end for (int i=1 ; i<= table[0].length; i++)
//       transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
//         '#TABLE$tableCode': table,
//       })));
//       tableContent[tableCode] = result;
//       // tableHeader[tableCode] = header;
//       tableHeader[tableCode] = headerString;
//     } catch (e) {
//       devPrint(e);
//     } // end try querySnapshot
//   } else {
//     devPrint('same checksum table = $checksum');
//   } // end if (needToRebuild)
// } // end of createInternalTableDynamic
Future<void> createInternalTableDynamic(
    String tableCode,
    DocumentSnapshot documentSnapshot,
    String headerString, {
      String index = '',
      String indexTableString = '', // New parameter for filtering
      String indexTableType = 'T', // 'T' for timestamp, 'K' for key in element #1
    }) async {
  // setting #TABLE$tableCode in ScreenTransaction
  // setting tableContent[tableCode] & tableHeader[tableCode]
  // in dynamic table checksum = String (from sha3)
  List<dynamic> result = [];
  Map<String, dynamic>? table =
  transactionStore.state.screenTx['#TABLE$tableCode'];
  String checksum = headerString.split(separator[6])[0];
  String lastChecksum = (tableHeader[tableCode] ?? '').split(separator[6])[0];
  // A filter query can change the result even if the checksum is the same.
  // We need a more robust way to check if a rebuild is needed.
  // For now, let's rebuild if a filter is present.
  bool needToRebuild = (table == null ||
      lastChecksum != checksum ||
      indexTableString.isNotEmpty);

  if (needToRebuild) {
    int numOfField = -1;
    devPrint('rebuild table $tableCode with filter: "$indexTableString"');

    // Start with the base query for the 'content' subcollection.
    Query query = documentSnapshot.reference.collection('content');
    QuerySnapshot querySnapshot;

    // If a filter string is provided, parse it and apply it to the query.
    // if (indexTableString.isNotEmpty) {
    //   final RegExp regExp =
    //       RegExp(r'([^=!<>\s]+)\s*(==|!=|<=|>=|<|>|=)\s*(.+)');
    //   final match = regExp.firstMatch(indexTableString.trim());
    //
    //   if (match != null) {
    //     try {
    //       final field = match.group(1)!.trim();
    //       final operator = match.group(2)!.trim();
    //       final valueStr = match.group(3)!.trim();
    //
    //       // Attempt to parse the value as a number, otherwise treat it as a string.
    //       // Firestore requires the data type in the query to match the type in the database.
    //       dynamic value = num.tryParse(valueStr) ?? valueStr;
    //
    //       switch (operator) {
    //         case '=':
    //           query = query.where(field, isEqualTo: value);
    //           break;
    //         case '==':
    //           query = query.where(field, isEqualTo: value);
    //           break;
    //         case '!=':
    //           query = query.where(field, isNotEqualTo: value);
    //           break;
    //         case '<':
    //           query = query.where(field, isLessThan: value);
    //           break;
    //         case '<=':
    //           query = query.where(field, isLessThanOrEqualTo: value);
    //           break;
    //         case '>':
    //           query = query.where(field, isGreaterThan: value);
    //           break;
    //         case '>=':
    //           query = query.where(field, isGreaterThanOrEqualTo: value);
    //           break;
    //       }
    //     } catch (e) {
    //       devPrint('Error parsing indexTableString "$indexTableString": $e');
    //     }
    //   } else {
    //     devPrint('Invalid indexTableString format: $indexTableString');
    //   }
    // }

    if (indexTableString.isNotEmpty) {
      // 1. Split the string by your specific delimiter '◆'
      List<String> conditions =
      indexTableString.split(separator[1]); // black diamond

      // Regex to capture: Group 1 (Field), Group 2 (Operator), Group 3 (Value)
      final RegExp regExp =
      RegExp(r'([^=!<>\s]+)\s*(==|!=|<=|>=|<|>|=)\s*(.+)');

      // 2. Iterate through every condition found
      for (String rawCondition in conditions) {
        String condition = rawCondition.trim();
        if (condition.isEmpty)
          continue; // Skip if there are accidental empty sections

        final match = regExp.firstMatch(condition);

        if (match != null) {
          try {
            final field = match.group(1)!.trim();
            final operator = match.group(2)!.trim();
            final valueStr = match.group(3)!.trim();

            // 3. Type Conversion Logic
            // Try to parse as a number (int or double).
            // If it fails (returns null), keep it as the original string.
            dynamic value = num.tryParse(valueStr) ?? valueStr;

            // Apply the filter to the query
            switch (operator) {
              case '=':
                query = query.where(field, isEqualTo: value);
                break;
              case '==':
                query = query.where(field, isEqualTo: value);
                break;
              case '!=':
                query = query.where(field, isNotEqualTo: value);
                break;
              case '<':
                query = query.where(field, isLessThan: value);
                break;
              case '<=':
                query = query.where(field, isLessThanOrEqualTo: value);
                break;
              case '>':
                query = query.where(field, isGreaterThan: value);
                break;
              case '>=':
                query = query.where(field, isGreaterThanOrEqualTo: value);
                break;
            }
          } catch (e) {
            devPrint('Error parsing condition "$condition": $e');
          }
        } else {
          devPrint('Invalid format for condition: $condition');
        }
      }
    } // end if (indexTableString.isNotEmpty)

    try {
      // Execute the potentially modified query.
      querySnapshot = await query.get();
      table = {tableCode: checksum};

      for (DocumentSnapshot documentSnapshot in querySnapshot.docs) {
        dynamic rowData = documentSnapshot.data();
        dynamic newRow = jsonDecode(rowData['c']);
        if (numOfField < 0) {
          numOfField = newRow.length;
        } // end if (numOfField < 0)
        if (indexTableType == 'K') {
          if (newRow.length > 0 &&
              newRow[0] != null &&
              newRow[0].toString().isNotEmpty) {
            table[newRow[0].toString()] = newRow;
            newRow.insert(0,
                rowData['t'].toString()); // add key in element #1 in the front
            result.add(newRow);
          }
        } else {
          // indexTableType == 'T'
          table[rowData['t'].toString()] = newRow;
          newRow.insert(
              0, rowData['t'].toString()); // add timestamp in the front
          result.add(newRow);
        }
      } // end for (DocumentSnapshot documentSnapshot in querySnapshot.docs)

      String sep = separator[6]; // white star
      String header = '$checksum$sep$lastChecksum$sep';
      String numberOfField = '00000$numOfField';
      List<String> nameArray = tableCode.split('.');
      if (nameArray.length < 2) {
        nameArray.add('mobileTable');
      }
      header += '${numberOfField.substring(numberOfField.length - 5)}$sep';
      header += '00200$sep{}$sep${nameArray[1]}$sep${nameArray[0]}';
      String sep2 = separator[1]; // black diamond
      for (int i = 1; i <= numOfField; i++) {
        header += '$sep2$i${sep}text${sep}left';
      } // end for (int i=1 ; i<= table[0].length; i++)
      transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
        '#TABLE$tableCode': table,
      })));
      tableContent[tableCode] = result;
      // tableHeader[tableCode] = header;
      tableHeader[tableCode] = headerString;
      tableType[tableCode] = 'D';
    } catch (e) {
      devPrint(e);
    } // end try querySnapshot
  } else {
    devPrint('same checksum table = $checksum and no filter provided.');
  } // end if (needToRebuild)
} // end of createInternalTableDynamic

List<dynamic>? findData(String tableCode, String recordKey) {
  dynamic table = transactionStore.state.screenTx['#TABLE$tableCode'];
  List<dynamic>? rec;
  if (table != null) {
    rec = table[recordKey];
    if (rec != null) {
      dynamic front = recordKey;
      rec = [front] + rec;
    }
  } //end if (table != null)
  return rec;
} // end of findData

Future subscribeToTable(
    String rawTableCode,
    int tableVid, {
      String indexString = '',
      String indexTableString = '',
      String indexTableType = 'T', // 'T' for timestamp, 'K' for key in element #1
    } //
    ) async {
  if (rawTableCode == '\$vtl/request/request_master') {
    int d = 1;
  }
  String tableCode = normalizeTableName(rawTableCode);
  try {
    dynamic tableListener =
    transactionStore.state.screenTx['#REFTABLE$tableCode'];
    bool needToListen = false;
    if (tableListener == null) {
      devPrint('Table $tableCode has not subscribed yet.');
      needToListen = true;
    } else {
      devPrint('table $tableCode has already subscribed');
    } // end if (tableListener == null)
    if (needToListen) {
      devPrint('subscribeTable => $tableCode with filter: "$indexTableString"');
      dynamic docRef = firestoreDb
          .collection('$mobileTable/$tableVid/$mobileTableCollection')
      // .collection(
      //     '$mobileTable/${appCodeController.applicationTableVid}/$mobileTableCollection')
          .doc(tableCode); // search in MobileTable\
      bool docExists = (await docRef.get()).exists;
      if (!docExists) {
        docRef = firestoreDb
            .collection(tableDirectory)
            .doc(tableCode); // search in TableDirectory
        docExists = (await docRef.get()).exists;
      } // end if (!docSnapshot.exists)
      if (docExists) {
        try {
          final dynamic tableListener = docRef.snapshots().listen(
                (event) async {
              if (event.data() == null) {
                transactionStore
                    .dispatch(UpdateScreenTxAction(ScreenTransaction({
                  '#TABLE$tableCode': null,
                })));
                devPrint('subscribeTable => no record found in $tableCode.');
                tableContent[tableCode] = [];
                tableHeader[tableCode] = '';
                tableType[tableCode] = '';
              } else {
                if (event.data()['tt'] == 'D') {
                  // Pass the filter string down to the handler function
                  await createInternalTableDynamic(
                      tableCode, event, event.data()['hd'],
                      index: indexString,
                      indexTableString: indexTableString,
                      indexTableType: indexTableType);
                } else {
                  // Note: Filtering is not supported for 'A' type tables here
                  // as all content is in a single document field.
                  if (indexTableString.isNotEmpty) {
                    devPrint(
                        'Warning: Filtering is only supported for dynamic (type D) tables. Filter "$indexTableString" will be ignored for table $tableCode.');
                  }
                  createInternalTable(
                      tableCode, event.data()['tc'], event.data()['hd'],
                      index: indexString);
                  // tableContent[tableCode] = jsonDecode(event.data()['tc'])
                  // tableHeader[tableCode] = event.data()['hd'];
                  devPrint("subscribeTable => header: ${event.data()['hd']}");
                  devPrint(
                      'subscribeTable => $tableCode loaded to #TABLE$tableCode');
                  devPrint(
                      'subscribeTable => ${(tableContent[tableCode] ?? []).length} record found in tableContent[$tableCode].');
                  debugPrint('data 2 = ${tableContent[tableCode][1]}');
                } //end if (event.data()['tt'] == 'D')
              } // end if (event.data() == null)
              tableSourceUpdated[tableCode] = true;
              // debugPrint(
              //     'subscribeTable => $tableCode updated, length = ${tableContent[tableCode]
              //         .length}');
            },
            onError: (error) => devPrint("Listen failed: $error"),
          ); // end of listener
          transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
            '#REFTABLE$tableCode': tableListener,
          })));
        } catch (e1) {
          //print('error listening to $tableCode $e1');
        } // end try docRef
      } else {
        devPrint('No table $tableCode');
      } // end if (docRef != null)
    } // end if (needToListen)
  } catch (e) {
    devPrint('Error table $tableCode $e');
  } // end try subscribeToTable
} // end of subscribeToTable

Future unsubscribeTable(String tableCode) async {
  try {
    var handle = transactionStore.state.screenTx['#REFTABLE$tableCode'];
    if (handle != null) {
      handle.close();
      transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
        '#REFTABLE$tableCode': handle,
      })));
    } // end if (handle != null)
  } catch (e) {
    // do nothing
  }
} // end of unsubscribeTable

Future loadHistory(bool clearHistoryImageMap, String parent) async {
  // loads to imageMap, then _HISTORY from secure storage, or from firestore (if secure storage is empty)
  // await historyClear(); // delete this for production
  const functionName = 'historyLoadFromSecureStorage';
  devPrint(
      '!!!! --- run load history from $parent clearHistory = $clearHistoryImageMap}');
  bool guestSsid = false;
  // load imageMap
  if (imageMap.isEmpty) {
    String? imageMapStr;
    try {
      imageMapStr = await storage.read(key: imageMapSecureName);
    } catch (e) {
      devPrint('Cannot read _IMAGEMAP from secure storage $e');
      imageMapStr = null;
    } // end try (e)
    if (imageMapStr == null || imageMapStr == 'null') {
      devPrint('imageMapStr is null, load from firestore');
      String? ssid;
      try {
        ssid =
            (await waitUntilNotNullScreenTx(functionName, '#INTERFACE_KEY', 20))
                .toString();
      } catch (eSsid) {
        devPrint('Cannot read ssid from #INTERFACE_KEY $eSsid');
        ssid = null;
      }
      if (ssid != null && ssid != loginSsid) {
        var docRef = firestoreDb
            .collection(proxyCollectionName)
            .doc(ssid ?? 'ErrorInLoadHistory');
        try {
          dynamic proxyData = (await docRef.get()).data();
          if (proxyData['i'] == null || proxyData['i'] == 'null') {
            imageMapStr = '{}';
          } else {
            imageMapStr = proxyData['i'];
          } // end if (proxyData != null)
        } catch (errorFirestore) {
          devPrint('Cannot read imagemap from firestore $errorFirestore');
          imageMapStr = '{}';
        } // end try (eFirestore)
        storage.write(key: imageMapSecureName, value: imageMapStr);
        //write history to proxy firestore here
        await docRef.update({'i': imageMapStr});
      } else {
        guestSsid = true;
      } // end if (ssid != null && ssid != loginSsid)
    } // end if (historyStr == null || historyStr == 'null')
    if (!guestSsid) {
      if (clearHistoryImageMap) {
        // clear imageMap every app startup
        devPrint('Clearing imageMap because of clearHistoryImageMap = true');
        imageMapStr = '{}';
        await imageMapInit(jsonDecode(imageMapStr ?? '{}'));
        storage.write(key: imageMapSecureName, value: imageMapStr);
        if (internetConnected()) {
          try {
            String ssid = (await waitUntilNotNullScreenTx(
                functionName, '#INTERFACE_KEY', 20))
                .toString();
            var docRef = firestoreDb
                .collection(proxyCollectionName)
                .doc(ssid ?? 'ErrorInLoadHistory');
            docRef.update({'i': imageMapStr});
          } catch (fErr) {
            // error in firebase, do nothing
          } // end try
        } // end if  (internetConnected())
      } else {
        await imageMapInit(jsonDecode(imageMapStr ?? '{}'));
      } // end if (clearHistoryImageMap)
      scheduleSendImagesInImageMap();
    } // end if (!guestSsid)
  } // if (tableContent[imageMapName] == null || tableContent[imageMapName].isEmpty)

  // load _HISTORY
  if (tableContent[historyName] == null || tableContent[historyName].isEmpty) {
    String? historyStr;
    try {
      historyStr = await storage.read(key: historyName);
    } catch (e) {
      devPrint('Cannot read history from secure storage $e');
      historyStr = null;
    } // end try (e)
    if (historyStr == null || historyStr == 'null') {
      devPrint('historyStr is null, load from firestore');
      String? ssid;
      try {
        ssid =
            (await waitUntilNotNullScreenTx(functionName, '#INTERFACE_KEY', 20))
                .toString();
      } catch (eSsid) {
        devPrint('Cannot read ssid from #INTERFACE_KEY $eSsid');
        ssid = null;
      }
      if (ssid != null && ssid != loginSsid) {
        var docRef = firestoreDb
            .collection(proxyCollectionName)
            .doc(ssid ?? 'ErrorInLoadHistory');
        try {
          dynamic proxyData = (await docRef.get()).data();
          if (proxyData['h'] == null || proxyData['h'] == 'null') {
            historyStr = '[]';
          } else {
            historyStr = proxyData['h'];
          } // end if (proxyData != null)
        } catch (errorFirestore) {
          devPrint('Cannot read history from firestore $errorFirestore');
          historyStr = '[]';
        } // end try (eFirestore)
        storage.write(key: historyName, value: historyStr);
        //write history to proxy firestore here
        await docRef.update({'h': historyStr});
      } else {
        guestSsid = true;
      } // end if (ssid != null && ssid != loginSsid)
    } else {
      tableContent[historyName] = jsonDecode(historyStr);
    } // end if (historyStr == null || historyStr == 'null')
    if (!guestSsid) {
      if (clearHistoryImageMap) {
        // clear history every app startup
        devPrint('Clearing history because of clearHistoryImageMap = true');
        historyStr = '[]';
        storage.write(key: historyName, value: historyStr);
        await historyLock(functionName);
        tableContent[historyName] = jsonDecode(historyStr);
        historyFix();
        historyUnLock(functionName);
        if (internetConnected()) {
          try {
            String ssid = (await waitUntilNotNullScreenTx(
                functionName, '#INTERFACE_KEY', 20))
                .toString();
            var docRef = firestoreDb
                .collection(proxyCollectionName)
                .doc(ssid ?? 'ErrorInLoadHistory');
            docRef.update({'h': historyStr});
          } catch (fErr) {
            // error in firebase, do nothing
          } // end try
        } // end if  (internetConnected())
        updateHistoryImage(); // replace image in history async
      } // end if (clearHistoryImageMap)
      await sendImagesInImageMap();
      historySync('LoadHistory', false);
    }
  } // if (tableContent[historyName] == null || tableContent[historyName].isEmpty)
  //updateHistoryImage(); // replace image in history async
  devPrint(
      '!!!! --- ending of load history from $parent clearHistory = $clearHistoryImageMap}');
} // end of loadHistory

Future historyAdd(List<dynamic> inputEvent) async {
  List<dynamic> newEvent = List.from(inputEvent);
  String dateTimeString = DateFormat(dateTimeFormat)
      .format(DateTime.fromMillisecondsSinceEpoch(newEvent[0]));
  if (newEvent[2] is List) {
    try {
      newEvent[2] = (newEvent[2].length > 1)
          ? newEvent[2][1]
          : newEvent[2][0]; // to handle history blocked by a list
    } catch (eEvent) {
      newEvent[2] = emptyString;
    }
  } // end if (newEvent[2] is List)
  // Map<String,String> eventMap = {};
  // if (newEvent[5].isNotEmpty) {
  //   eventMap['addToTable'] = newEvent[5];
  // } // end if (newEvent[5].isNotEmpty)
  List<dynamic> cnt = newEvent.sublist(0, 5) +
      [dateTimeString, "", "", "", 0, 0, 0, {}, [], newEvent[5]];
  await checkTable('historyAdd', historyName, 10);
  await historyLock('historyAdd');
  try {
    tableContent[historyName].insert(0, cnt);
    tableContent[historyName].sort((a, b) => int.parse(b[0].toString())
        .compareTo(int.parse(a[0].toString()))); // sort descending by timestamp
  } catch (e) {
    devPrint('error in tableContent[$historyName]: $e');
  }
  historyUnLock('historyAdd');
  await saveHistory();
} // end of historyAdd

Future historySent(int historyId) async {
  await historyCheckMark(historyId, 6, 9);
} // end of historySent

Future historyCloudReceived(int historyId) async {
  await historyCheckMark(historyId, 7, 10);
} // end of historyCloudReceived

Future historyProcessed(int historyId) async {
  await historyCheckMark(historyId, 8, 11);
} // end of historyProcessed

Future historyClear() async {
  await imageMapClear();
  await historyLock('historyClear');
  tableContent[historyName].clear();
  historyUnLock('historyClear');
  await saveHistory();
} // end of historyClear

Future historyResetAll() async {
  // uncheck all history status
  await checkTable('historyResetAll', historyName, 10);
  await historyLock('historyResetAll');
  //tableContent[historyName].removeAt(4);
  //tableContent[historyName].removeAt(1);
  for (int i = 0; i < tableContent[historyName].length; i++) {
    dynamic rec = tableContent[historyName][i];
    rec[0]++;
    rec[6] = "";
    rec[7] = "";
    rec[8] = "";
    rec[9] = 0;
    rec[10] = 0;
    rec[11] = 0;
  }
  historyUnLock('historyResetAll');
  await saveHistory();
} // end of historyResetAll

Future historyTrim({int day = 7}) async {
  // trim history to keep only last several days. Default 7 days
  // this function will delete all record that was processed and aged more than day
  int now = DateTime.now().millisecondsSinceEpoch;
  int cutoff = now - day * 86400000; // 24 * 60 * 60 * 1000;
  bool end = false;
  bool deleted = false;
  await checkTable('historyTrim', historyName, 10);
  await historyLock('historyTrim');
  for (int i = tableContent[historyName].length - 1; !end && i >= 0; i--) {
    if (tableContent[historyName][i][0] > cutoff &&
        tableContent[historyName][i][11] > 0 &&
        tableContent[historyName][i][11] < cutoff) {
      tableContent[historyName].removeAt(i);
      deleted = true;
    } // end if (tableContent[historyName][i][11] < cutoff)
    if (tableContent[historyName][i][0] <= cutoff) {
      end = true;
    } // end if (tableContent[historyName][i][0] <= cutoff)
  } // end for (int i = 0; i < tableContent[historyName].length)
  historyUnLock('historyTrim');
  if (deleted) {
    saveHistory();
  } // end if (deleted)
} // end of historyTrim

Future<void> checkTable(String from, String tableName, int waitLoop) async {
  /*
    Check if tableContent[tableName] is null, if yes, wait for it to be available
    After waitLoop, if tableContent[tableName] is still null, create it as empty list
   */
  if (tableContent[tableName] == null) {
    int waitCounter = 0;
    Completer<void> completer = Completer<void>();

    Timer.periodic(const Duration(milliseconds: 250), (timer) async {
      if (tableContent[tableName] != null) {
        timer.cancel(); // Stop polling once data is available
        completer.complete();
      } else {
        waitCounter++;
        devPrint('>> $from waiting for tableContent[$tableName] $waitCounter');
        if (waitCounter > waitLoop) {
          timer.cancel();
          await historyLock('historyAdd blank');
          tableContent[tableName] = [];
          historyUnLock('historyAdd blank');
          completer.complete();
        }
      }
    });
    await completer.future;
  }
} // end of checkTable

Future saveHistory() async {
  // save to secure storage, update transactionStore['#TABLE_HISTORY'],
  // and firestore proxy['h']
  const functionName = 'saveHistory';
  await checkTable(functionName, historyName, 10);
  await updateHistoryImage();
  imageMapSecureStore(); // save imageMap to secure storage

  // save history to secure storage
  await historyLock('$functionName 1');
  historyFix();
  String historyStr = jsonEncode(tableContent[historyName]);
  historyUnLock('$functionName 1');
  // update secure storage
  try {
    storage.write(key: historyName, value: historyStr);
  } catch (e) {
    devPrint('Cannot save history to secure storage $e');
  } // end try (e)
  // update transactionStore['#TABLE_HISTORY']
  Map<String, dynamic>? table = {historyName: sha3_256(historyStr)};
  await historyLock(functionName);
  for (int i = 0; i < tableContent[historyName].length; i++) {
    table[tableContent[historyName][i][0].toString()] =
    tableContent[historyName][i];
  } // end for tableContent[historyName]
  historyUnLock(functionName);
  transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
    '#TABLE$historyName': table,
  })));
  if (internetConnected()) {
    String ssid =
    (await waitUntilNotNullScreenTx(functionName, '#INTERFACE_KEY', 20))
        .toString();
    try {
      FirebaseFirestore.instance.settings =
      const Settings(persistenceEnabled: true);
      dynamic docRef = firestoreDb.collection(proxyCollectionName).doc(ssid);
      docRef.update({
        'h': historyStr,
        'i': jsonEncode(imageMap)
      }); // saving to proxy field 'h' in firestore
    } catch (e) {
      devPrint('Cannot save history to firestore $e');
    } // end try (e)
  } // end if (!internetConnected())
  //historyUnLock('saveHistory');
} // end of saveHistory

Future archiveHistory() async {
  // archive current history and imageMap to firestore proxy['h2'], proxy[i2
  // this is for debugging purpose
  const myFunctionName = 'archiveHistory';
  await checkTable(myFunctionName, historyName, 10);
  await historyLock('$functionName 1');
  String historyStr = jsonEncode(tableContent[historyName]);
  historyUnLock('$functionName 1');
  if (internetConnected()) {
    String ssid =
    (await waitUntilNotNullScreenTx(myFunctionName, '#INTERFACE_KEY', 20))
        .toString();
    try {
      FirebaseFirestore.instance.settings =
      const Settings(persistenceEnabled: true);
      dynamic docRef = firestoreDb.collection(proxyCollectionName).doc(ssid);
      docRef.update({
        'h2': historyStr,
        'i2': jsonEncode(imageMap)
      }); // saving to proxy field 'h' in firestore
    } catch (e) {
      devPrint('!!! Cannot archive history to firestore $e');
    } // end try (e)
  } // end if (!internetConnected())
} // end of archiveHistory

void historyFix() {
  // got the error that caused history to ruin, this function is not needed.
  // fix history table, convert List to String. List in hist[i][2] is not a bug
  // todo fix tablecontent[historyName][i][2] 'is a List' bug
  // try {
  //   final hist = tableContent[historyName];
  //   for (int i = 0; i < hist.length; i++) {
  //     if (hist[i][2] is List) {
  //       hist[i][2] = (hist[i][2].length < 1) ? hist[i][2][0] : hist[i][2][1];
  //     }
  //   }
  // } catch (e) {
  //   devPrint('!!! error in historyFix $e');
  // }
} // end of historyFix

Future historyCheckMark(int historyId, int checkIndex, int tsIndex) async {
  // set tableContent[historyName] [i][] = checkmark with [i][0] = historyId
  await checkTable('historyCheckMark', historyName, 10);
  await historyLock(
      'historyCheckMark bSearch index $checkIndex for historyId $historyId');
  int index = binarySearch2DDesc(tableContent[historyName], 0, historyId);
  historyUnLock(
      'historyCheckMark bSearch index $checkIndex for historyId $historyId');
  if (index >= 0 && tableContent[historyName][index][tsIndex] == 0) {
    await historyLock(
        'historyCheckMark check index $checkIndex for historyId $historyId');
    tableContent[historyName][index][checkIndex] = checkMark;
    tableContent[historyName][index][tsIndex] =
        DateTime.now().millisecondsSinceEpoch;
    historyUnLock(
        'historyCheckMark check index $checkIndex for historyId $historyId');
    await saveHistory();
  } // end if (index >= 0)
} // end of historySent

void historyUnLock(String from) {
  historyTableIsLocked = false;
  // debugPrint('*** historyUnLock from $from');
}

Future historyLock(String from) async {
  Duration backoffDuration =
  const Duration(milliseconds: 100); // Initial backoff time
  while (historyTableIsLocked) {
    // debugPrint('*** waiting for history lock from $from');
    try {
      await Future.delayed(backoffDuration);
      backoffDuration = Duration(
          milliseconds:
          backoffDuration.inMilliseconds * 2); // Double backoff time
    } on Exception catch (e) {
      // Handle potential exceptions during unlock or write
      devPrint("!!! Error waiting for historyLock from $from: $e");
      backoffDuration = Duration(
          milliseconds:
          backoffDuration.inMilliseconds * 2); // Increase backoff on errors
    } // end try Future.delayed
  } // end while (historyTableIsLocked)
  historyTableIsLocked = true;
  // debugPrint('*** historyLock from $from');
} // end of waitForHistoryLock

Future historySyncLockOld(String from) async {
  Duration backoffDuration =
  const Duration(milliseconds: 100); // Initial backoff time
  while (historySyncIsLocked) {
    // debugPrint('***>>> waiting for historySync lock from $from');
    try {
      await Future.delayed(backoffDuration);
      backoffDuration = Duration(
          milliseconds:
          backoffDuration.inMilliseconds * 2); // Double backoff time
    } on Exception catch (e) {
      // Handle potential exceptions during unlock or write
      devPrint("!!! Error waiting for historyLock from $from: $e");
      backoffDuration = Duration(
          milliseconds:
          backoffDuration.inMilliseconds * 2); // Increase backoff on errors
    } // end try Future.delayed
  } // end while (historyTableIsLocked)
  historySyncIsLocked = true;
  // debugPrint('***>>> historySyncLock from $from');
} // end of historySyncLock

void historySyncUnLockOld(String from) {
  historySyncIsLocked = false;
  // debugPrint('***>>> historySyncUnLock from $from');
} // end of historySyncUnLock

Future historySync(String source, bool forceSend) async {
  // sent unsent history to event
  // trim history at the end
  devPrint('!!!-- run historySync from $source forceSend = $forceSend');
  final functionName = 'historySync ${forceSend ? '' : 'not '} forceSend';
  await checkTable(functionName, historyName, 10);
  await updateHistoryImage();
  dynamic state = transactionStore.state.screenTx;
  // if (!(await internetConnectedCheck())) {
  if (!internetConnected()) {
    debugPrint('historySync skipped because no internet');
  } else {
    String? ssid =
    await waitUntilNotNullScreenTx(functionName, '#INTERFACE_KEY', 20);
    if (ssid != loginSsid) {
      if (tableContent[historyName] == null) {
        debugPrint(
            'historySync skipped because tableContent[historyName] is null');
      } else {
        debugPrint('execute $functionName');
        if (historySyncLock.queueLock(functionName)) {
          try {
            FirebaseFirestore.instance.settings =
            const Settings(persistenceEnabled: false);
            // SubmitBloc submitBloc = state['#SUBMIT_BLOC'];
            bool moreHistory = true;
            bool continueSendingHistory = true;
            bool needToCallProcessEvent = false;
            while (moreHistory) {
              bool unsentHistoryFound = false;
              int historyIndex = -1;
              await historyLock('$functionName 1');
              try {
                tableContent[historyName].sort((a, b) =>
                    int.parse(b[0].toString()).compareTo(int.parse(
                        a[0].toString()))); // sort descending by timestamp
                List<Future<List<dynamic>>> futureList = [];
                for (int i = tableContent[historyName].length - 1;
                i >= 0;
                i--) {
                  // looping in all history records to identify aum__ image
                  if (tableContent[historyName][i][9] <= 0) {
                    if (tableContent[historyName][i][2].contains('aum__')) {
                      futureList.add(sendHistoryImagesToCloud(
                          i, tableContent[historyName][i][2]));
                    }
                  } // if (tableContent[historyName][i][9] <= 0)
                } // end for (int i = 0; i < tableContent[historyName].length)
                if (futureList.isNotEmpty) {
                  // if there is aum__ image to be sent
                  List<dynamic> historyRecords = await Future.wait(
                      futureList); // try to replace all aum__ with url

                  for (int i = 0; i < historyRecords.length; i++) {
                    tableContent[historyName][historyRecords[i][0]][2] =
                    historyRecords[i][1];
                    // replace aum__ with url (if generated successfully)
                  } // end for (int i = 0; i < historyRecords.length)
                } // end if (futureList.isNotEmpty)
                // aum__ should be processed by now
                for (int i = tableContent[historyName].length - 1;
                !unsentHistoryFound && i >= 0;
                i--) {
                  if (tableContent[historyName][i][9] <= 0) {
                    unsentHistoryFound = true;
                    historyIndex = i;
                    if ((tableContent[historyName][i][2].contains('aum__'))) {
                      // continueSendingHistory = false;
                      continueSendingHistory = forceSend;
                    }
                  } // end if (tableContent[historyName][i][9] == 0)
                } // end for (int i = 0; i < tableContent[historyName].length)
              } catch (e1) {
                // do nothing
                int ddd = 1;
              }
              historyUnLock('$functionName 1');
              if (unsentHistoryFound && continueSendingHistory) {
                List<dynamic> eventHistory =
                tableContent[historyName][historyIndex];
                debugPrint(
                    'historySync processing historyId ${eventHistory[0]}');
                String eventTemp = await replaceLocalImageToUrl(
                    eventHistory[2]); // send image to cloud
                if (!forceSend && eventTemp.contains('aum__')) {
                  devPrint('*** image not sent, skip historySync');
                  moreHistory = false;
                } else {
                  await historyLock('$functionName 2');
                  List<String> contentArray = eventTemp.split(separator[0]);
                  List<String> locArray = contentArray[0].split(separator[1]);
                  if (locArray[4] != '' &&
                      double.parse(locArray[4]) != invalidLocation &&
                      locArray[5] != '' &&
                      double.parse(locArray[5]) != invalidLocation) {
                    List<Placemark> thePlace = [];
                    try {
                      thePlace = await placemarkFromCoordinates(
                          double.parse(locArray[4]), double.parse(locArray[5]));
                      locArray[7] = locArray[7] == '88'
                          ? thePlace[0].isoCountryCode ?? emptyString
                          : locArray[7];
                      locArray[8] = locArray[8] == emptyString
                          ? thePlace[0].postalCode ?? emptyString
                          : locArray[8];
                      locArray[9] = locArray[9] == emptyString
                          ? thePlace[0].administrativeArea ?? emptyString
                          : locArray[9];
                      locArray[10] = locArray[10] == emptyString
                          ? (thePlace[0].subAdministrativeArea ?? emptyString)
                          : locArray[10];
                      locArray[11] = locArray[11] == emptyString
                          ? (thePlace[0].locality ?? emptyString)
                          : locArray[11];
                      locArray[12] = locArray[12] == emptyString
                          ? (thePlace[0].subLocality ?? emptyString)
                          : locArray[12];
                      locArray[13] = locArray[13] == emptyString
                          ? (thePlace[0].thoroughfare ?? emptyString)
                          : locArray[13];
                      locArray[14] = locArray[14] == emptyString
                          ? (thePlace[0].subThoroughfare ?? emptyString)
                          : locArray[14];
                      contentArray[0] = locArray.join(separator[1]);
                      eventTemp = contentArray.join(separator[0]);
                    } catch (ePlace) {
                      devPrint('error in placemarkFromCoordinates $ePlace');
                    }
                  } // end if (locArray[4] == '')
                  eventHistory[2] = eventTemp;
                  historyUnLock('$functionName 2');
                  dynamic id =
                      '${state['#VID']}${(Random.secure().nextDouble() * 1000).toString()}';
                  final firestoreEventCollection2 =
                      '$proxyCollectionName/$ssid/$eventCollectionName';
                  final docName =
                  getEventDocName('${defaultVid()}${eventHistory[0]}');
                  final docReference = FirebaseFirestore.instance
                      .collection(firestoreEventCollection2)
                      .doc(docName);
                  Map<String, dynamic> dataSent = {
                    "t": eventHistory[0],
                    "p": eventHistory[1],
                    "c": eventHistory[2],
                    "s": 10,
                  };
                  if (internetConnected()) {
                    //add writeToTable here with Future.wait
                    devPrint(
                        '*** internet connected, send history and writeToTable.');
                    if (eventHistory.length > 14) {
                      final String rawTb =
                      (eventHistory[14] ?? '').toString();
                      final List<String> tbParts = rawTb.split(separator[0]);
                      final String addStr = tbParts[0];
                      final String updateStr =
                      tbParts.length > 1 ? tbParts[1] : '';
                      final String deleteStr =
                      tbParts.length > 2 ? tbParts[2] : '';
                      final String eventRowString = jsonEncode([
                        eventHistory[0],
                        eventHistory[1],
                        eventHistory[2]
                      ]);
                      if (addStr.isNotEmpty) {
                        writeToTable(addStr, eventRowString);
                      }
                      if (updateStr.isNotEmpty) {
                        updateTableRow(updateStr, eventRowString);
                      }
                      if (deleteStr.isNotEmpty) {
                        deleteFromTable(deleteStr, eventRowString);
                      }
                    } else {
                      devPrint(
                          'writeToTable skipped, no table definition in history.');
                    }
                    await docReference.set(dataSent).then((value) async {
                      debugPrint(
                          'historySync doc $docName sent dataSent $dataSent');
                      await historySent(eventHistory[0]);
                      docReference.snapshots().listen((event) async {
                        await historyProcessed(eventHistory[0]);
                        if (event.exists) {
                          // Timer timer = Timer(const Duration(seconds: 1), () async {
                          // dynamic qParams = {"ssid": ssid};
                          // devPrint(
                          //     '=== call $eventFunctionName with param=$qParams');
                          // dynamic uri = Uri.https(functionFront, eventFunctionName);
                          // await callHttpPost(uri, qParams);
                          // });
                        } // end if (event.exists)
                      }); // end of listen
                    }); // end of docReference.then
                    await historyCloudReceived(eventHistory[0]);
                    needToCallProcessEvent = true;
                  } else {
                    devPrint('*** internet not connected.');
                    moreHistory = false; // no internet, get out
                  } // end if (internetConnected.value)
                } // end if (unsentHistoryFound && continueSendingHistory)
              } else {
                moreHistory = false;
              } // end if (!unsentHistoryFound)
            } // end while (true)
            historyFix();
            historyUnLock('$functionName 3');
            if (needToCallProcessEvent) {
              historyTrim(day: 7).then((_) {
                saveHistory();
              });
              // call process event
              callEventFunction();
            } else {
              debugPrint('no history sent'); // end if (needToCallProcessEvent)
            }
          } catch (e) {
            // do nothing
          } // end try (e)
          historySyncLock.queueUnlock(functionName);
        } // end if (historySyncLock.lock1(functionName))
        // await historySyncLockOld('$functionName from $source');
      } // end if (tableContent[historyName] == null)
      // historySyncUnLockOld('$functionName from $source');
    } else {
      devPrint('Guest proxy detected, skip historySync');
    } // end if (ssid != null && ssid != loginSsid)
  }
} // end of syncHistory

Future updateHistoryImage() async {
  // update all aum in history according to imageMap
  await imageMapTrim(imageMapMaxDayAge); // trim to last 31 days
  // await sendImagesInImageMap();
  if (imageMap.isNotEmpty && tableContent[historyName] != null) {
    await historyLock('updateHistoryImage');
    historyFix();
    String pattern = r"aum__(.*?)__mua";
    RegExp regex = RegExp(pattern);
    for (int i = 0; i < tableContent[historyName].length; i++) {
      Iterable<Match> matches =
      regex.allMatches(tableContent[historyName][i][2]);
      for (Match match in matches) {
        // looping for all aum in the history entry
        dynamic imageMapEntry = imageMapGet(match.group(1) ?? emptyString);
        bool imageReady = (imageMapEntry != null);
        if (imageReady) {
          imageReady = isValidImageUrl(imageMapEntry[1]) ||
              imageMapEntry[3] >= maxImageUploadRetry;
        } else {
          // insert aum__ in imageMap
          if (match.group(1) != null) {
            await imageMapUpdateUrl(match.group(1)!, emptyString);
          }
        } // end if (imageReady)
        if (imageReady) {
          tableContent[historyName][i][2] = tableContent[historyName][i][2]
              .replaceAll(match.group(0), imageMapEntry[1]); // replace the aum
          int d = 1;
        } // end if (imageMap != null)
      } // end for (RegExpMatch match in matches)
    } // end for (int i=0; i<tableContent[historyName].length; i++)
    historyFix();
    historyUnLock('updateHistoryImage');
  } // end if (tableContent[imageMapName].length > 0)
} // end of updateHistoryImage

List<dynamic>? imageMapGet(String localPath) {
  // get imageMap entry for localPath
  return imageMap[localPath];
} // end of getImageMapEntry

Future<void> imageMapUpdateUrl(String localPath, String url) async {
  // add entry to imageMap
  String functionName = 'imageMapUpdateUrl';
  await imageLock.lock(functionName);
  try {
    var imageMapEntry = imageMap[localPath];
    if (imageMapEntry == null) {
      imageMap[localPath] = [
        DateTime.now().millisecondsSinceEpoch,
        url,
        false,
        0,
        0
      ];
    } else {
      int retry = imageMapEntry[3] + 1;
      if (isValidImageUrl(url) || (retry > maxImageUploadRetry)) {
        imageMapEntry[1] = url;
        imageMapEntry[4] = 0;
        imageMapEntry[3] =
        retry > maxImageUploadRetry ? maxImageUploadRetry : retry;
      } else {
        // not valid and retry < maxImageUploadRetry, increase retry count
        imageMapEntry[4] = 0;
        imageMapEntry[3]++;
      } // end if (isValidImageUrl(url) || (retry == maxImageUploadRetry))
    } // end if (imageMap[localPath] == null)
  } catch (e) {
    devPrint('!!! error in imageMapUpdateUrl $e');
  }
  imageLock.unlock(functionName);
  imageMapSecureStore();
  return;
} // end of imageMapUpdateUrl

Future<void> imageMapChangeStatus(String localPath, bool status) async {
  // add entry to imageMap
  const String functionName = 'imageMapChangeStatus';
  await imageLock.lock(functionName);
  var imageMapEntry = imageMap[localPath];
  imageMapEntry[2] = status;
  imageMapEntry[4] = 0;
  imageLock.unlock(functionName);
} // end of addEntryToImageMap

Future<void> imageMapDelete(String localPath) async {
  // delete entry from imageMap
  const String functionName = 'imageMapDelete';
  await imageLock.lock(functionName);
  imageMap.remove(localPath);
  imageLock.unlock(functionName);
} // end of deleteEntryFromImageMap

Future<void> imageMapTrim(int days) async {
  // delete entries in tableContent[imageMapName] is older than 31 days
  final int trimInterval = days.abs() * 86400000; // = 24 * 60 * 60000;
  final int currentTime = DateTime.now().millisecondsSinceEpoch;
  if (imageMap.isNotEmpty) {
    const String functionName = 'imageMapDelete';
    await imageLock.lock(functionName);
    imageMap.removeWhere((key, value) {
      if (value.isNotEmpty && value[0] is int) {
        int timestamp = value[0];
        // ToDo check if the url is valid
        bool validUrl = isValidImageUrl(value[1].toString());
        bool needToDelete =
            validUrl && (currentTime - timestamp) > trimInterval;
        if (validUrl) {
          File file = File(value[1].toString());
          if (file.existsSync()) {
            file.delete();
          }
        } // end if (validUrl)
        return needToDelete;
      }
      return false;
    });
    imageLock.unlock(functionName);
  } // end if (tableContent[imageMapName].length > 0)
} // end of deleteOldEntriesInImageMap

Future<void> imageMapClear() async {
  const String functionName = 'imageMapClear';
  await imageLock.lock(functionName);
  imageMap.clear();
  imageLock.unlock(functionName);
} // end of clearImageMap

Future<void> imageMapInit(dynamic content) async {
  const String functionName = 'imageMapInit';
  await imageLock.lock(functionName);
  imageMap = content;
  imageLock.unlock(functionName);
} // end of initImageMap}

Future imageMapSecureStore() async {
  // store imageMap to local secure storage
  const String functionName = 'imageMapSecureStorage';
  await imageLock.lock(functionName);
  String imageMapStr = jsonEncode(imageMap);
  try {
    storage.write(key: imageMapSecureName, value: imageMapStr);
  } catch (e) {
    devPrint('Cannot save imageMap to secure storage $e');
  } // end try (e)
  imageLock.unlock(functionName);
} // end of imageMapSecureStore

Future sendImagesInImageMap() async {
  // send all images in tableContent[imageMapName] to firebase storage
  // fill in the url [1] in tableContent[imageMapName]
  const String functionName = 'sendImagesInImageMap';
  if (imageSendLock.queueLock(functionName)) {
    try {
      final ageIntervalMillis = imageMapMaxDayAge * 86400000;
      devPrint('run $functionName');
      if (internetConnected()) {
        List<Future<dynamic>> sendArray = [];
        int nowMillis = DateTime.now().millisecondsSinceEpoch;
        final List<String> keysArray = imageMap.keys.toList();
        for (String key in keysArray) {
          //String key = entry.key;
          List<dynamic> value = imageMap[key];
          if (value.length <= 4 || (nowMillis - value[4]) > ageIntervalMillis) {
            await imageLock.lock(functionName);
            if (value.length <= 4) {
              value.add(nowMillis);
            } else {
              value[4] = nowMillis;
            }
            imageMap[key][4] = nowMillis; // lock the imageMap record
            // DateTime.now().millisecondsSinceEpoch; // lock the imageMap record
            int retry = value[3];
            imageLock.unlock(functionName);
            if (value[1].length < 5 ||
                (value[1].contains('aum__') && retry < maxImageUploadRetry)) {
              // if url is empty
              sendArray.add(uploadUpdateImage(key, value[1], retry));
              //String url = await uploadImageToCloud(localPath);
              // if (url.contains('aume__') && retry == maxImageUploadRetry - 1) {
              //   devPrint('Error upload in sendImagesInImageMap:$url');
              //   imageMapUpdateUrl(localPath, value[1]);
              // } else {
              //   imageMapUpdateUrl(localPath, url);
              // }
              // needToHistorySync = true;
            } // end if (value[1].length < 5)
            // imageMap[key][4] = 0; // unlock the imageMap record
          } // end if (value.length <= 4)
        } // end for (String key in keysArray)
        if (sendArray.isNotEmpty) {
          Future.wait(sendArray);
        }
      } // end if (internetConnected())
    } catch (ie) {
      devPrint('!!! error in sendImagesInImageMap $ie');
    } // end try (e)
    imageSendLock.queueUnlock(functionName);
  } // end if (imageLock.lock1(functionName))
} // end of sendImagesInImageMap

Future<void> uploadUpdateImage(
    String localPath, String originalPath, int retry) async {
  // upload image to cloud and update imageMap
  // this is used for image that is not in imageMap

  String url = await uploadImageToCloud(localPath);
  // if (url.contains('aume__') && retry >= maxImageUploadRetry - 1) {
  //   devPrint('Error upload in sendImagesInImageMap:$url');
  //   imageMapUpdateUrl(localPath, originalPath);
  // } else {
  //   imageMapUpdateUrl(localPath, url)
  // }
  imageMapUpdateUrl(localPath, url);
} // end of uploadUpdateImage

Future<String> uploadImageToCloud(String localPath) async {
  // try to upload to cloud, will return successful url if successful
  // will return 'aum__Invalid image path-XX__mua' if failed
  const invalidPathPrefix = 'aume__InvalidImagePath-';
  const invalidPathPostfix = '__emua';
  String returnUrl = invalidPathPrefix;
  if (localPath.length < 5 || !localPath.contains('___')) {
    devPrint('Not processing localPath = $localPath');
  } else {
    // returnUrl = invalidPathPrefix;
    List<String> fileArray = localPath.split('___');
    String rawFolder = Uri.decodeComponent(fileArray[0]);
    String folder = rawFolder.substring(
        rawFolder.lastIndexOf('$localImageBeginningFolderDivider/') +
            localImageBeginningFolderDivider.length +
            1);
    String fileName = (fileArray[1]).replaceAll('.jpg', '');
    String finalImagePath = await renamePath(
        originalImagePath: localPath, folder: folder, fileName: fileName);
    try {
      if (await internetConnectedCheck()) {
        String tempResult =
        await uploadToCloudStorage(finalImagePath, "$folder/$fileName.jpg");
        if (isValidImageUrl(tempResult)) {
          returnUrl = tempResult;

          //file.delete(); // file successfully uploaded, delete local file
        } else {
          var imageMapEntry = imageMapGet(finalImagePath);
          if (imageMapEntry == null) {
            await imageMapUpdateUrl(finalImagePath, emptyString);
            imageMapEntry = imageMapGet(finalImagePath);
          }
          if (imageMapEntry![3] >= maxImageUploadRetry) {
            // returnUrl =
            //     '${invalidPathPrefix}13:$emptyString$invalidPathPostfix'; // not a valid url
            returnUrl =
            '${invalidPathPrefix}13:$finalImagePath$invalidPathPostfix'; // not a valid url
          } else {
            returnUrl =
            '$localImagePrefix$localPath$localImagePostfix'; // put original for retry
          }
          tempResult = returnUrl;
        } // end if (isValidImageUrl(tempResult))
        await imageMapUpdateUrl(finalImagePath, tempResult);
      } else {
        returnUrl =
        '$localImagePrefix$localPath$localImagePostfix'; // put original for retry
      } // end if (await internetConnectedCheck())
    } catch (e) {
      returnUrl =
      '${invalidPathPrefix}10-${e.toString()}$invalidPathPostfix'; // end if (file.existsSync())
      devPrint('Error in uploadImageToCloud $e');
      if (internetConnected()) {
        await imageMapUpdateUrl(finalImagePath, returnUrl);
      }
    } // end try (e)
  }
  return returnUrl;
} // end of uploadImageToCloud
