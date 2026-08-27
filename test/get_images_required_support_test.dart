// test/get_images_required_support_test.dart
//
// Pure-function tests for the GET_IMAGES `optional:"FALSE"` submit gate.
// No binding, no Firebase, no GetX.
//
// Each group names the production line to break to see it go red; Task 7 of the
// plan makes running those mutations mandatory. A test that survives its own
// mutation is guarding nothing.
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart' show emptyImageUrl, emptyString, separator;
import 'package:otonomiq/widget/get_images_required_support.dart';

void main() {
  const String realUrl =
      'https://firebasestorage.googleapis.com/v0/b/otq-01/o/meter.jpg';
  const String localPath = 'aum__FTZIMG%2Fmeter___87544551624342-meter.jpg__mua';

  // A recording slot reader: returns the seeded slot for a position (or null
  // when none was seeded) and remembers which positions were asked for.
  ({GetImagesSlotReader read, List<int> asked}) reader(
    Map<int, GetImagesSlot> slots,
  ) {
    final List<int> asked = <int>[];
    return (
      read: (int pos) {
        asked.add(pos);
        return slots[pos];
      },
      asked: asked,
    );
  }

  GetImagesSlot slot(String value, {bool enabled = true}) => GetImagesSlot(
        finalData: value,
        controllerText: '',
        enabled: enabled,
      );

  Map<String, dynamic> getImages({
    String type = 'GET_IMAGES',
    dynamic position = 3,
    String label = 'Foto Muka Meter',
    String text = '+◆Foto muka meter belum diambil',
    Map<String, dynamic> extra = const <String, dynamic>{},
  }) =>
      <String, dynamic>{
        'type': type,
        'position': position,
        'label': label,
        'text': text,
        ...extra,
      };

  group('getImagesSlotValue', () {
    // RED if: the ternary is flipped, or the '--' comparison is replaced with
    // `.isEmpty`. This is the ONE place that has to track api.dart:4839.
    test("the '--' birth sentinel falls back to controller.text", () {
      expect(getImagesSlotValue(emptyString, localPath), localPath);
      expect(getImagesSlotValue('--', ''), '');
    });

    test('a written finalData wins, even over a non-empty controller.text', () {
      expect(getImagesSlotValue(realUrl, 'stale-text'), realUrl);
    });

    test('an EMPTY finalData is a real value and still wins', () {
      // Delete-last writes '' into finalData. '' is not the sentinel, so the
      // composer submits '' — a stale controller.text must NOT resurrect.
      expect(getImagesSlotValue('', 'stale-text'), '');
    });
  });

  group('GetImagesSlot.value', () {
    // RED if: `value` stops delegating (e.g. `=> finalData;`). The selection
    // must live here, not in the untestable RBT closure.
    test('delegates to getImagesSlotValue in both directions', () {
      expect(
        const GetImagesSlot(
                finalData: '--', controllerText: 'from-controller', enabled: true)
            .value,
        'from-controller',
      );
      expect(
        const GetImagesSlot(
                finalData: 'from-final', controllerText: 'stale', enabled: true)
            .value,
        'from-final',
      );
    });
  });

  group('getImagesSlotHasPhoto', () {
    // RED if: `if (v.isEmpty) continue;` is removed.
    test("'' and whitespace are not photos", () {
      expect(getImagesSlotHasPhoto(''), isFalse);
      expect(getImagesSlotHasPhoto('   '), isFalse);
    });

    // RED if: `if (v == emptyString) continue;` is removed.
    test("'--' is not a photo", () {
      expect(emptyString.isEmpty, isFalse, reason: 'guards the premise');
      expect(getImagesSlotHasPhoto(emptyString), isFalse);
    });

    // RED if: `if (v == emptyImageUrl) continue;` is removed.
    test('emptyImageUrl is not a photo', () {
      expect(emptyImageUrl, 'aum__--__mua', reason: 'guards the premise');
      expect(getImagesSlotHasPhoto(emptyImageUrl), isFalse);
    });

    // RED if: `if (v == 'null') continue;` is removed. Without this term the
    // gate fails OPEN on every page whose `currentValue` is absent —
    // init_values.dart:11 turns that into the literal string "null".
    test("the literal string 'null' is not a photo", () {
      expect(getImagesSlotHasPhoto('null'), isFalse);
      expect(getImagesSlotHasPhoto('  null  '), isFalse);
    });

    test('a real URL and a real local path ARE photos', () {
      expect(getImagesSlotHasPhoto(realUrl), isTrue);
      // Proves the emptyImageUrl term matches the WHOLE sentinel, not a prefix:
      // every local image path starts with 'aum__'.
      expect(getImagesSlotHasPhoto(localPath), isTrue);
    });

    // RED if: the ◇ split is dropped. Multi-photo slots are separator[5]-joined.
    test('◇-joined slots count as filled when ANY segment survives', () {
      final String sep = separator[5];
      expect(getImagesSlotHasPhoto('$realUrl$sep$localPath'), isTrue);
      expect(getImagesSlotHasPhoto('$sep$realUrl'), isTrue);
      expect(getImagesSlotHasPhoto('$realUrl$sep'), isTrue);
      expect(getImagesSlotHasPhoto('--$sep--'), isFalse);
      expect(getImagesSlotHasPhoto('$sep$sep'), isFalse);
    });
  });

  group('getImagesIsRequired', () {
    // RED if: the default in `str('optional', 'TRUE')` is changed to 'FALSE'.
    test('absent, blank and whitespace all mean NOT required', () {
      expect(getImagesIsRequired(getImages()), isFalse);
      expect(getImagesIsRequired(getImages(extra: {'optional': ''})), isFalse);
      expect(getImagesIsRequired(getImages(extra: {'optional': '   '})), isFalse);
    });

    test("'TRUE' means NOT required", () {
      expect(getImagesIsRequired(getImages(extra: {'optional': 'TRUE'})), isFalse);
      expect(getImagesIsRequired(getImages(extra: {'optional': 'true'})), isFalse);
      expect(getImagesIsRequired(getImages(extra: {'optional': true})), isFalse);
    });

    // RED if: `.toUpperCase()` is dropped, or the comparison is loosened.
    test('only a literal FALSE arms the gate', () {
      expect(getImagesIsRequired(getImages(extra: {'optional': 'FALSE'})), isTrue);
      expect(getImagesIsRequired(getImages(extra: {'optional': 'false'})), isTrue);
      expect(getImagesIsRequired(getImages(extra: {'optional': ' False '})), isTrue);
      expect(getImagesIsRequired(getImages(extra: {'optional': false})), isTrue);
    });

    // Spec §5 ships the sheet template after the renderer, so a half-swept
    // workbook must leave live pages exactly as they are today.
    test('an unresolved [OPTIONAL] placeholder is NOT required', () {
      expect(
        getImagesIsRequired(getImages(extra: {'optional': '[OPTIONAL]'})),
        isFalse,
      );
    });

    test('a non-Map component does not throw', () {
      expect(getImagesIsRequired(null), isFalse);
      expect(getImagesIsRequired('GET_IMAGES'), isFalse);
    });
  });

  group('getImagesRequiredBlock', () {
    test('children that is not a List yields null', () {
      final r = reader(<int, GetImagesSlot>{});
      expect(getImagesRequiredBlock(null, r.read), isNull);
      expect(getImagesRequiredBlock('children', r.read), isNull);
      expect(getImagesRequiredBlock(<String, dynamic>{}, r.read), isNull);
      expect(r.asked, isEmpty);
    });

    test('non-Map children and other component types are skipped', () {
      final r = reader(<int, GetImagesSlot>{});
      expect(
        getImagesRequiredBlock(<dynamic>[
          null,
          'rbt',
          42,
          <String, dynamic>{'type': 'txf', 'position': 1, 'optional': 'FALSE'},
        ], r.read),
        isNull,
      );
    });

    // RED if: either spelling is dropped from the type test.
    test('both dispatch spellings are recognised, any case', () {
      for (final String tip in <String>[
        'GET_IMAGES',
        'get_images',
        'GETIMAGES',
        'getimages',
        ' Get_Images ',
      ]) {
        final r = reader(<int, GetImagesSlot>{3: slot('')});
        expect(
          getImagesRequiredBlock(
              <dynamic>[getImages(type: tip, extra: {'optional': 'FALSE'})],
              r.read),
          isNotNull,
          reason: 'spelling "$tip" must be recognised',
        );
      }
    });

    test('optional absent or TRUE never blocks, even with an empty slot', () {
      final r = reader(<int, GetImagesSlot>{3: slot('')});
      expect(getImagesRequiredBlock(<dynamic>[getImages()], r.read), isNull);
      expect(
        getImagesRequiredBlock(
            <dynamic>[getImages(extra: {'optional': 'TRUE'})], r.read),
        isNull,
      );
    });

    // RED if: the `getImagesSlotHasPhoto` test is negated or removed.
    test('FALSE + empty slot BLOCKS, with label and text[1]', () {
      final r = reader(<int, GetImagesSlot>{3: slot('')});
      final GetImagesRequirement? block = getImagesRequiredBlock(
          <dynamic>[getImages(extra: {'optional': 'FALSE'})], r.read);
      expect(block, isNotNull);
      expect(block!.title, 'Foto Muka Meter');
      expect(block.message, 'Foto muka meter belum diambil');
      expect(r.asked, <int>[3], reason: 'the parsed int position is used');
    });

    test('FALSE + filled slot does NOT block', () {
      final r = reader(<int, GetImagesSlot>{3: slot(realUrl)});
      expect(
        getImagesRequiredBlock(
            <dynamic>[getImages(extra: {'optional': 'FALSE'})], r.read),
        isNull,
      );
    });

    test('a String position parses to the same int slot', () {
      final r = reader(<int, GetImagesSlot>{3: slot('')});
      expect(
        getImagesRequiredBlock(
            <dynamic>[getImages(position: ' 3 ', extra: {'optional': 'FALSE'})],
            r.read),
        isNotNull,
      );
      expect(r.asked, <int>[3]);
    });

    // RED if: `if (pos == null) continue;` is replaced by a `?? 0` default.
    // A positionless component writes to NO record slot, so requiring it would
    // build a gate the officer can never clear.
    test('a positionless required component is SKIPPED, not blocked', () {
      final r = reader(<int, GetImagesSlot>{});
      expect(
        getImagesRequiredBlock(<dynamic>[
          <String, dynamic>{
            'type': 'GET_IMAGES',
            'label': 'Foto',
            'text': '+◆pesan',
            'optional': 'FALSE',
          },
        ], r.read),
        isNull,
      );
      expect(
        getImagesRequiredBlock(
            <dynamic>[getImages(position: 'abc', extra: {'optional': 'FALSE'})],
            r.read),
        isNull,
      );
      expect(r.asked, isEmpty);
    });

    // RED if: `if (slot != null && !slot.enabled) continue;` is removed.
    // A disabled GET_IMAGES cannot be tapped (otq_get_images_2.dart gates the
    // empty-state `onTap:` and the add button on `canAddMore && isEnabled`),
    // so requiring it would build a gate the officer can never clear.
    test('a required component whose slot is DISABLED is SKIPPED, not blocked',
        () {
      final r = reader(<int, GetImagesSlot>{3: slot('', enabled: false)});
      expect(
        getImagesRequiredBlock(
            <dynamic>[getImages(extra: {'optional': 'FALSE'})], r.read),
        isNull,
      );
      expect(r.asked, <int>[3]);
    });

    // RED if: the disabled skip is widened to `slot == null || !slot.enabled`.
    // A slot that does not exist yet has never been disabled by anyone — that
    // is the ordinary first-render case, and it must STILL be gated.
    test('a required component whose slot is ABSENT still BLOCKS', () {
      final r = reader(<int, GetImagesSlot>{});
      final GetImagesRequirement? block = getImagesRequiredBlock(
          <dynamic>[getImages(extra: {'optional': 'FALSE'})], r.read);
      expect(block, isNotNull);
      expect(block!.message, 'Foto muka meter belum diambil');
      expect(r.asked, <int>[3]);
    });

    // RED if: the disabled skip `return`s instead of `continue`s.
    test('a disabled slot does not mask an empty ENABLED one further down', () {
      final r = reader(<int, GetImagesSlot>{
        3: slot('', enabled: false),
        5: slot('', enabled: true),
      });
      final GetImagesRequirement? block = getImagesRequiredBlock(<dynamic>[
        getImages(position: 3, text: '+◆muka belum', extra: {'optional': 'FALSE'}),
        getImages(position: 5, text: '+◆badan belum', extra: {'optional': 'FALSE'}),
      ], r.read);
      expect(block, isNotNull);
      expect(block!.message, 'badan belum');
    });

    // RED if: the `text(1, default)` fallback is replaced by a bare `text(1)`,
    // or if a missing message is allowed to unblock the submit.
    test("text with no ◆ still BLOCKS, with the default message", () {
      final r = reader(<int, GetImagesSlot>{3: slot('')});
      final GetImagesRequirement? block = getImagesRequiredBlock(
          <dynamic>[getImages(text: '+', extra: {'optional': 'FALSE'})], r.read);
      expect(block, isNotNull);
      expect(block!.message, getImagesRequiredDefaultMessage);
      expect(block.message.contains('◆'), isFalse);
    });

    // RED if: the `message.trim().isEmpty ? default : message` guard is removed.
    test('a blank ◆ segment 1 falls back to the default message', () {
      final r = reader(<int, GetImagesSlot>{3: slot('')});
      expect(
        getImagesRequiredBlock(
                <dynamic>[getImages(text: '+◆', extra: {'optional': 'FALSE'})],
                r.read)!
            .message,
        getImagesRequiredDefaultMessage,
      );
      expect(
        getImagesRequiredBlock(
                <dynamic>[getImages(text: '+◆   ', extra: {'optional': 'FALSE'})],
                r.read)!
            .message,
        getImagesRequiredDefaultMessage,
      );
    });

    test('an absent or blank text still BLOCKS with the default message', () {
      final r = reader(<int, GetImagesSlot>{3: slot('')});
      expect(
        getImagesRequiredBlock(
                <dynamic>[getImages(text: '', extra: {'optional': 'FALSE'})],
                r.read)!
            .message,
        getImagesRequiredDefaultMessage,
      );
      expect(
        getImagesRequiredBlock(<dynamic>[
          <String, dynamic>{
            'type': 'GET_IMAGES',
            'position': 3,
            'label': 'Foto',
            'optional': 'FALSE',
          },
        ], r.read)!
            .message,
        getImagesRequiredDefaultMessage,
      );
    });

    test('a blank or absent label falls back to the default title', () {
      final r = reader(<int, GetImagesSlot>{3: slot('')});
      expect(
        getImagesRequiredBlock(
                <dynamic>[getImages(label: '  ', extra: {'optional': 'FALSE'})],
                r.read)!
            .title,
        getImagesRequiredDefaultTitle,
      );
    });

    // RED if: the loop `return`s on the first REQUIRED component instead of the
    // first BLOCKING one.
    test('a required-but-FILLED field does not mask an empty one below it', () {
      final r = reader(<int, GetImagesSlot>{3: slot(realUrl), 5: slot('')});
      final GetImagesRequirement? block = getImagesRequiredBlock(<dynamic>[
        getImages(
            position: 3,
            label: 'Foto Muka',
            text: '+◆muka belum',
            extra: {'optional': 'FALSE'}),
        getImages(
            position: 5,
            label: 'Foto Badan',
            text: '+◆badan belum',
            extra: {'optional': 'FALSE'}),
      ], r.read);
      expect(block, isNotNull);
      expect(block!.message, 'badan belum');
    });

    test('two empty required fields: the FIRST in page order wins', () {
      final r = reader(<int, GetImagesSlot>{3: slot(''), 5: slot('')});
      final GetImagesRequirement? block = getImagesRequiredBlock(<dynamic>[
        getImages(position: 3, text: '+◆muka belum', extra: {'optional': 'FALSE'}),
        getImages(position: 5, text: '+◆badan belum', extra: {'optional': 'FALSE'}),
      ], r.read);
      expect(block!.message, 'muka belum');
      expect(r.asked, <int>[3], reason: 'short-circuits — never reads slot 5');
    });

    // The '--' and 'null' sentinels arriving through the REAL selection path,
    // not just through getImagesSlotHasPhoto in isolation.
    test('a slot left at its birth state blocks through the real selection', () {
      final r = reader(<int, GetImagesSlot>{
        3: const GetImagesSlot(
            finalData: emptyString, controllerText: '', enabled: true),
      });
      expect(
        getImagesRequiredBlock(
            <dynamic>[getImages(extra: {'optional': 'FALSE'})], r.read),
        isNotNull,
      );

      final r2 = reader(<int, GetImagesSlot>{
        3: const GetImagesSlot(
            finalData: 'null', controllerText: '', enabled: true),
      });
      expect(
        getImagesRequiredBlock(
            <dynamic>[getImages(extra: {'optional': 'FALSE'})], r2.read),
        isNotNull,
      );
    });
  });
}
