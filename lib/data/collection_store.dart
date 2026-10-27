import 'dart:async';
import 'dart:convert';

import 'package:anki_core/anki_core.dart';

import '../storage/file_store.dart';
import 'legacy_import.dart';

/// - **Model**: `view = base + outbox`. `base` is server state at [seq];
///   `outbox` holds ops the server has not acknowledged, in dispatch order.
/// - **Single writer**: every read-modify-write runs on one serial queue, so a
///   pull applied mid-edit can never overwrite the edit.
/// - **Durability**: an op is appended to `outbox.jsonl` before it reaches the
///   view; `base.json` is written before acked ops leave the outbox, so a
///   crash in between only causes a resend the server de-duplicates.
class CollectionStore {
  CollectionStore(
    this._files, {
    required this.scheduler,
    required this._newId,
    this.localCompactAt = 256,
  });

  static const basePath = 'collection/base.json';
  static const outboxPath = 'collection/outbox.jsonl';
  static const statePath = 'collection/state.json';

  final FileStore _files;
  final CardScheduler scheduler;
  final String Function() _newId;

  /// Outbox length at which a never-synced store folds ops into `base`.
  final int localCompactAt;

  final _changes = StreamController<void>.broadcast(sync: true);
  Future<void> _tail = Future.value();

  late Collection _base;
  late Collection _view;
  var _outbox = <Op>[];
  var _seq = 0;
  late String _clientId;
  String? _attachedTo;

  Collection get view => _view;

  int get seq => _seq;

  String get clientId => _clientId;

  /// Sync target (`url|email`) the base and outbox belong to; null until the
  /// first sync.
  String? get attachedTo => _attachedTo;

  int get pendingCount => _outbox.length;

  Stream<void> get changes => _changes.stream;

  Future<void> dispose() => _changes.close();

  Future<T> _serial<T>(Future<T> Function() body) {
    final run = _tail.then((_) => body());
    _tail = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  Future<void> open() => _serial(() async {
    final state = await _readJson(statePath);
    _attachedTo = state?['attachedTo'] as String?;
    if (state?['clientId'] case final String id) {
      _clientId = id;
    } else {
      _clientId = _newId();
      await _writeState();
    }
    final base = await _readJson(basePath);
    if (base != null) {
      _seq = base['seq'] as int;
      _base = Collection.fromJson(
        base['collection'] as Map<String, dynamic>,
        scheduler: scheduler,
      );
    } else {
      _seq = 0;
      _base =
          await importLegacy(_files, scheduler) ??
          Collection(scheduler: scheduler);
      if (!_base.isPristine) await _writeBase();
    }
    _outbox = await _readOutbox();
    _rebuild();
  });

  Future<void> dispatch(Op op) => dispatchAll([op]);

  Future<void> dispatchAll(List<Op> ops) => _serial(() async {
    for (final op in ops) {
      await _files.append(outboxPath, jsonEncode(op.toJson()));
      _outbox.add(op);
      _view.apply(op);
    }
    if (_attachedTo == null && _outbox.length >= localCompactAt) {
      _base = _view.copy();
      await _writeBase();
      await _writeOutbox(const []);
      _outbox = [];
    }
    _changes.add(null);
  });

  Future<List<Op>> pending(int limit) =>
      _serial(() async => _outbox.take(limit).toList());

  /// Re-targets the store at a different sync target: the current view is
  /// exported as ops for that server and the cursor restarts at 0.
  Future<void> rebind(String key) => _serial(() async {
    final exported = _view.export(_newId);
    await _writeOutbox(exported);
    _outbox = exported;
    _base = Collection(scheduler: scheduler);
    _seq = 0;
    await _writeBase();
    _attachedTo = key;
    await _writeState();
    _rebuild();
    _changes.add(null);
  });

  Future<void> applySnapshot(CollectionSnapshot snapshot) => _serial(() async {
    _base = snapshot.collection.rescheduled(scheduler);
    _seq = snapshot.seq;
    await _writeBase();
    _rebuild();
    _changes.add(null);
  });

  Future<void> applyPull(SyncPull pull) => _serial(() async {
    final fresh = [
      for (final s in pull.ops)
        if (s.seq > _seq) s,
    ];
    if (fresh.isNotEmpty) {
      final next = _base.copy();
      for (final s in fresh) {
        next.apply(s.op);
      }
      _base = next;
      _seq = fresh.last.seq;
      await _writeBase();
    }
    final acked = pull.acked.toSet();
    final remaining = [
      for (final op in _outbox)
        if (!acked.contains(op.id)) op,
    ];
    if (remaining.length != _outbox.length) {
      await _writeOutbox(remaining);
      _outbox = remaining;
    }
    if (fresh.isEmpty && acked.isEmpty) return;
    _rebuild();
    _changes.add(null);
  });

  void _rebuild() {
    final view = _base.copy();
    for (final op in _outbox) {
      view.apply(op);
    }
    _view = view;
  }

  Future<Map<String, dynamic>?> _readJson(String path) async {
    final raw = await _files.read(path);
    return raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
  }

  /// A crash mid-append can leave a torn last line; it never reached the
  /// view, so it is dropped.
  Future<List<Op>> _readOutbox() async {
    final raw = await _files.read(outboxPath);
    if (raw == null) return [];
    final ops = <Op>[];
    for (final line in const LineSplitter().convert(raw)) {
      if (line.trim().isEmpty) continue;
      try {
        ops.add(Op.fromJson(jsonDecode(line) as Map<String, dynamic>));
      } on FormatException {
        continue;
      }
    }
    return ops;
  }

  Future<void> _writeBase() => _files.write(
    basePath,
    jsonEncode({'seq': _seq, 'collection': _base.toJson()}),
  );

  Future<void> _writeOutbox(List<Op> ops) => _files.write(
    outboxPath,
    ops.map((op) => '${jsonEncode(op.toJson())}\n').join(),
  );

  Future<void> _writeState() => _files.write(
    statePath,
    jsonEncode({'clientId': _clientId, 'attachedTo': ?_attachedTo}),
  );
}
