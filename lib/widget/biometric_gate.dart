import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:local_auth/local_auth.dart';

import '../global.dart'; // diamondTextToList

/// Whether [component] requires biometric verification.
/// Returns true ONLY when component is a Map with `biometrik` set to
/// boolean `true`. All other shapes (null, missing key, non-bool value,
/// non-Map component) return false.
bool bioGateRequired(dynamic component) {
  // Server-driven JSON (Sheets) delivers values as STRINGS, so `biometrik`
  // arrives as "true", not a bool. Coerce via toString().toLowerCase() ==
  // 'true' -- same convention as sibling flags (fakeGpsAllowed /
  // outPositionAllowed) in the attendance widget. A real bool `true` still
  // passes (true.toString() == 'true'), so both shapes work.
  return component is Map &&
      component['biometrik']?.toString().toLowerCase() == 'true';
}

/// Whether device credential (PIN / pattern / passcode) is accepted ALONGSIDE
/// biometrics, from the optional `biometrikPin` JSON flag (string "true", same
/// coercion as [bioGateRequired]). When true, [bioGate] runs with
/// `biometricOnly:false` so the OS prompt offers biometric AND device credential
/// and the user picks which to use; when false/absent the gate is
/// biometric-only. (The app cannot force a *specific* type, e.g. fingerprint vs
/// face -- that is always the OS's choice.)
bool bioGatePinAllowed(dynamic component) {
  return component is Map &&
      component['biometrikPin']?.toString().toLowerCase() == 'true';
}

/// Pure truth-table for the gate decision.
///
/// - Not required -> pass (true).
/// - Required but the device cannot authenticate the requested way (no enrolled
///   biometric, or in PIN-allowed mode no device lock set at all) -> pass
///   (true, spec 5).
/// - Required and the device can authenticate -> return [authOk].
bool bioGateOutcome({
  required bool required,
  required bool deviceCanAuth,
  required bool authOk,
}) {
  if (!required) return true;
  if (!deviceCanAuth) return true;
  return authOk;
}

/// Resolves the prompt/dialog texts from the single `biometrikText` JSON field:
/// a ◆-separated string `"reason◆failTitle◆failMessage"` (same separator the
/// app uses everywhere, via [diamondTextToList]). Each part is optional; a
/// missing or blank part falls back to its Indonesian default. Length-guarded
/// so a shorter/empty string never throws.
({String reason, String failTitle, String failMessage}) bioGateTexts(
  dynamic component,
) {
  final List<String> parts = component is Map
      ? diamondTextToList((component['biometrikText'] ?? '').toString())
      : const <String>[];
  String at(int i, String fallback) =>
      (parts.length > i && parts[i].trim().isNotEmpty) ? parts[i] : fallback;
  return (
    reason: at(0, 'Verifikasi identitas Anda'),
    failTitle: at(1, 'Autentikasi Gagal'),
    failMessage: at(2, 'Verifikasi biometrik gagal. Coba lagi.'),
  );
}

/// Orchestrator: evaluates whether the action should proceed.
///
/// Returns `true` if the action may continue, `false` if it was blocked.
/// Shows a fail dialog on auth failure (guarded by `context.mounted`).
///
/// This is a standalone utility -- it does NOT push to routeStack, does NOT
/// call gotoRoute, and does NOT modify any state. The caller simply returns
/// early when this returns false.
Future<bool> bioGate(dynamic component, BuildContext context) async {
  final bool required = bioGateRequired(component);
  if (!required) return true;

  final bool allowPin = bioGatePinAllowed(component);
  final auth = LocalAuthentication();

  // Can the device authenticate the way this gate asks?
  // - PIN allowed (biometricOnly:false): any device lock works. isDeviceSupported()
  //   is true when the device can use biometrics OR fail over to a device
  //   credential (PIN/pattern/passcode); false when no lock is set at all.
  // - biometric-only: require an actually-enrolled biometric (isDeviceSupported +
  //   canCheckBiometrics + a non-empty enrolled list).
  final bool deviceCanAuth = allowPin
      ? await auth.isDeviceSupported()
      : await auth.isDeviceSupported() &&
            await auth.canCheckBiometrics &&
            (await auth.getAvailableBiometrics()).isNotEmpty;

  if (!deviceCanAuth) return true; // spec 5: no usable lock -> pass through

  final texts = bioGateTexts(component);

  bool authOk;
  try {
    authOk = await auth.authenticate(
      localizedReason: texts.reason,
      options: AuthenticationOptions(
        biometricOnly: !allowPin,
        stickyAuth: true,
      ),
    );
  } catch (_) {
    // ponytail: lockedOut / permanentlyLockedOut / noCredentialsSet treated as
    // fail for v1. Upgrade path: parse the exception code and branch (e.g.
    // no-credential -> pass through; locked -> distinct message).
    authOk = false;
  }

  // Delegate the final decision to the unit-tested pure truth table so the
  // production path exercises the same function the tests cover.
  if (!bioGateOutcome(
    required: required,
    deviceCanAuth: deviceCanAuth,
    authOk: authOk,
  )) {
    if (context.mounted) {
      await Get.dialog(
        AlertDialog(
          title: Text(texts.failTitle),
          content: Text(texts.failMessage),
          actions: <Widget>[
            TextButton(
              child: const Text('Ok'),
              onPressed: () {
                Get.back();
              },
            ),
          ],
        ),
      );
    }
    return false;
  }

  return true;
}
