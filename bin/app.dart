import 'dart:async';
import 'dart:io';

import 'package:dotenv/dotenv.dart';
import 'package:metricestan/collector.dart';
import 'package:metricestan/collectors/mongodb.dart';
import 'package:metricestan/collectors/redis.dart' as collector;
import 'package:metricestan/exporter.dart';
import 'package:metricestan/exporters/new_relic.dart';
import 'package:metricestan/log.dart';

Future<void> main() async {
  final logger = Logger(
    writer: StdoutLogWriter(),
  );

  final env = DotEnv(includePlatformEnvironment: true);
  if (File('.env').existsSync()) {
    env.load();
  } else {
    logger.warning('.env file not found, relying on platform env variables');
  }

  await runZonedGuarded(() async {
    List<Exporter> exporters = [];
    if (env['EXPORTER_NEW_RELIC_ENABLED'] == 'true') {
      final newRelicExporter = _createNewRelicExporter(env, logger);
      _setupExportTimer(newRelicExporter, logger);
      exporters.add(newRelicExporter);
    }

    List<Collector> collectors = [];
    if (env['COLLECTOR_REDIS_ENABLED'] == 'true') {
      final redisCollector = _createRedisCollector(env, logger);
      _setupCollectionTimer(redisCollector, exporters, logger);
      collectors.add(redisCollector);
    }
    if (env['COLLECTOR_MONGODB_ENABLED'] == 'true') {
      final mongoDbCollector = MongoDb(
        collectionDuration: int.tryParse(
              env['COLLECTOR_MONGODB_PERIODICITY_SECONDS'] ?? '60',
            ) ??
            60,
        mongoUrl: env['COLLECTOR_MONGODB_URL'] ?? 'mongodb://localhost:27017',
        userName: env['COLLECTOR_MONGODB_USERNAME'] ?? '',
        password: env['COLLECTOR_MONGODB_PASSWORD'] ?? '',
        authSource: env['COLLECTOR_MONGODB_AUTH_SOURCE'],
      );
      _setupCollectionTimer(mongoDbCollector, exporters, logger);
      collectors.add(mongoDbCollector);
    }

    ProcessSignal.sigterm.watch().listen((_) async {
      logger.info('🛑 SIGTERM shutting down main.');
      await _shutdown(collectors, exporters);
      exit(0);
    });
    ProcessSignal.sigint.watch().listen((_) async {
      logger.info('🛑 SIGINT shutting down main.');
      await _shutdown(collectors, exporters);
      exit(0);
    });

    // Keep the main isolate alive indefinitely
    await Completer<void>().future;
  }, (error, stackTrace) {
    logger.error(
      'Unhandled error in main zone',
      error: error,
      stackTrace: stackTrace,
    );
  });
}

Future<void> _shutdown(
    List<Collector> collectors, List<Exporter> exporters) async {
  for (var collector in collectors) {
    collector.collectionTimer?.cancel();
  }
  for (var exporter in exporters) {
    await exporter.flush();
    exporter.flushTimer?.cancel();
  }
}

void _setupExportTimer(Exporter exporter, Logger logger) {
  exporter.setupFlushTimer(() async {
    try {
      await exporter.flush();
      logger.log(
        LogSeverity.info,
        'Flushed metrics to ${exporter.runtimeType}',
        null,
      );
    } catch (error, stackTrace) {
      logger.error(
        'Error flushing metrics to ${exporter.runtimeType}',
        error: error,
        stackTrace: stackTrace,
      );
    }
  });
}

NewRelic _createNewRelicExporter(DotEnv env, Logger logger) {
  return NewRelic(
    flushIntervalSeconds: int.tryParse(
          env['EXPORTER_NEW_RELIC_PERIODICITY_SECONDS'] ?? '60',
        ) ??
        60,
    endpoint: env['EXPORTER_NEW_RELIC_ENDPOINT'] ??
        'https://metric-api.newrelic.com/metric/v1',
    licenseKey: env['EXPORTER_NEW_RELIC_LICENSE_KEY'] ?? '',
    commonAttributes: {
      'service.name': env['SERVICE_NAME'] ?? 'metricestan',
      'service.version': env['SERVICE_VERSION'] ?? 'unknown',
    },
    logger: logger,
  );
}

void _setupCollectionTimer(
  Collector collector,
  List<Exporter> exporters,
  Logger logger,
) {
  collector.setupCollectionTimer(
    () async {
      try {
        final metrics = await collector.collect();
        for (var exporter in exporters) {
          exporter.record(metrics);
        }
        logger.log(
          LogSeverity.info,
          'Collected ${metrics.length} metrics from ${collector.runtimeType}',
          null,
        );
      } catch (error, stackTrace) {
        logger.error(
          'Error collecting metrics from ${collector.runtimeType}',
          error: error,
          stackTrace: stackTrace,
        );
      }
    },
  );
}

collector.Redis _createRedisCollector(DotEnv env, Logger logger) {
  return collector.Redis(
    collectionDuration: int.tryParse(
          env['COLLECTOR_REDIS_PERIODICITY_SECONDS'] ?? '60',
        ) ??
        60,
    hostname: env['COLLECTOR_REDIS_HOST'] ?? 'localhost',
    port: int.tryParse(env['COLLECTOR_REDIS_PORT'] ?? '6379') ?? 6379,
    tlsEnabled: env['COLLECTOR_REDIS_TLS_ENABLED'] == 'true',
    password: env['COLLECTOR_REDIS_PASSWORD'],
    streamKeys: (env['COLLECTOR_REDIS_STREAM_KEYS'] ?? '')
        .split(',')
        .where((key) => key.isNotEmpty)
        .toSet(),
    sortedSetKeys: (env['COLLECTOR_REDIS_SORTED_SET_KEYS'] ?? '')
        .split(',')
        .where((key) => key.isNotEmpty)
        .toSet(),
    logger: logger,
  );
}
