import 'dart:convert';

class Log {
  final LogSeverity level;
  final String message;
  final DateTime timestamp;
  final Map<String, dynamic>? context;
  final List<String>? stackTrace;

  Log({
    required this.level,
    required this.message,
    required this.timestamp,
    this.context,
    this.stackTrace,
  });

  Map<String, dynamic> toMap() {
    return {
      'level': level.value,
      'level_name': level.name,
      'message': message,
      'timestamp': timestamp.toIso8601String(),
      'context': context,
      'stackTrace': stackTrace,
    };
  }
}

class Logger {
  final LogWriter writer;

  Logger({required this.writer});

  Future<void> flush() async {
    await writer.flush();
  }

  void log(
    LogSeverity level,
    String message,
    Map<String, dynamic>? context, {
    Object? error,
    StackTrace? stackTrace,
    DateTime? timestamp,
  }) {
    if (error != null) {
      context = {...?context, 'error': error.toString()};
    }
    Log log = Log(
      level: level,
      message: message,
      timestamp: timestamp ?? DateTime.now().toUtc(),
      context: context,
      stackTrace: stackTrace
          ?.toString()
          .split('\n')
          .map((line) => line.trim())
          .toList(),
    );
    writer.write(log);
  }

  StackTrace? get stackTrace {
    return StackTrace.current;
  }

  void emergency(String message,
      {Map<String, dynamic>? context, Object? error, StackTrace? stackTrace}) {
    log(LogSeverity.emergency, message, context,
        error: error, stackTrace: stackTrace ?? this.stackTrace);
  }

  void alert(String message,
      {Map<String, dynamic>? context, Object? error, StackTrace? stackTrace}) {
    log(LogSeverity.alert, message, context,
        error: error, stackTrace: stackTrace ?? this.stackTrace);
  }

  void critical(String message,
      {Map<String, dynamic>? context, Object? error, StackTrace? stackTrace}) {
    log(LogSeverity.critical, message, context,
        error: error, stackTrace: stackTrace ?? this.stackTrace);
  }

  void error(String message,
      {Map<String, dynamic>? context, Object? error, StackTrace? stackTrace}) {
    log(LogSeverity.error, message, context,
        error: error, stackTrace: stackTrace ?? this.stackTrace);
  }

  void warning(String message,
      {Map<String, dynamic>? context, Object? error, StackTrace? stackTrace}) {
    log(LogSeverity.warning, message, context,
        error: error, stackTrace: stackTrace ?? this.stackTrace);
  }

  void notice(String message,
      {Map<String, dynamic>? context, Object? error, StackTrace? stackTrace}) {
    log(LogSeverity.notice, message, context,
        error: error, stackTrace: stackTrace ?? this.stackTrace);
  }

  void info(String message,
      {Map<String, dynamic>? context, Object? error, StackTrace? stackTrace}) {
    log(LogSeverity.info, message, context,
        error: error, stackTrace: stackTrace);
  }

  void debug(String message,
      {Map<String, dynamic>? context, Object? error, StackTrace? stackTrace}) {
    log(LogSeverity.debug, message, context,
        error: error, stackTrace: stackTrace);
  }
}

abstract class LogWriter {
  Future<void> write(Log log);
  Future<void> flush();
  Future<void> destroy();
}

enum LogSeverity {
  emergency(0),
  alert(1),
  critical(2),
  error(3),
  warning(4),
  notice(5),
  info(6),
  debug(7);

  final int value;

  const LogSeverity(this.value);

  static LogSeverity fromValue(int value) {
    return LogSeverity.values.firstWhere(
      (severity) => severity.value == value,
      orElse: () => LogSeverity.info,
    );
  }
}

class StdoutLogWriter implements LogWriter {
  @override
  Future<void> write(Log log) async {
    print(jsonEncode(log.toMap()));
  }

  @override
  Future<void> flush() async {
    return;
  }

  @override
  Future<void> destroy() async {}
}
