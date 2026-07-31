// Collanium 2019
//   Oct 25, 2019 HS

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

class NotificationEntity extends Equatable {
  final String vid; // vid, documentId
  final int urd; // # of unread messages of this vid (urd)
  final String lm; // last message to display in notification list (lm)
  final int lt; // time of last message in unix milli second (lt)
  final String nm; // name of vid displayed (nm)
  final String pp; // url to profilePicture (pp)
  final int la; // time of last read (la)

  // NotificationEntity();
  @override
  List<Object> get props => [];

  const NotificationEntity(
    this.vid,
    this.urd,
    this.lm,
    this.lt,
    this.nm,
    this.pp,
    this.la,
  );

  Map<String, Object> toJson() {
    return {
      "vid": vid,
      "urd": urd,
      "lm": lm,
      "lt": lt,
      "nm": nm,
      "pp": pp,
      "la": la,
    };
  }

  @override
  String toString() {
    return 'NotificationEntity{vid: $vid, urd: $urd, lm: $lm, lt: $lt, nm: $nm, pp: $pp, la: $la}';
  }

  static NotificationEntity fromJson(Map<String, Object> json) {
    return NotificationEntity(
      json["vid"] as String,
      json["urd"] as int,
      json["lm"] as String,
      json["lt"] as int,
      json["nm"] as String,
      json["pp"] as String,
      json["la"] as int,
    );
  }

  // `snap.get(field)` THROWS StateError when the field is absent, and this runs
  // inside the inbox stream's .map() -- one thread doc written without a `pp`
  // or `urd` (server CF, or a half-applied offline write) killed the whole
  // stream, so the inbox rendered "no notifications" forever. Read tolerantly:
  // orderBy('lt') is the only field the query itself guarantees.
  static NotificationEntity fromSnapshot(DocumentSnapshot snap) {
    final data = snap.data();
    final m = data is Map<String, dynamic> ? data : const <String, dynamic>{};
    int asInt(dynamic v) => v is int ? v : (v is num ? v.toInt() : 0);
    String asStr(dynamic v) => v == null ? '' : v.toString();
    return NotificationEntity(
      snap.id,
      asInt(m['urd']),
      asStr(m['lm']),
      asInt(m['lt']),
      asStr(m['nm']),
      asStr(m['pp']),
      asInt(m['la']),
    );
  }

  Map<String, Object> toDocument() {
    return {"urd": urd, "lm": lm, "lt": lt, "nm": nm, "pp": pp, "la": la};
  }
}
