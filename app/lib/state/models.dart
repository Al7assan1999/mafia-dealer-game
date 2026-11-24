
/// Another account as the server shows it (never an email).
class Person {
  Person(this.j);
  final Map<String, Object?> j;
  String get id => j['id'] as String;
  String? get handle => j['handle'] as String?;
  String get display => j['display'] as String;
  int? get preset => (j['avatar'] as Map?)?['preset'] as int?;
  int? get photo => (j['avatar'] as Map?)?['photo'] as int?;
  String get fav => (j['fav'] as String?) ?? '';
  String get rel => (j['rel'] as String?) ?? 'none';
  bool get online => j['on'] == true;
  String get status => (j['st'] as String?) ?? '';
  int get roomSize => (j['n'] as num?)?.toInt() ?? 0; // P3: players in their room
}

class Note {
  Note(this.j);
  final Map<String, Object?> j;
  String get id => j['id'] as String;
  String get kind => j['kind'] as String;
  Person get from => Person(Map<String, Object?>.from(j['from'] as Map));
  int get at => j['at'] as int;
  String? get code => j['code'] as String?;
  bool get read => j['read'] == true;
  /// Handled (kept 24 h, read-only): joined / let_in / accepted / declined / dismissed / expired; null while it waits.
  String? get result => j['result'] as String?;
  /// wifi_confirm / wifi_result: {request, status, reason, players, winner, playedAt, seat, role}
  Map<String, Object?>? get wifi => j['wifi'] == null ? null : Map<String, Object?>.from(j['wifi'] as Map);
}
