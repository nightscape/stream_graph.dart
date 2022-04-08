import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:rxdart/rxdart.dart';

part 'schedule.freezed.dart';

class Schedule {
  static Stream<T> Function(T) once<T>(T elem, Duration duration,
          {required bool Function(T) afterCondition}) =>
      (T t) => (afterCondition.call(t))
          ? TimerStream(elem, duration)
          : Stream.empty();
  static Stream<T> Function(T) emit<T>(T elem, Duration duration,
          {required T after}) =>
      Schedule.once(elem, duration, afterCondition: (e) => e == after);
  static Stream<Lifecycle<S>> Function(Lifecycle<S>) emitStart<S>(
          S elem, Duration duration,
          {required Lifecycle<S> after}) =>
      emit(Lifecycle.start(elem), duration, after: after);
  static Stream<Lifecycle<S>> Function(Lifecycle<S>) emitInterval<S>(
          S elem, Duration duration,
          {required Lifecycle<S> after,
          required Future<dynamic> Function() endWhen}) =>
      (Lifecycle<S> t) => emitStart<S>(elem, duration, after: after)
          .call(t)
          .asyncExpand((v) => Stream.value(v).concatWith([
                Stream.fromFuture(endWhen().then((_) => Lifecycle.stop(elem)))
              ]));
}

@freezed
class Lifecycle<T> with _$Lifecycle<T> {
  const factory Lifecycle.start(T t) = Start;
  const factory Lifecycle.stop(T t) = Stop;
}
