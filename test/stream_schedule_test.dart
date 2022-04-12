import 'dart:async';

import 'package:stream_graph/stream_schedule.dart';
import 'package:test/test.dart';

import 'absolute_time_interval.dart';

void main() {
  Duration afterSeconds(int seconds) =>
      Duration(milliseconds: seconds * 1000 ~/ speedup);
  Duration forSeconds(int seconds) =>
      Duration(milliseconds: seconds * 1000 ~/ speedup);
  final session = <Schedule<Lifecycle<int>>>[
    Schedule.start(duration: afterSeconds(10), after: streamStart(), emit: 0),
    Schedule.start(
        duration: afterSeconds(20),
        after: observingElement(Lifecycle.start(0)),
        emit: 1),
    Schedule.interval<int>(
        duration: afterSeconds(30),
        after: observingElement(Lifecycle.start(1)),
        emit: 2,
        stopWhen: timePassed(afterSeconds(40))),
    Schedule.start(
        duration: afterSeconds(50),
        after: observingElement(Lifecycle.stop(2)),
        emit: 3),
  ];
  group("StreamSchedule", () {
    test('Converts Schedules into a correctly timed Stream of elements',
        () async {
      final outputStream = session.lifecycleStream().absoluteTimeInterval();
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
      final subscription = session
          .lifecycleStream()
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
