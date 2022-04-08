import 'dart:async';

import 'package:rxdart/rxdart.dart';
import 'package:stream_graph/schedule.dart';
import 'package:stream_graph/stream_schedule.dart';
import 'package:test/test.dart';

import 'absolute_time_interval.dart';

void main() {
  Duration afterSeconds(int seconds) =>
      Duration(milliseconds: seconds * 1000 ~/ speedup);
  Duration forSeconds(int seconds) =>
      Duration(milliseconds: seconds * 1000 ~/ speedup);
  Stream<Lifecycle<int>> startStream() =>
      TimerStream(Lifecycle.start(0), afterSeconds(10));
  final session = [
    Schedule.emitStart(1, afterSeconds(20), after: Lifecycle.start(0)).call,
    Schedule.emitInterval(2, afterSeconds(30),
        after: Lifecycle.start(1),
        endWhen: () => Future.delayed(afterSeconds(40))).call,
    Schedule.emitStart(3, afterSeconds(50), after: Lifecycle.stop(2)).call,
  ];
  group("StreamSchedule", () {
    test('Converts Schedules into a correctly timed Stream of elements',
        () async {
      final outputStream = startStream()
          .asyncExpandMultipleRecursive(session)
          .absoluteTimeInterval();
      expect(
          outputStream,
          emitsRoughlyAfterSeconds([
            // We need to give the stream a chance to start, therefore we add 30
            MapEntry(40, Lifecycle.start(0)),
            MapEntry(60, Lifecycle.start(1)),
            MapEntry(90, Lifecycle.start(2)),
            MapEntry(130, Lifecycle.stop(2)),
            MapEntry(180, Lifecycle.start(3)),
          ]));
    });
    test(
        'Converts Schedules into a correctly timed Stream of elements, even with breaks',
        () async {
      final elementStreamController = StreamController<Lifecycle<int>>();
      final subscription = startStream()
          .asyncExpandMultipleRecursive(session)
          .listen((event) => elementStreamController.add(event));
      subscription.pause();
      final outputStream =
          elementStreamController.stream.absoluteTimeInterval();
      final outputList = outputStream.toList();
      subscription.resume();
      await Future.delayed(forSeconds(20), subscription.pause);
      await Future.delayed(forSeconds(90), subscription.resume);
      await Future.delayed(forSeconds(190), subscription.cancel);
      elementStreamController.close();
      expect(
          outputList,
          completion(orderedEquals([
            afterRoughlyMillis(10, Lifecycle.start(0)),
            afterRoughlyMillis(110, Lifecycle.start(1)),
            afterRoughlyMillis(140, Lifecycle.start(2)),
            afterRoughlyMillis(180, Lifecycle.stop(2)),
            afterRoughlyMillis(230, Lifecycle.start(3)),
          ])));
    });
  });
}
