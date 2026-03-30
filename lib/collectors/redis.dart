import 'dart:async';

import 'package:metricestan/collector.dart';
import 'package:metricestan/log.dart';
import 'package:metricestan/metric.dart';
import 'package:redis/redis.dart' as redis;

class Redis implements Collector {
  final RedisConnection _redis;
  final Duration _collectionDuration;
  final Logger _logger;
  final Set<String> _streamKeys;
  final Set<String> _sortedSetKeys;
  redis.Command? _command;
  Timer? _collectionTimer;

  Redis({
    required int collectionDuration,
    required String hostname,
    required int port,
    bool tlsEnabled = false,
    String? password,
    Set<String>? streamKeys,
    Set<String>? sortedSetKeys,
    required Logger logger,
  })  : _logger = logger,
        _streamKeys = streamKeys ?? {},
        _sortedSetKeys = sortedSetKeys ?? {},
        _collectionDuration = Duration(seconds: collectionDuration),
        _redis = RedisConnection(
          hostname,
          port,
          tlsEnabled,
          password,
          logger,
        );

  Future<void> _connect() async {
    try {
      _command = await _redis.connect();
    } catch (error, stackTrace) {
      _logger.error(
        'Error connecting to Redis',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  @override
  Future<List<Metric>> collect() async {
    await _connect();

    final results = await Future.wait(
      [
        ..._streamKeys.map(_getStreamLength),
        ..._sortedSetKeys.map(_getSortedSetLength),
      ],
      eagerError: false,
    );
    return [
      for (var result in results) ...result,
    ];
  }

  Future<List<Metric>> _getStreamLength(String streamKey) async {
    try {
      final count = await _command!.send_object(['XLEN', streamKey]) as num?;
      if (count != null) {
        return [
          Metric(
            name: 'redis.stream.length',
            value: count,
            type: MetricType.gauge,
            attributes: {'stream': streamKey},
          ),
        ];
      }
    } catch (error, stackTrace) {
      _logger.error(
        'Error retrieving redis stream length.',
        context: {'streamKey': streamKey},
        error: error,
        stackTrace: stackTrace,
      );
    }
    return [];
  }

  Future<List<Metric>> _getSortedSetLength(String sortedSetKey) async {
    try {
      final count = await _command!.send_object(['ZCARD', sortedSetKey]) as num?;
      if (count != null) {
        return [
          Metric(
            name: 'redis.sorted_set.length',
            value: count,
            type: MetricType.gauge,
            attributes: {'sorted_set': sortedSetKey},
          ),
        ];
      }
    } catch (error, stackTrace) {
      _logger.error(
        'Error retrieving redis sorted set length.',
        context: {'sortedSetKey': sortedSetKey},
        error: error,
        stackTrace: stackTrace,
      );
    }
    return [];
  }

  @override
  Timer? get collectionTimer => _collectionTimer;

  @override
  void setupCollectionTimer(Function onCollect) {
    _collectionTimer = Timer.periodic(_collectionDuration, (_) => onCollect());
  }
}

class RedisConnection {
  redis.Command? _command;
  final String _host;
  final bool _tlsEnabled;
  final int _port;
  final String? _password;
  final Logger logger;

  RedisConnection(
    this._host,
    this._port,
    this._tlsEnabled,
    this._password,
    this.logger,
  );

  Future<redis.Command> connect() async {
    if (_command != null) {
      return _command!;
    }
    if (_tlsEnabled) {
      _command = await redis.RedisConnection().connectSecure(_host, _port);
    } else {
      _command = await redis.RedisConnection().connect(_host, _port);
    }
    if (_password != null && _password.isNotEmpty) {
      await _command!.send_object(['AUTH', _password]);
    }
    return _command!;
  }

  Future<void> close() async {
    await _command?.get_connection().close();
    _command = null;
  }
}
