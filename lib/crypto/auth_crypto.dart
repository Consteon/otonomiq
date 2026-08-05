import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:pointycastle/export.dart'; // Replaced 'argon2' with 'pointycastle'

// import 'package:argon2_ffi_base/argon2_ffi_base.dart';
// full registry
// import 'package:flutter_sodium/flutter_sodium.dart';
import '../ftz_secret.dart';
import '../global.dart';
// import 'package:encrypt/encrypt.dart' as encrypt; // Removed encrypt package

typedef ClusterPosition = ({String vid, int cluster, int position});
// test keccak256 & keccak512 in :
// https://github.com/mmsqe/pointycastle/blob/master/test/digests/sha3_test.dart

/// Creates a checksum based on the SHA3-256 hash of the input data.
/// The output is a record containing the final integer checksum and the intermediate hash.
({int checksum, String sha256Hash}) createChecksumSha3(dynamic data) {
  // 1. Convert the entire data structure to a single, stable string.
  String stableString = _createStableString(data);

  // 2. Compute the SHA3-256 hash of that string.
  String hashHex = sha3_256(stableString);

  // 3. Convert the hex hash to a BigInt and use modulo to get a 14-digit integer.
  final BigInt hashAsBigInt = BigInt.parse(hashHex, radix: 16);
  final BigInt modulus = BigInt.from(10).pow(14);
  final int finalChecksum = (hashAsBigInt % modulus).toInt();

  return (checksum: finalChecksum, sha256Hash: hashHex);
} // end of createChecksumSha3

/// Recursively traverses a data structure to create a single, stable string representation.
String _createStableString(dynamic element) {
  if (element == null) return "null";
  if (element is String)
    return '"$element"'; // Add quotes to distinguish from other types
  if (element is num || element is bool) return element.toString();

  if (element is List) {
    return '[${element.map(_createStableString).join(',')}]';
  }

  if (element is Map) {
    // Sort keys to ensure map stability
    var sortedKeys = element.keys.toList()
      ..sort(
        (a, b) => _createStableString(a).compareTo(_createStableString(b)),
      );

    var mapEntries = sortedKeys.map((key) {
      return '${_createStableString(key)}:${_createStableString(element[key])}';
    });
    return '{${mapEntries.join(',')}}';
  }

  // Fallback for other types
  return '"${element.toString()}"';
} // end of createChecksumSha3

Future<String> getSharedKey(int prefix) async {
  // get shared key for user qr
  if (prefix == 1) {
    List<String?> r = await Future.wait([
      storage.read(key: 'sd1'),
      storage.read(key: 'sd2'),
    ]);
    if (r[0] == null || r[0]!.length < 7) {
      r[0] = '11111111111111';
    }
    if (r[1] == null || r[0]!.length < 7) {
      r[1] = '22222222222';
    }
    return sha3_256(
      r[0]!.substring(5) +
          r[1]!.substring(0, r[1]!.length - 1).split('').reversed.join(''),
    );
  } else {
    return emptyString;
  } // end if (prefix == 1)
} // end of getSharedKey

String generateArgon2Salt() {
  final random = Random.secure();
  return base64Encode(List<int>.generate(16, (i) => random.nextInt(256)));
} // end of generateArgon2Salt

String passwordHashCreate(String password) {
  String hashResult = emptyString;
  int vid = transactionStore.state.screenTx['#VID'] ?? -1;
  if (vid < 0) {
    return '${hashResult}VID not set';
  }
  try {
    String saltSeed = base64ForUrl(generateArgon2Salt());
    Uint8List salt = latin1.encode(
      sha3_256('hjJ$saltSeed${vid}s wA${String.fromCharCode(10)}23+=%'),
    );
    Argon2Parameters parameters = Argon2Parameters(
      Argon2Parameters.ARGON2_id,
      salt,
      version: Argon2Parameters.ARGON2_VERSION_13,
      iterations: 4,
      memory: 1 << 16, // Renamed from memoryKB, value 65536
      lanes: 2,
      desiredKeyLength: 64, // Added required parameter
    );
    final argon2 = KeyDerivator("Argon2"); // Use KeyDerivator factory
    argon2.init(parameters);
    Uint8List passwordBytes = utf8.encode(
      password,
    ); // Changed from parameters.converter
    Uint8List result = argon2.process(passwordBytes); // Use process()
    String hash64 = base64ForUrl(base64Encode(result));
    hashResult = '$saltSeed:$hash64'; // Concatenate salt and hash
  } catch (eh) {
    hashResult = emptyString + eh.toString();
  }
  return hashResult;
} // end of passwordHashCreate

bool passwordVerify(String password, String passwordHash) {
  //  var uid = transactionStore.state.screenTx['#FIREBASE_USER'].uid;
  bool boolResult = false;
  final parts = passwordHash.split(':');
  if (parts.length != 2) {
    // throw Exception('Invalid hashed password format');
    return false;
  }
  int vid = transactionStore.state.screenTx['#VID'] ?? -1;
  if (vid < 0) {
    // throw Exception('VID not set');
    return false;
  }
  try {
    String saltSeed = parts[0];
    Uint8List salt = latin1.encode(
      sha3_256('hjJ$saltSeed${vid}s wA${String.fromCharCode(10)}23+=%'),
    ); // Fixed typo: sha3_2s.sha3_256 -> sha3_256
    Argon2Parameters parameters = Argon2Parameters(
      Argon2Parameters.ARGON2_id,
      salt,
      version: Argon2Parameters.ARGON2_VERSION_13,
      iterations: 4,
      memory: 1 << 16, // Renamed from memoryKB, value 65536
      lanes: 2,
      desiredKeyLength: 64, // Added required parameter
    );
    final argon2 = KeyDerivator("Argon2"); // Use KeyDerivator factory
    argon2.init(parameters);
    Uint8List passwordBytes = utf8.encode(
      password,
    ); // Changed from parameters.converter
    Uint8List result = argon2.process(passwordBytes); // Use process()
    String currentHash = base64ForUrl(base64Encode(result));
    boolResult = constantTimeComparison(currentHash, parts[1]);
  } catch (ve) {
    boolResult = false;
  }
  return boolResult;
} // end of argon2VerifyPassword

bool constantTimeComparison(String a, String b) {
  // Helper function for constant-time comparison to avoid timing attacks
  if (a.length != b.length) {
    return false;
  }
  var result = 0;
  for (int i = 0; i < a.length; i++) {
    result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return result == 0;
} // end of constantTimeComparison

String crQRAttend1Enc(String content) {
  // attend1 encryption
  // put get key and iv here
  return aesEnc(content, 'tempkey', 'tempiv');
}

String crQRAttend1Dec(String content) {
  // attend1 decryption
  // put get key and iv here
  // return aesDec(content, 'tempkey', 'tempiv');
  return content;
}

String aesEnc(var data, var key, var iv) {
  // put AES encrypt algorithm here
  return data;
}

/// Helper function to convert a hex string to a Uint8List
Uint8List _hexToBytes(String hex) {
  if (hex.length % 2 != 0) {
    throw ArgumentError("Hex string must have an even length.");
  }
  final bytes = Uint8List(hex.length ~/ 2);
  for (int i = 0; i < bytes.length; i++) {
    final hexChars = hex.substring(i * 2, (i * 2) + 2);
    bytes[i] = int.parse(hexChars, radix: 16);
  }
  return bytes;
}

/// Decrypts a hex-encoded string using AES-256.
/// The IV is extracted from the first 16 bytes (32 hex chars) of the payload.
/// Variant can be 'cbc' or 'gcm'.
/// [hexPayload] The hex-encoded string containing IV + ciphertext.
/// [hexKeyString] The 64-character hex-encoded (32-byte) secret key.
/// Returns the decrypted plaintext.
String aesDec(String hexPayload, String hexKeyString, String variant) {
  String decrypted = errorString;
  // The IV is 16 bytes, which is 32 characters in hexadecimal.
  try {
    const int ivSize = 32;
    if (hexPayload.length < ivSize) {
      throw ArgumentError("Hex payload is too short to contain an IV.");
    }

    // 1. Extract IV and ciphertext from the hex payload
    final String ivHex = hexPayload.substring(0, ivSize);
    final String ciphertextHex = hexPayload.substring(ivSize);

    // 2. Convert hex strings to bytes using our helper
    final keyBytes = _hexToBytes(hexKeyString);
    final ivBytes = _hexToBytes(ivHex);
    final ciphertextBytes = _hexToBytes(ciphertextHex);

    // 3. Create KeyParameter
    final keyParams = KeyParameter(keyBytes);

    Uint8List decryptedBytes;

    // 4. Create the encrypter and decrypt
    if (variant == 'cbc') {
      // Create a CBC cipher with PKCS7 padding (standard for 'encrypt' pkg)
      final cipher = PaddedBlockCipher('AES/CBC/PKCS7');

      // Initialize for decryption
      cipher.init(
        false, // 'false' for decryption
        PaddedBlockCipherParameters(
          ParametersWithIV(keyParams, ivBytes),
          null, // No specific padding params
        ),
      );

      // Process the data
      decryptedBytes = cipher.process(ciphertextBytes);
    } else if (variant == 'gcm') {
      // Create a GCM cipher
      final cipher = GCMBlockCipher(AESEngine());

      // Initialize for decryption
      // GCM default MAC size is 128 bits (16 bytes)
      // The 'encrypt' package uses 128-bit MAC by default.
      final macSizeInBits = 128;
      final params = AEADParameters(
        keyParams,
        macSizeInBits,
        ivBytes,
        Uint8List(0),
      );
      cipher.init(false, params); // 'false' for decryption

      // Allocate an output buffer.
      // getOutputSize for decryption will return input_length - mac_size.
      final outputSize = cipher.getOutputSize(ciphertextBytes.length);
      if (outputSize < 0) {
        throw ArgumentError("Input is too short to contain a GCM MAC tag.");
      }
      final outputBuffer = Uint8List(outputSize);

      // Process all bytes (ciphertext + tag) in one go.
      // pointycastle's GCM implementation handles splitting them.
      int bytesProcessed = cipher.processBytes(
        ciphertextBytes,
        0,
        ciphertextBytes.length,
        outputBuffer,
        0,
      );

      // doFinal will validate the tag (from the end of ciphertextBytes)
      // and write any remaining buffered bytes.
      // It will throw an exception if the tag is invalid.
      int bytesFinal = cipher.doFinal(outputBuffer, bytesProcessed);

      // The final decrypted data is in the output buffer.
      int totalBytes = bytesProcessed + bytesFinal;
      decryptedBytes = outputBuffer.sublist(0, totalBytes);
    } else {
      throw ArgumentError("Unsupported AES variant: $variant");
    }

    // 5. Convert decrypted bytes back to a string
    decrypted = utf8.decode(decryptedBytes);
  } catch (e) {
    debugPrint("aesDec failed: $e");
    decrypted = errorString; // Return the initial value if decryption fails
  }
  return decrypted;
} // end aesDec

Future pinHash(String pin) async {
  var result = passwordHashCreate(pin);
  return result;
}

// String sha3_512(String inputText) {
//   var plainText = createUInt8ListFromString(inputText);
//   var out = sha3_512Registry.process(plainText);
//   String outputText = formatBytesAsHexString(out);
//   return outputText;
// }

String sha3_256(String inputText) {
  dynamic plainText = createUInt8ListFromString(inputText);
  dynamic out = sha3_256Registry.process(plainText);
  return formatBytesAsHexString(out);
} // end of sha3_256

String sha3_256B64(String inputText) {
  dynamic plainText = createUInt8ListFromString(inputText);
  dynamic out = sha3_256Registry.process(plainText);
  return base64Encode(out);
} // end of sha3_256B64Url

Uint8List createUInt8ListFromString(String s) {
  var ret = Uint8List(s.length);
  for (var i = 0; i < s.length; i++) {
    ret[i] = s.codeUnitAt(i);
  }
  return ret;
} // end of createUInt8ListFromString

String formatBytesAsHexString(Uint8List bytes) {
  var result = StringBuffer();
  for (var i = 0; i < bytes.lengthInBytes; i++) {
    var part = bytes[i];
    result.write('${part < 16 ? '0' : ''}${part.toRadixString(16)}');
  }
  return result.toString();
} // end of formatBytesAsHexString

String base64ForUrl(String base64String) {
  // Replace any invalid characters for a URL
  final String result = base64String
      .replaceAll('+', '-')
      .replaceAll('/', '_')
      .replaceAll('=', '');
  return result;
} // end of base64ForUrl

String createPublicDH1(String s, p, g) {
  var result = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    int d1 = int.parse(s.substring(i, i + 1), radix: 16);
    int d2 = (pow(dhG, (d1 % dhP)) % dhP).toInt();
    String d3 = d2.toRadixString(16);
    result.write(d3);
  }
  return result.toString();
} // end of createPublicDH1

String createPrivateKey(String saltInput) {
  /// create private key from vid, time, location, imei, and any salt
  /// assumption state [IMEI, LOCATION, VID] set already by other process
  String result = '--';
  String salt = saltInput;
  int now = DateTime.now().millisecondsSinceEpoch;
  var state = transactionStore.state.screenTx;
  //  String seed =
  //      salt + state['#VID'] + now.toString() + state['#LOCATION'].lng.toString();
  //  seed += state['#IMEI'] + state['#LOCATION'].lat.toString();
  return result;
} // end of createPrivateKey

String qr1Decrypt(String cipherText) {
  String result = 'Fail';
  result = cipherText;
  return result;
} // end of qr1Decrypt

String makeLqrCode(String text) {
  /// Build a version-0 (plaintext) location QR payload from any text.
  /// Format: '0' encryption-version marker + 'l' location tag + sha1 hex,
  /// e.g. 0l9d637068c9470c72407715b3dc03a110e818b75b (1 + 1 + 40 = 42 chars).
  /// Deterministic — the same text always yields the same code.
  /// The result is what lqrVerify returns minus the leading '0', so it must
  /// match a key in #LQR_LIST (or #TABLE<code>) for a scan to resolve.
  // ponytail: sha1 only supplies a stable 160-bit id. aecDecrypt version '0'
  // does no verification, so this is an identifier, not a security boundary.
  // Swap for the real sheet generator once its algorithm is known.
  final Uint8List digest = SHA1Digest().process(
    Uint8List.fromList(utf8.encode(text)),
  );
  return '0l${formatBytesAsHexString(digest)}';
} // end of makeLqrCode

Future<String> lqrVerify(String p, String q, var rawQrText) async {
  String qrValid = empty;
  String qrText = rawQrText;
  String returnValue = errorString;

  if (rawQrText.length >= 4 && rawQrText.substring(0, 4) == 'http') {
    qrText = rawQrText.substring(rawQrText.lastIndexOf('/qr/') + 4);
  }
  // qrValid = location[qrText]??empty;
  if (qrText.isNotEmpty) {
    qrValid = aecDecrypt(qrText, 'l');
  }
  if (qrValid != empty) {
    returnValue = qrValid;
  } else {
    returnValue = errorString;
  }
  // use code below as reference to version 1 decryption (220105)
  /*
  if (qrValid == empty) {
    if (qrText.substring(0, 1) == '1' &&
        qrText.length == 129) { // 129 = fix length of location QR code
      String shared = aec1S(p, q);
      String decrypted = aec1D(shared, qrText);
      String qrData = decrypted.substring(0, 40);
      String qrHash = decrypted.substring(40);
      if (qrHash == aec1h(qrData)) {
        qrValid = qrData;
      }
    }
  }
  */
  return returnValue;
} // end of lqrVerify

/// Calculates a value based on a complex formula, mimicking a Google Sheets function.
///
/// The formula is equivalent to:
/// =MOD(((VALUE(MID(A2, 1, 7))+VALUE(MID(A2, 2, 7))+VALUE(MID(A2, 3, 7))+VALUE(MID(A2, 4, 7)))*100000+VALUE(MID(A2, 5, 4))+VALUE(MID(A2, 7, 4))*VALUE(MID(A2, 9, 4))), 1000000000000)
///
/// @param input The input string, corresponding to cell A2.
/// @returns The calculated integer result.
int getAddress(String input) {
  // Ensure the input string is long enough to prevent range errors.
  if (input.length < 14) {
    throw ArgumentError(
      "Input string must be at least 14 characters long. Current length: ${input.length}",
    );
  }

  try {
    // Helper function to parse substrings into integers, mimicking VALUE(MID(...)).
    // Dart's substring is 0-indexed, so we subtract 1 from the start position.
    int getValue(int start, int length) {
      // Adjusted for 0-indexed substring: start - 1
      return int.parse(input.substring(start - 1, (start - 1) + length));
    }

    // Part 1: Sum of the first four 7-digit numbers.
    int sumOfFirstParts =
        getValue(1, 7) + getValue(2, 7) + getValue(3, 7) + getValue(4, 7);

    // Part 2: Multiply the sum by 100,000.
    int multipliedSum = sumOfFirstParts * 100000;

    // Part 3: The 4-digit number starting at the 5th position.
    int middlePart = getValue(5, 4);

    // Part 4: The product of two 4-digit numbers.
    int productOfLastParts = getValue(7, 4) * getValue(9, 4);

    // Part 5: Sum all the calculated parts.
    int totalSum = multipliedSum + middlePart + productOfLastParts;

    // Part 6: Apply the final modulo.
    int result = totalSum % 1000000000000;

    return result;
  } on FormatException catch (e) {
    // Handle cases where a substring is not a valid number.
    debugPrint(
      "Error: A part of the input string could not be parsed as a number. Details: $e",
    );
    rethrow;
  } on RangeError catch (e) {
    debugPrint(
      "Error: Index out of range when parsing input string. Please check input length. Details: $e",
    );
    rethrow;
  }
} // end of getAddress

/// Extracts the cluster and position from a given address.
///
/// @param vid The video ID (which is the address string before conversion).
/// @returns A record containing the cluster (first 7 digits) and position (last 5 digits).
ClusterPosition getClusterAndPosition(String vid) {
  String result = errorString;
  int cluster = -1;
  int position = -1;

  try {
    // Calculate the address integer from the video ID string.
    int address = getAddress(vid);

    // Convert the address integer to a string, padding with leading zeros to ensure it's 12 digits long.
    String addressString = address.toString().padLeft(12, '0');

    // Ensure the string is at least 12 characters long after padding.
    if (addressString.length < 12) {
      throw StateError(
        'Address string must be at least 12 characters long after padding for cluster/position extraction.',
      );
    }

    // The cluster is the integer value of the first 7 digits.
    cluster = int.parse(addressString.substring(0, 7));

    // The position is the integer value of the remaining 5 digits.
    position = int.parse(
      addressString.substring(7, 12),
    ); // Explicitly take 5 digits
  } catch (e) {
    result = errorString;
  }
  return (vid: result, cluster: cluster, position: position);
} // end of getClusterAndPosition

String assetVerify(String rawQrText, int initialCheckPosition) {
  // The lqrVerify function returns a non-nullable String, so `result` here will not be null.
  // The type of `result` is changed from `String?` to `String`.
  String result = errorString;
  String qrText = rawQrText;
  try {
    if (rawQrText.length >= 4 && rawQrText.substring(0, 4) == 'http') {
      qrText = rawQrText.substring(rawQrText.lastIndexOf('/qr/') + 4);
    }
    String? t = getAecKey('6');
    result = aesDec(qrText, getAecKey('6')!, 'cbc');
    // The null check `result != null` is now redundant and removed.
    debugPrint('qrText in assetVerify: $result');
    bool codeIsValid = integrityCheck(result, initialCheckPosition);
    if (!codeIsValid) {
      result = errorString;
    }
  } catch (e) {
    result = errorString;
  }
  return result;
} // end of assetVerify(String p, String q, var rawQrText)

bool integrityCheck(String qrText, int initialCheckPosition) {
  // put integrity check here
  // based on https://docs.google.com/spreadsheets/d/14qT1qbVitTYYfppF8Y21OGC_5XYUI9Kk0KzZtN15vZo/edit?gid=1066641925#gid=1066641925
  return true;
} // end of integrityCheck

// ========================== Temporary ==============================
String curToken =
    'pd66RVFnC0LI4b2267227b1521271612Fn0P1223191b173558b12a9134a1264818ca621641298a77141c4524232434969cc1147b72491c273435c74b127514518c918c7361662611c49a628ab8313b1614c2454ba418447ca934128186332114b3998a24714139572b6a44b61cb2267227b152127161271c129c612111221588974117539a4129689b26b994247861232912ec1d6fd216ee79589e7471396e21172fb11affd261d671dd2e50fd2de711705ffa965becb19329ad013ed4dc58314f272d72c3564118f05ead50dedd3881b6ca';
// ========================== end of Temporary =============================
// =========================== Key Getter ===========================
Future omLqrReaderP() async {
  String? myOmLqrReaderP;
  try {
    myOmLqrReaderP = await storage.read(key: 'omLqrReaderP');
  } catch (e) {
    devPrint(e.toString());
  }
  if (myOmLqrReaderP == null) {
    myOmLqrReaderP = curToken.substring(356, 420);
    storage.write(key: 'omLqrReaderP', value: myOmLqrReaderP);
  }
  return myOmLqrReaderP;
} // end of omLqrReaderP

Future osLqrMakerQ() async {
  String? myOsLqrMakerQ;
  try {
    myOsLqrMakerQ = await storage.read(key: 'osLqrMakerQ');
  } catch (e) {
    devPrint(e.toString());
  }
  if (myOsLqrMakerQ == null) {
    myOsLqrMakerQ = curToken.substring(36, 164);
    storage.write(key: 'osLqrMakerQ', value: myOsLqrMakerQ);
  } // end if (myOsLqrMakerQ == null)
  return myOsLqrMakerQ;
} // end of osLqrMakerQ

// ========================= end of Key Getter ===========================
// ========================== AEC1 family ==========================
//void main() {
//  const secureSharedKey1 =
//      'ff5db751ebdba8970b972ddb8eb20' + '1391cca39cbd13ecafd4f553b20088801f7';
//  const securePrivateKey1 =
//      '107efcd749eeca80de61681786' + '6fb6589ace3ffa629364ff907129551fb964f5';
//
//  String privateKey =
//      'e595adbe0c1dc55facc121e133c7f7d2a42886490860eb73045e8b1021900967';
//  String myPublicKey = aec1q(privateKey);
//  String otherPublicKey =
//      '242b24c14c2c51a5c9417a211b5132c769345129b147187c1a713aa1a' +
//          '44141612115664116143125bb51413923a113911545bba113a94191826c31263b24b33c                                   ';
//  String sharedKey = aec1s(privateKey, otherPublicKey);
//  String rawData = '415c4dd108337b1285178e20e6f3d4142f61feba4c' +
//      '79d74eab1d6480406f5e8e5498d6e2489a7552e9469595e3c6dd30df541b84';
//
//  String keyFromPassPhrase = aec1h('This is my very secret passphrase');
////   devPrint ('key len = ${keyFromPassPhrase.length}');
//  String chiperPrivateKey = aec1eH64(keyFromPassPhrase, privateKey);
//  String pb2 = aec1qc(keyFromPassPhrase, chiperPrivateKey);
//  String shared2 = aec1sc(keyFromPassPhrase, chiperPrivateKey, otherPublicKey);
//  String encryptedData = aec1e64c(keyFromPassPhrase, chiperPrivateKey, rawData);
//  String data = aec1d64c(keyFromPassPhrase, chiperPrivateKey, encryptedData);
//  String teste = aec1eH64(secureSharedKey1,rawData);
//  String testd = aec1dH64(secureSharedKey1,teste);
//  String newEncrypted = aec1eH64(secureSharedKey1,rawData);
//  String newDecrypted = aec1dH64(secureSharedKey1,newEncrypted);
//  devPrint ('private key $privateKey');
//  devPrint ('public1 = $myPublicKey');
//  devPrint ('public2 = $pb2');
//  devPrint ('shared key = $sharedKey');
//  devPrint ('shared2 = $shared2');
//  devPrint ('key from pass phrase $keyFromPassPhrase');
//  devPrint ('cp = $chiperPrivateKey');
//  devPrint ('cp decrypted ${aec1dH64(keyFromPassPhrase,chiperPrivateKey)}');
//  devPrint('rawData = $rawData');
//  devPrint ('encrypted = $encryptedData');
//  devPrint ('decrypted = $data');
//  devPrint ('test encryption H64 = $teste');
//  devPrint ('test decryption H64 = $testd');
//  devPrint ('New Encrypted $newEncrypted');
//  devPrint ('New Decrypted $newDecrypted');
//}

String aec1qc(String phKey, String cp) {
  // Public key generator from private key
  String p = aec1D(phKey, cp, 24);
  return aec1Q(p);
} // end of aec1qc

String aec1sc(String phKey, String cp, String qk) {
  String p = aec1D(phKey, cp, 24);
  return aec1S(p, qk);
} // end of aec1sc

String aec1h(String data) {
  // Authenium EC 1 hashing function
  String hashingPadding =
      '76ad54fc4d31e7ec12375709f438b4bdf0d7e3107ddaf9a0e56bc5ce7afe467d'; // put in secure storage
  var o = List<int>.filled(16, 0);
  String hx = hashingPadding.substring(0, 4);
  int l = data.length;

  for (int i = 0; i < o.length; i++) {
    hx = hashingPadding.substring(i * 4, i * 4 + 4);
    o[i] =
        (data.codeUnitAt(0) *
            data.codeUnitAt(l - 1) *
            int.parse(hx, radix: 16)) %
        65536;
  }

  for (int c = 0; c < l; c++) {
    int head = o[0];
    o = o.sublist(1);
    int entry = head ^ data.codeUnitAt(c);
    o.add(entry);
  }

  String hash = '';
  for (int c = 0; c < o.length; c++) {
    String h1 = '000${o[c].toRadixString(16)}';
    h1 = h1.substring(h1.length - 4, h1.length);
    hash += h1;
  }
  return hash;
} // end of aec1h

String aec1E1C(String phKey, String cp, String inputData) {
  // encrypt inputData with aec1 encryption then encode with a64.
  // encryption key derived from phase phrase key (phKey) and ciphered private key (cp).
  String p = aec1D(phKey, cp, 24);
  return aec1E1(p, inputData);
} // end of aec1e64c

String aec1DC(String phKey, String cp, String inputData) {
  // encrypt inputData with aec1 encryption then encode with a64.
  // encryption key derived from phase phrase key (phKey) and ciphered private key (cp).
  String p = aec1D(phKey, cp, 24);
  return aec1D(p, inputData, 24);
} // end of aec1d64c

String aec1Q(String pk) {
  //   devPrint('AEC1q :');
  const G =
      '2c9f4f799eee3b335de8a42a6e51ef90d'
      '2c81bcbf5a514b0400318998583d39f';
  int p = 13;
  int g = 2;
  String result = '';
  int pLength = pk.length;
  if (pLength >= 64) {
    int loop = 16;
    String dhKey = '';
    for (int c = 0; c < loop; c++) {
      var n4 =
          int.parse(G.substring(c * 4, c * 4 + 4), radix: 16) *
          int.parse(pk.substring(c * 4, c * 4 + 4), radix: 16);
      var n5 = padZero(n4.toRadixString(16), 8);
      dhKey += n5;
    }
    loop = 128;
    for (int c = 0; c < loop; c++) {
      int d = int.parse(dhKey.substring(c, c + 1), radix: 16) % p;
      String q = (pow(g, d) % p).toInt().toRadixString(16);
      result += q;
    }
  }
  return result;
} // end of aec1q

String aec1S(String pk, String qk) {
  // Create shared key from private key and other's public key
  const G =
      '2c9f4f799eee3b335de8a42a6e51ef90d'
      '2c81bcbf5a514b0400318998583d39f';
  int p = 13;
  String result = '';
  int pLength = pk.length;
  if (pLength >= 64) {
    int loop = 16;
    String dhKey = '';
    for (int c = 0; c < loop; c++) {
      var n4 =
          int.parse(G.substring(c * 4, c * 4 + 4), radix: 16) *
          int.parse(pk.substring(c * 4, c * 4 + 4), radix: 16);
      var n5 = padZero(n4.toRadixString(16), 8);
      dhKey += n5;
    }
    loop = 128;
    var dq = List<int>.filled(loop, 0);
    for (int c = 0; c < loop; c++) {
      int d = int.parse(dhKey.substring(c, c + 1), radix: 16) % p;
      dq[c] =
          pow(int.parse(qk.substring(c, c + 1), radix: 16) % p, d).toInt() % p;
    }

    int lastS = int.parse(G.substring(G.length - 1, G.length), radix: 16);
    loop = (loop / 2).round();
    for (int c = 0; c < loop; c++) {
      var s = (dq[c * 2] * p + dq[c * 2 + 1] + lastS) % 16;
      result += s.toRadixString(16);
      lastS = s;
    }
  }
  return result;
} // end of aec1s
//------------------------------------------------------------

String aec1E1(String key, String inputData) {
  // Authenium EC 1 base A64 encryption function
  // inputData.length must be even. If odd => add '0' at the front
  // dart implementation of
  //   https://docs.google.com/spreadsheets/d/1NZF40himzMKHvBEy2-i29FbIj4B4IOWcdbalZ3UaBpY/edit#gid=26908217

  String rawData;
  if (inputData.length % 2 == 0) {
    rawData = nonceGenerator(96) + inputData;
  } else {
    rawData = '${nonceGenerator(96)}0$inputData';
  }
  int m1 = 13;
  int m2 = 17;
  int m3 = 19;
  int m4 = 23;
  int encodingVolume = 64;
  int encryptionModulo = encodingVolume * encodingVolume; //*****^2
  const kLength = 64;

  int keyByteSize = (key.length / 2).round();
  var k = List<int>.filled(64, 0);
  for (int b = 0; b < kLength; b++) {
    String t1;
    var t2 = 0;
    if (b < keyByteSize) {
      t1 = key.substring(b * 2, b * 2 + 2);
      t2 = int.parse(t1, radix: 16);
    }
    k[b] = t2;
  }

  var encrypted = '1'; // AEC1 encryption code
  int v = (k[0] * m1 * m2) % encryptionModulo;
  int o = 0;
  int i = 0;
  int loop = ((rawData.length) / 2).round();
  for (int c = 0; c < loop; c++) {
    i = int.parse(
      rawData.substring(c * 2, c * 2 + 2),
      radix: 16,
    ); // take 2 input
    o = i ^ v;
    encrypted +=
        a64[(o / encodingVolume).floor()] + a64[(o % encodingVolume).floor()];
    if (c < loop - 1) {
      v =
          (v * m1 + k[(c + 1) % keyByteSize] * m2 + i * m3 + o * m4) %
          encryptionModulo;
    }
  }
  return encrypted;
} // end of aes1E1
//------------------------------------------------------------

String aec1D(String key, String vEncryptedData, int nonceLength) {
  // Authenium Elliptic Curve 1 base A64 decryption function
  // dart implementation of
  //  https://docs.google.com/spreadsheets/d/1FlgDdtRdqvUJvU0j3S4Lr4CG9nt8fEPPAFZwlS9J5X4/edit#gid=216071792
  // nonceLength = bit. 24 for general, 8 for qr
  String encryptedData = vEncryptedData.substring(1);
  int m1 = 13;
  int m2 = 17;
  int m3 = 19;
  int m4 = 23;
  int encodingVolume = 64;
  int encryptionModulo = encodingVolume * encodingVolume;
  int keyBitSize = 256;
  int keyStringLength = (keyBitSize / 4).round();
  int keyByteSize = (keyStringLength / 2).round();
  const kLength = 64;
  var decrypted = '';
  var eCode = vEncryptedData.substring(0, 1);
  switch (eCode) {
    case '1':
      int keyByte = (key.length / 2).round();
      var k = List<int>.filled(64, 0);
      for (int b = 0; b < kLength; b++) {
        String t1;
        var t2 = 0;
        if (b < keyByte) {
          t1 = key.substring(b * 2, b * 2 + 2);
          t2 = int.parse(t1, radix: 16);
        } // end if (b < keyByte)
        k[b] = t2;
      } // end for (int b = 0; b < kLength; b++)

      String output = '';
      int v = 0;
      int o = 0;
      int i = 0;
      int loop = ((encryptedData.length) / 2).round();
      for (int c = 0; c < loop; c++) {
        int t = c % keyByteSize;
        if (c == 0) {
          v = (k[0] * m1 * m2) % encryptionModulo;
        } else {
          v = (v * m1 + k[t] * m2 + o * m3 + i * m4) % encryptionModulo;
        }
        i =
            base64ToDec(encryptedData.substring(c * 2, c * 2 + 1)) *
                encodingVolume +
            base64ToDec(encryptedData.substring(c * 2 + 1, c * 2 + 2));
        o = i ^ v;
        output += padZero(o.toRadixString(16), 2);
      }
      //decrypted = output.substring(24).toLowerCase();
      decrypted = output.substring(nonceLength).toLowerCase();
      break;

    default:
      decrypted = vEncryptedData;
  }
  return decrypted;
} // end of aec1D
//------------------------------------------------------------

String padZero(String hexa, int len) {
  String tem = ('0' * len) + hexa;
  return tem.substring(tem.length - len, tem.length);
}

String nonceGenerator(int bitLen) {
  var rand = Random.secure();
  String nonce = '';
  int len = (bitLen / 4).round();
  int loop = (len / 5).round() + 1;
  for (int c = 0; c < loop; c++) {
    int randNumber = rand.nextInt(99999999);
    nonce += randNumber.toRadixString(16);
  }
  nonce = nonce.substring(nonce.length - len, nonce.length);
  //   nonce = '9e611040623410122b82331e';
  return nonce;
}

// ======================= end of AEC1 family ======================

String aecDecrypt(String input, String inputType) {
  //  aecDecrypt will try to decrypt with inputType specification
  //  When fail, will try to decrypt with other keys.
  //  inputString : raw string begin with encryption version
  //      0 : no encryption
  //      1 : encryption version 1 (Proprietary)
  //      2 : encryption version 2 (AEC)
  //  inputType : "l" : location  => "6"
  //              "d" : document  => "P"
  //              "u" : user      => "_"

  //   Usage : aecDecrypt(inputString, "l");
  //   final Map<String, String> key = getKeys();
  String result = '--';
  String version = input.substring(0, 1);
  String encrypted = input.substring(1, input.length);
  bool found = false;
  String stringType = "6";

  switch (inputType.toLowerCase()) {
    case "l":
      stringType = "6";
      break;

    case "d":
      stringType = "P";
      break;

    case "u":
      stringType = "_";
      break;
  } // end of switch inputType

  switch (version) {
    case '0':
      result = encrypted;
      break;

    case '2':
      try {
        // trying to decrypt with type from user input
        result = aec2Decrypt(getAecKey(stringType)!, encrypted);
        found = true;
      } catch (e) {
        found = false;
      } // end of try 1
      if (!found) {
        try {
          // trying to decrypt with type = 1st character
          result = aec2Decrypt(
            getAecKey(encrypted.substring(0, 1))!,
            encrypted,
          );
          found = true;
        } catch (e) {
          found = false;
        } // end of try 2
      }
      dynamic ks = getKeyTypes();
      int len = ks.length;
      for (int i = 0; !found & (i < len); i++) {
        // trying to decrypt with all keys available
        try {
          result = aec2Decrypt(getAecKey(ks[i])!, encrypted);
          found = true;
        } catch (e) {
          found = false;
        } // end of try inside for
      } // end of for
      break;
  } // end switch version
  return result;
} // end of aecDecryptor

String aec2Decrypt(String key, String encrypted) {
  // Aec Decrypt version 2
  // Algorithm from https://docs.google.com/spreadsheets/d/1TMnQ-eCVn0iHALZ-85_t3E-tqMJmMgT_95k_JDxe7FU/edit#gid=216071792
  const List<int> m = [0, 13, 17, 19, 23, 29]; // Multiplier
  const encryptionModulo = 4096;
  const int inputBase = 64;
  String result = '';
  List<int> keyVector = [0];
  int keyByte = (key.length) ~/ 2;
  for (int i = 1; i <= keyByte; i++) {
    int cursor = (i - 1) * 2;
    keyVector.add(int.parse(key.substring(cursor, cursor + 2), radix: 16));
  }
  List<int> inputVector = [0];
  int inputLen = encrypted.length ~/ 2;
  int keyCursor = 0;
  int lastPass = 0;
  int lastXOr = 0;
  for (int i = 0; i < inputLen; i++) {
    int cursor = i * 2;
    int value =
        base64ToDec(encrypted.substring(cursor, cursor + 1)) * inputBase +
        base64ToDec(encrypted.substring(cursor + 1, cursor + 2));

    inputVector.add(value);
    int value2 = 0;
    int xorValue = 0;
    if (i == 0) {
      value2 = (keyVector[i + 1] * m[1] * m[2]) % encryptionModulo;
      xorValue = value ^ value2;
    } else {
      value2 =
          (lastPass * m[1] +
              keyVector[keyCursor + 1] * m[2] +
              lastXOr * m[3] +
              inputVector[i] * m[4]) %
          encryptionModulo;
      xorValue = value ^ value2;
    } // end if i == 0
    lastPass = value2;
    lastXOr = xorValue;
    keyCursor = (keyCursor + 1) % keyByte;
    result += a64[xorValue];
  } // end for inputLen
  return result.substring(24).toLowerCase();
} // end of aecDecryptor2

Future<int> getVidUQR(String rawQrText) async {
  // get vid (integer) from user qr
  String vidValid = emptyString;
  String qrText = rawQrText;
  int returnValue = -1;

  if (rawQrText.length >= 4 && rawQrText.substring(0, 4) == 'http') {
    try {
      qrText = rawQrText.substring(rawQrText.lastIndexOf('/qr/') + 4);
      vidValid = aec1D(await getSharedKey(1), qrText, 8);
      int dLen = vidValid.length;
      if (uiemsSxHex() == int.parse(vidValid.substring(dLen - 6, dLen))) {
        vidValid = vidValid.substring(0, dLen - 6);
        returnValue = int.parse(vidValid, radix: 16);
      } else {
        returnValue = -1;
      } // end if (Hex() == int.parse(vidValid.substring(dLen - 6, dLen)))
    } catch (e) {
      returnValue = -1;
    } // end try
  } else {
    returnValue = -1;
  } // end if (rawQrText.length >= 4 && rawQrText.substring(0, 4) == 'http')
  return returnValue;
} // end of getVidUQR

int base64ToDec(String inp) {
  int result = 0;
  int prs = inp.codeUnitAt(0);
  if (65 <= prs && prs <= 90) {
    result = prs - 65;
  } else if (97 <= prs && prs <= 122) {
    result = prs - 71;
  } else if (48 <= prs && prs <= 57) {
    result = prs + 4;
  } else if (prs == 45) {
    result = 62;
  } else if (prs == 95) {
    result = 63;
  }
  return result;
} // end of base64ToDec

String? getAecKey(String keyType) {
  const Map<String, String> keyMap = {
    "6": ftzSecretSixCode, // lqr autsorz
    "P": ftxSecretPCode, // dqr autsorz
  };
  return keyMap[keyType];
} // end of getAecKey

int uiemsSxHex() {
  // user qr marker
  String s1 = '577000';
  return ((int.parse(s1) - 988) / 3).floor() + 10003;
}

List<String> getKeyTypes() {
  // get all kind of 1st char in qr code
  return ['6', 'P', "_"];
} // end of getKeyTypes
