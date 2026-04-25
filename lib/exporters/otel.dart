import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:metricestan/exporter.dart';
import 'package:metricestan/log.dart';
import 'package:metricestan/metric.dart';

class OTel implements Exporter {
  static const int _aggregationTemporalityCumulative = 2;

  final Duration _flushInterval;
  final String _endpoint;
  final Map<String, String>? _headers;
  final List<Map<String, dynamic>> _resourceAttrs;
  final List<Metric> _buffer = [];
  final Logger logger;
  Timer? _flushTimer;

  OTel({
    required int flushIntervalSeconds,
    required this.logger,
    required String endpoint,
    Map<String, String>? headers,
    required String serviceName,
    Map<String, dynamic>? resourceAttributes,
  })  : _flushInterval = Duration(seconds: flushIntervalSeconds),
        _endpoint = endpoint,
        _headers = headers,
        _resourceAttrs = [
          _toOtelAttr('service.name', serviceName),
          ...?(resourceAttributes?.entries
              .map((e) => _toOtelAttr(e.key, e.value))),
        ];

  @override
  void record(List<Metric> metrics) {
    _buffer.addAll(metrics);
  }

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
          '[OTel] Failed to flush ${metrics.length} metrics, dropping batch',
          error: error,
          stackTrace: stackTrace,
        );
        return;
      }
      _buffer.insertAll(0, metrics);

      logger.error(
        '[OTel] Error flushing metrics',
        error: error,
        stackTrace: stackTrace,
        context: {'metricsCount': metrics.length},
      );
    }
  }

  Future<void> _send(List<Metric> metrics) async {
    final otelMetrics = metrics.map(_toOtelMetric).toList();

    final payload = jsonEncode({
      'resourceMetrics': [
        {
          'resource': {'attributes': _resourceAttrs},
          'scopeMetrics': [
            {
              'scope': {'name': 'metricestan'},
              'metrics': otelMetrics,
            }
          ],
        }
      ]
    });

    final response = await http
        .post(
          Uri.parse(_endpoint),
          headers: {'Content-Type': 'application/json', ...?_headers},
          body: payload,
        )
        .timeout(_flushInterval);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
          'Failed to send metrics: ${response.statusCode} ${response.body}');
    }
  }

  Map<String, dynamic> _toOtelMetric(Metric metric) {
    final timeUnixNano = (metric.timestamp * 1e9).toInt().toString();
    final attrs = metric.attributes.entries
        .map((e) => _toOtelAttr(e.key, e.value))
        .toList();

    final dataPoint = {
      'asDouble': metric.value.toDouble(),
      'timeUnixNano': timeUnixNano,
      'attributes': attrs,
    };

    if (metric.type == MetricType.gauge) {
      return {
        'name': metric.name,
        'gauge': {'dataPoints': [dataPoint]},
      };
    } else {
      // count and summary map to a monotonic sum
      return {
        'name': metric.name,
        'sum': {
          'dataPoints': [dataPoint],
          'aggregationTemporality': _aggregationTemporalityCumulative,
          'isMonotonic': true,
        },
      };
    }
  }

  static Map<String, dynamic> _toOtelAttr(String key, dynamic value) => {
        'key': key,
        'value': {'stringValue': value.toString()},
      };

  @override
  Timer? get flushTimer => _flushTimer;

  @override
  void setupFlushTimer(Function onFlush) {
    _flushTimer = Timer.periodic(_flushInterval, (_) => onFlush());
  }
}
