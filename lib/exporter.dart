import 'dart:async';

import 'package:metricestan/metric.dart';

abstract class Exporter {
  void record(List<Metric> metrics);
  Future<void> flush();
  Timer? get flushTimer;
  void setupFlushTimer(Function onFlush);
}
