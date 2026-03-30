import 'dart:async';

import 'package:metricestan/collector.dart';
import 'package:metricestan/metric.dart';
import 'package:mongo_dart/mongo_dart.dart';

class MongoDb implements Collector {
  final String _mongoUrl;
  final String _userName;
  final String _password;
  final String? _dbName;
  final String? _authSource;
  final String? _replicaSet;
  final String? _readPreference;
  final bool? _retryWrites;
  final String? _w;
  final Duration _collectionDuration;
  late final Db _db;
  Timer? _collectionTimer;

  MongoDb({
    required int collectionDuration,
    required String mongoUrl,
    required String userName,
    required String password,
    String? dbName,
    String? authSource,
    String? replicaSet,
    String? readPreference,
    bool? retryWrites,
    String? w,
  })  : _mongoUrl = mongoUrl,
        _userName = userName,
        _password = password,
        _dbName = dbName,
        _authSource = authSource,
        _replicaSet = replicaSet,
        _readPreference = readPreference,
        _retryWrites = retryWrites,
        _w = w,
        _collectionDuration = Duration(seconds: collectionDuration);

  @override
  Future<List<Metric>> collect() async {
    await _connect();
    return await _getServerStatusMetrics();
  }

  Future<List<Metric>> _getServerStatusMetrics() async {
    final serverStatusResult = await ServerStatusCommand(_db).executeDocument();
    return [
      if (serverStatusResult.uptime != null)
        Metric(
          name: 'mongodb.uptime_seconds',
          value: serverStatusResult.uptime!,
          type: MetricType.gauge,
          attributes: {'db': _dbName},
        ),
      if (serverStatusResult.connections != null) ...[
        Metric(
          name: 'mongodb.connections.current',
          value: serverStatusResult.connections!['current'] ?? 0,
          type: MetricType.gauge,
          attributes: {'db': _dbName},
        ),
        Metric(
          name: 'mongodb.connections.available',
          value: serverStatusResult.connections!['available'] ?? 0,
          type: MetricType.gauge,
          attributes: {'db': _dbName},
        ),
        Metric(
          name: 'mongodb.connections.totalCreated',
          value: serverStatusResult.connections!['totalCreated'] ?? 0,
          type: MetricType.gauge,
          attributes: {'db': _dbName},
        ),
        Metric(
          name: 'mongodb.connections.active',
          value: serverStatusResult.connections!['active'] ?? 0,
          type: MetricType.gauge,
          attributes: {'db': _dbName},
        ),
        Metric(
          name: 'mongodb.connections.exhaustIsMaster',
          value: serverStatusResult.connections!['exhaustIsMaster'] ?? 0,
          type: MetricType.gauge,
          attributes: {'db': _dbName},
        ),
        Metric(
          name: 'mongodb.connections.awaitingTopologyChanges',
          value:
              serverStatusResult.connections!['awaitingTopologyChanges'] ?? 0,
          type: MetricType.gauge,
          attributes: {'db': _dbName},
        ),
      ],
      if (serverStatusResult.opcounters != null) ...[
        Metric(
          name: 'mongodb.opcounters.insert',
          value: serverStatusResult.opcounters!['insert'] ?? 0,
          type: MetricType.gauge,
          attributes: {'db': _dbName},
        ),
        Metric(
          name: 'mongodb.opcounters.query',
          value: serverStatusResult.opcounters!['query'] ?? 0,
          type: MetricType.gauge,
          attributes: {'db': _dbName},
        ),
        Metric(
          name: 'mongodb.opcounters.update',
          value: serverStatusResult.opcounters!['update'] ?? 0,
          type: MetricType.gauge,
          attributes: {'db': _dbName},
        ),
        Metric(
          name: 'mongodb.opcounters.delete',
          value: serverStatusResult.opcounters!['delete'] ?? 0,
          type: MetricType.gauge,
          attributes: {'db': _dbName},
        ),
        Metric(
          name: 'mongodb.opcounters.command',
          value: serverStatusResult.opcounters!['command'] ?? 0,
          type: MetricType.gauge,
          attributes: {'db': _dbName},
        ),
        Metric(
          name: 'mongodb.opcounters.getmore',
          value: serverStatusResult.opcounters!['getmore'] ?? 0,
          type: MetricType.gauge,
          attributes: {'db': _dbName},
        ),
      ],
    ];
  }

  Future<void> _connect() async {
    _db = await MongoDbConnection.connection(
      mongoUrl: _mongoUrl,
      userName: _userName,
      password: _password,
      dbName: _dbName,
      authSource: _authSource,
      replicaSet: _replicaSet,
      readPreference: _readPreference,
      retryWrites: _retryWrites,
      w: _w,
    );
  }

  @override
  Timer? get collectionTimer => _collectionTimer;

  @override
  void setupCollectionTimer(Function onCollect) {
    _collectionTimer = Timer.periodic(_collectionDuration, (_) => onCollect());
  }
}

class MongoDbConnection {
  static Future<Db> connection({
    required String mongoUrl,
    required String userName,
    required String password,
    String? dbName,
    String? authSource,
    String? replicaSet,
    String? readPreference,
    bool? retryWrites,
    String? w,
  }) async {
    final connectionString = _composeMongoUri(
      mongoUrl: mongoUrl,
      userName: userName,
      password: password,
      dbName: dbName,
      authSource: authSource,
      replicaSet: replicaSet,
      readPreference: readPreference,
      retryWrites: retryWrites,
      w: w,
    );

    final db = await Db.create(connectionString);
    await db.open();
    await db.pingCommand();
    return db;
  }

  static String _composeMongoUri({
    required String mongoUrl,
    required String userName,
    required String password,
    String? dbName,
    String? authSource,
    String? replicaSet,
    String? readPreference,
    bool? retryWrites,
    String? w,
  }) {
    final encUser = Uri.encodeComponent(userName);
    final encPass = Uri.encodeComponent(password);
    List<String> options = [];
    if (authSource != null) {
      options.add('authSource=${Uri.encodeQueryComponent(authSource)}');
    }
    if (replicaSet != null) {
      options.add('replicaSet=${Uri.encodeComponent(replicaSet)}');
    }
    if (readPreference != null) {
      options.add('readPreference=${Uri.encodeComponent(readPreference)}');
    }
    if (retryWrites != null) {
      options.add('retryWrites=$retryWrites');
    }
    if (w != null) {
      options.add('w=${Uri.encodeComponent(w)}');
    }
    final dbPart = dbName != null ? '/$dbName' : '';
    final optionsPart = options.isNotEmpty ? '?${options.join('&')}' : '';
    return 'mongodb://$encUser:$encPass@$mongoUrl$dbPart$optionsPart';
  }
}
