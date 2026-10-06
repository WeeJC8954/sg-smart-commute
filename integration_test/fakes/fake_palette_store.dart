import 'dart:async';

import 'package:sg_smart_commute/features/appearance/domain/palette_store.dart';

/// The palette store in memory. [failRead] / [failWrite] make those calls
/// throw; with [pendingRead] a read waits for that completer (never
/// completed: a hang; completed later: a late result).
class FakePaletteStore implements PaletteStore {
  FakePaletteStore({
    this.stored,
    this.failRead = false,
    this.failWrite = false,
    this.pendingRead,
  });

  String? stored;
  bool failRead;
  bool failWrite;
  Completer<String?>? pendingRead;
  int reads = 0;
  final List<String> writes = [];

  @override
  Future<String?> read() async {
    reads++;
    if (pendingRead case final pending?) return pending.future;
    if (failRead) throw StateError('read failed (fake)');
    return stored;
  }

  @override
  Future<void> write(String id) async {
    if (failWrite) throw StateError('write failed (fake)');
    writes.add(id);
    stored = id;
  }
}
