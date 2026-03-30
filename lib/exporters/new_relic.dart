import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:metricestan/exporter.dart';
import 'package:metricestan/log.dart';
import 'package:metricestan/metric.dart';

class NewRelic implements Exporter {
  final Duration _flushInterval;
  final String _endpoint;
  final String _licenseKey;
  final Map<String, dynamic> _commonAttributes;
  final List<Metric> _buffer = [];
  final Logger logger;
  Timer? _flushTimer;

  NewRelic({
    required int flushIntervalSeconds,
    required this.logger,
    required String endpoint,
    required String licenseKey,
    Map<String, dynamic>? commonAttributes,
  })  : _flushInterval = Duration(seconds: flushIntervalSeconds),
        _licenseKey = licenseKey,
        _endpoint = endpoint,
        _commonAttributes = commonAttributes ?? {};

  /// Buffer a metric (send in batches for efficiency)
  @override
  void record(List<Metric> metrics) {
    _buffer.addAll(metrics);
  }

  /// Send all buffered metrics
  @override
  Future<void> flush() async {
    if (_buffer.isEmpty) return;

    final metrics = List<Metric>.from(_buffer);
    _buffer.clear();

    try {
      await _send(metrics);
    } catch (error, stackTrace) {
      if (metrics.length > 200) {
        logger.error(
          '[NewRelic] Failed to flush ${metrics.length} metrics, dropping batch',
          error: error,
          stackTrace: stackTrace,
        );
        return; // Drop batch if too large to avoid memory issues
      }
      _buffer.insertAll(0, metrics); // Re-buffer on failure

      logger.error(
        '[NewRelic] Error flushing metrics',
        error: error,
        stackTrace: stackTrace,
        context: {
          'metricsCount': metrics.length,
        },
      );
    }
  }

  Future<void> _send(List<Metric> metrics) async {
    final payload = jsonEncode([
      {
        'common': {'attributes': _commonAttributes},
        'metrics': metrics.map((m) => m.toJson()).toList(),
      }
    ]);

    final response = await http
        .post(
          Uri.parse(_endpoint),
          headers: {
            'api-key': _licenseKey,
            'Content-Type': 'application/json',
          },
          body: payload,
        )
        .timeout(_flushInterval);

    if (response.statusCode != 202) {
      throw Exception(
          'Failed to send metrics: ${response.statusCode} ${response.body}');
    }
  }

  @override
  Timer? get flushTimer => _flushTimer;

  @override
  void setupFlushTimer(Function onFlush) {
    _flushTimer = Timer.periodic(_flushInterval, (_) => onFlush());
  }
}
