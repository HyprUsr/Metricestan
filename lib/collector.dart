import 'dart:async';

import 'package:metricestan/metric.dart';

abstract class Collector {
  Future<List<Metric>> collect();
  Timer? get collectionTimer;
  void setupCollectionTimer(Function onCollect);
}