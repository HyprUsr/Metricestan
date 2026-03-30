enum MetricType { gauge, count, summary }

class Metric {
  final String name;
  final MetricType type;
  final num value;
  final Map<String, dynamic> attributes;
  final int timestamp;

  Metric({
    required this.name,
    required this.type,
    required this.value,
    Map<String, dynamic>? attributes,
  })  : timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000,
        attributes = attributes ?? {};

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type.name,
        'value': value,
        'timestamp': timestamp,
        'attributes': attributes,
      };
}
