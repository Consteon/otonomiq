import 'dart:typed_data' as td;

import 'package:fast_contacts/fast_contacts.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';

import '../global.dart';

/*
  chooseContactAndGetPhoneNumber() will dispay a dialogbox of all contacts.
  tap one to get its phone number
*/
//const String countryCode = '62';

/// True when [contact] matches [query] by display name or by phone number.
///
/// [contact] is one row of the picker's list: `[displayName, {label: number}]`.
///
/// Name match is case-insensitive substring. A query with no digits never
/// falls through to the number branch.
///
/// Number match runs TWO comparisons, because neither alone is enough:
///  - raw digits-only, which handles fixed-line and partial fragments
///    (typed `5551234` vs stored `021-555-1234`);
///  - both sides through [phoneCanonical62], which bridges local and
///    international mobile formats (typed `0812-3456` vs stored
///    `+62 812-3456-7890` — raw digits do NOT match there, since `6281…`
///    never contains `0812…`).
///
/// Top-level and pure so it is testable without pumping a widget.
bool contactMatchesQuery(List<dynamic> contact, String query) {
  final String q = query.trim().toLowerCase();
  if (q.isEmpty) return true;

  if (contact.isNotEmpty && contact[0].toString().toLowerCase().contains(q)) {
    return true;
  }

  final String qDigits = q.replaceAll(RegExp('[^0-9]'), '');
  if (qDigits.isEmpty) return false;
  if (contact.length < 2 || contact[1] is! Map) return false;

  final String qCanon = phoneCanonical62(qDigits);
  for (final dynamic number in (contact[1] as Map).values) {
    final String stored = number.toString().replaceAll(RegExp('[^0-9]'), '');
    if (stored.contains(qDigits)) return true;
    if (qCanon.isNotEmpty && phoneCanonical62(stored).contains(qCanon)) {
      return true;
    }
  }
  return false;
}

class FtzContactPicker extends StatefulWidget {
  final String? label;
  const FtzContactPicker({super.key, this.label = 'Contact'});

  @override
  State<FtzContactPicker> createState() => _FtzContactPickerState();
}

class _FtzContactPickerState extends State<FtzContactPicker> {
  dynamic contacts;
  final _ctrl = ScrollController();
  String _query = '';

  /// Contacts matching [_query] by display name OR by phone number.
  List<dynamic> get _filtered {
    final List<dynamic> all = List<dynamic>.from(contacts ?? const []);
    final String q = _query.trim();
    if (q.isEmpty) return all;
    return all.where((dynamic c) => contactMatchesQuery(c, q)).toList();
  }

  @override
  void initState() {
    super.initState();
    fetchContacts();
  }

  Future<void> fetchContacts() async {
    List<ContactField> fields = ContactField.values.toList();
    dynamic fetchedContacts = await FastContacts.getAllContacts(fields: fields);
    List<dynamic> sortedContact = [];
    for (dynamic contact in fetchedContacts) {
      if (contact.displayName.isNotEmpty) {
        Map<String, String> phones = {};
        for (dynamic phone in contact.phones) {
          phones[phone.label] = phone.number;
        }
        sortedContact.add([contact.displayName, phones]);
      }
    }
    sortedContact.sort(
      (a, b) => a[0].compareTo(b[0]),
    ); // sort descending by timestamp
    setState(() {
      contacts = sortedContact;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (contacts == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final List<dynamic> shown = _filtered;
    return SizedBox(
      width: double.maxFinite,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            autofocus: false,
            decoration: const InputDecoration(
              hintText: 'Cari nama atau nomor',
              prefixIcon: Icon(Icons.search, size: 20),
              isDense: true,
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            onChanged: (String v) => setState(() => _query = v),
          ),
          const SizedBox(height: 8),
          if (shown.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('Kontak tidak ditemukan'),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                controller: _ctrl,
                itemCount: shown.length,
                itemExtent: _ContactItem.height,
                itemBuilder: (_, index) => _ContactItem(contact: shown[index]),
              ),
            ),
        ],
      ),
    );
  } // End of build
} // End of _FtzContactPickerState

class _ContactItem extends StatelessWidget {
  const _ContactItem({required this.contact});

  static const height = 65.0;
  final List<dynamic> contact;

  @override
  Widget build(BuildContext context) {
    final String phones = contact[1].values.join(',');
    final keys = contact[1].keys.toList();
    late String firstPhone;
    try {
      firstPhone = contact[1][keys[0]];
    } catch (e) {
      firstPhone = emptyString;
    }
    return SizedBox(
      height: height,
      child: Card(
        child: ListTile(
          onTap: () async {
            String phone = '';
            if (contact[1].length > 1) {
              phone = await choosePhoneNumber(contact[1]) ?? '';
            } else {
              phone = firstPhone;
            }
            phone = phone
                .replaceAll('-', '')
                .replaceAll(' ', '')
                .replaceAll('+', '');
            phone = phone.startsWith('0')
                ? transactionStore.state.screenTx['#COUNTRY'] +
                      phone.substring(1)
                : phone;
            Get.back(result: phones.isNotEmpty ? phone : null);
          },
          // leading: _ContactImage(contact: contact),
          title: Text(contact[0], maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (phones.isNotEmpty)
                Text(phones, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContactImage extends StatefulWidget {
  const _ContactImage({required this.contact});

  final Contact contact;

  @override
  __ContactImageState createState() => __ContactImageState();
}

class __ContactImageState extends State<_ContactImage> {
  late Future<td.Uint8List?> _imageFuture;

  @override
  void initState() {
    super.initState();
    _imageFuture = FastContacts.getContactImage(widget.contact.id);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<td.Uint8List?>(
      future: _imageFuture,
      builder: (context, snapshot) => SizedBox(
        width: 56,
        height: 56,
        child: snapshot.hasData
            ? Image.memory(snapshot.data!, gaplessPlayback: true)
            : const Icon(Icons.account_box_rounded),
      ),
    );
  }
}

Future<String?> chooseContactAndGetPhoneNumber(String? label) async {
  await Permission.contacts.request();
  dynamic result = await Get.dialog(
    AlertDialog(
      // insetPadding: const EdgeInsets.fromLTRB(12, 40, 12, 20),
      title: Text(label ?? '', textAlign: TextAlign.center),
      // content: Text('Choose a contact to get their phone number'),
      content: FtzContactPicker(label: label ?? ''),
    ),
  );

  // Get.dialog returns null when dismissed via barrier-tap or system-back;
  // `null.isEmpty` threw NoSuchMethodError. Guard at the source so all
  // callers (otq_txf, otq_txf_2, whatsapp_send) are fixed at once.
  if (result == null || result.isEmpty) {
    return null;
  }
  return result; // No contact chosen
}

Future<String?> choosePhoneNumber(dynamic phoneMap) async {
  final phoneController = ScrollController();
  final phoneArray = phoneMap.entries
      .map((entry) => [entry.key, entry.value])
      .toList();
  dynamic result = await Get.dialog(
    AlertDialog(
      // insetPadding: const EdgeInsets.fromLTRB(12, 40, 12, 20),
      // title: Text(
      //   '',
      //   textAlign: TextAlign.center,
      // ),
      // content: Text('Choose a contact to get their phone number'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          controller: phoneController,
          itemCount: phoneArray.length,
          itemExtent: 60,
          itemBuilder: (_, index) => Card(
            child: ListTile(
              onTap: () {
                Get.back(result: phoneArray[index][1]);
              },
              title: Text('${phoneArray[index][0]}: ${phoneArray[index][1]}'),
            ),
          ),
        ),
      ),
    ),
  );

  // Same null-on-dismiss guard as chooseContactAndGetPhoneNumber above.
  if (result == null || result.isEmpty) {
    return null;
  }
  return result; // No contact chosen
}
