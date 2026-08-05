// HH 220817
// init_values.dart

import 'api.dart';
import 'global.dart';
import 'global2.dart';

String getInitialValue(String scrName, dynamic component) {
  String result = "";

  if (component['currentValue'].toString().trim().isNotEmpty) {
    String tip = (component['type'] ?? emptyString).toString().toLowerCase();
    if (tip == 'get_images' || tip == 'getimage') {
      result = getImageInitValue(scrName, component);
    } else if (tip == 'txf') {
      result = getTotalValue(scrName, component);
    } else if (tip == 'switch') {
      result =
          ((component['currentValue'] ?? 'false').toString().toLowerCase() ==
              'true')
          ? "TRUE"
          : "FALSE";
    } else {
      result = component['currentValue'].toString();
    }
  } // end if (component['position'] != null)
  return result;
} //getInitialValue

String getTotalValue(String scrName, dynamic component) {
  // otq_txf
  // result = dynamic data to be stored
  String cData = (component['currentValue'] ?? "").toString();
  String result = "";
  const blackStar = "_u2605_";

  try {
    if (cData.length >= 7 && cData.toString().substring(0, 7) == blackStar) {
      // test for star
      List<String> currentArray = cData.split(blackStar);
      num subTotal = 0;
      bool sum = currentArray[1].toString().trim() == "+";
      bool multiply = currentArray[1].toString().trim() == "*";
      for (var i = 2; i < currentArray.length; i++) {
        late num referenceValue;
        try {
          int referencePosition = int.parse(currentArray[i]);
          referenceValue = num.parse(
            txfController[scrName]![referencePosition]!.finalData,
          );
        } catch (e) {
          referenceValue = 0;
        }
        if (sum) {
          subTotal += referenceValue;
        } else if (multiply) {
          subTotal = subTotal * referenceValue;
        } // end if sum
      } // end for currentArray
      result = subTotal.toString();
    } else {
      result = numericCleanUp(getCurrencyFormat(component['format']), cData);
    } // end if blackStar
  } catch (e) {
    result = cData; // default
  }
  return result;
} // end of getTotalValue

String numericCleanUp(List<dynamic> formatArray, String? inp) {
  // otq_txf
  // cleanup if and only if inp is formatted numeric
  String result = inp ?? "";
  try {
    if (inp != null && formatArray.length == 3) {
      String tPoint = getThousandSeparator(formatArray[1]);
      String decPoint = tPoint == "," ? "." : ",";
      result = inp.replaceAll(formatArray[0], ""); // delete symbol
      result = result.replaceAll(tPoint, ""); // delete thousands separator
      result = result.replaceAll(" ", ""); // delete blank
      result = result.replaceAll(RegExp("[()]"), ""); // delete bracket
      if (decPoint == ","
          ? result.contains(RegExp("[^-,0-9]"))
          : result.contains(RegExp("[^-.0-9]"))) {
        result = inp; // this is numeric, return original string
        if (inp.contains("(") && inp.contains(")")) {
          result = result.replaceAll(RegExp("[()]"), "");
          if (result[0] == "-") {
            result = result.substring(1);
          } else {
            result = "-$result";
          } // end if result[0] == "-"
        } // end if (inp.contains("(") && inp.contains(")"))
        result = result.replaceAll(",", ".");
        if (decPoint == ","
            ? result.contains(RegExp("[^-,0-9]"))
            : result.contains(RegExp("[^-.0-9]"))) {
          result =
              inp; // if there is another character, then revert to original
        }
      } else {
        result = result.replaceAll(",", ".");
      } // end if result.contains(RegExp("[0-9]"))
    } // end if (inp != null && formatArray.length == 3)
  } catch (e) {
    result = inp ?? "";
  }
  return result;
} // end of numericCleanUp

String getImageInitValue(String scrName, dynamic component) {
  // getImage
  String result = "";
  List<String> urlList = component['currentValue'].toString().trim().split(
    '_u2605_',
  );
  result = processData(urlList);
  return result;
} // end of getImageInitValue

String processData(List<String> iList) {
  // getImage
  String result = "";
  for (int i = 0; i < iList.length; i++) {
    result += i == 0 ? iList[i] : "${separator[5]}${iList[i]}";
  }
  return result;
} // end of processData
