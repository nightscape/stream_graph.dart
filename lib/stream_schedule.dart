import 'dart:async';

import 'package:rxdart/rxdart.dart';

class Schedule<T> {
  final T elem;
  final Duration duration;
  final bool Function(T)? afterCondition;

  Schedule(this.elem, this.duration, {this.afterCondition});

  factory Schedule.emit(T elem, Duration duration, {T? after}) => after == null
      ? Schedule(elem, duration)
      : Schedule(elem, duration, afterCondition: (e) => e == after);

  bool matches(T other) => afterCondition != null && afterCondition!(other);
}

class StreamSchedule<T> {
  Stream<T> scheduleStream(List<Schedule<T>> schedule) {
    if (schedule.isEmpty) {
      return Stream.empty();
    }
    StreamController<T> controller = StreamController();
    void emit(Schedule<T> schedule) {
      if (schedule.duration.inMicroseconds == 0) {
        controller.add(schedule.elem);
      } else {
        Future.delayed(
            schedule.duration, (() => controller.add(schedule.elem)));
      }
    }

    final stream = controller.stream.doOnData(
        (e) => schedule.where((element) => element.matches(e)).forEach(emit));
    schedule.where((e) => e.afterCondition == null).forEach(emit);

    return stream;
  }
}
