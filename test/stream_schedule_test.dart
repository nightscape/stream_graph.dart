import 'dart:async';

import 'package:rxdart/rxdart.dart';
import 'package:stream_graph/schedule.dart';
import 'package:stream_graph/stream_schedule.dart';
import 'package:test/test.dart';
import 'dart:mirrors';

import 'absolute_time_interval.dart';

typedef Output = int;
typedef Input = int;
void main() {
  Duration afterSeconds(int seconds) =>
      Duration(milliseconds: seconds * 1000 ~/ speedup);
  Duration forSeconds(int seconds) =>
      Duration(milliseconds: seconds * 1000 ~/ speedup);
  Stream<int> startStream() => TimerStream(0, afterSeconds(100));
  final session = [
    Schedule.emit<int>(1, afterSeconds(200), after: 0),
    Schedule.emit<int>(2, afterSeconds(300), after: 1),
    Schedule.emit<int>(3, afterSeconds(400), after: 2),
  ];
  group("StreamSchedule", () {
    test('Converts Schedules into a correctly timed Stream of elements',
        () async {
      final outputStream = startStream()
          .asyncMapMultipleRecursive(session)
          .absoluteTimeInterval();
      expect(
          outputStream,
          emitsRoughlyAfterSeconds([
            MapEntry(100, 0),
            MapEntry(300, 1),
            MapEntry(600, 2),
            MapEntry(1000, 3),
          ]));
    });
    test(
        'Converts Schedules into a correctly timed Stream of elements, even with breaks',
        () async {
      final elementStreamController = StreamController<Output>();
      final subscription = startStream()
          .asyncMapMultipleRecursive(session)
          .listen((event) => elementStreamController.add(event));
      subscription.pause();
      final outputStream =
          elementStreamController.stream.absoluteTimeInterval();
      final outputList = outputStream.toList();
      subscription.resume();
      await Future.delayed(forSeconds(200), subscription.pause);
      await Future.delayed(forSeconds(900), subscription.resume);
      await Future.delayed(forSeconds(900), subscription.cancel);
      elementStreamController.close();
      expect(
          outputList,
          completion(orderedEquals([
            afterRoughlyMillis<Output>(100, 0),
            afterRoughlyMillis<Output>(1100, 1),
            afterRoughlyMillis<Output>(1400, 2),
            afterRoughlyMillis<Output>(1800, 3),
          ])));
    });
  });
}
