import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:rxdart/rxdart.dart';

part 'schedule.freezed.dart';

abstract class ToFunction<T> {
  Stream<T> call(T value);
}

abstract class HasDuration {
  Duration get duration;
}

class Once<T> extends Schedule<T> with HasDuration {
  final T elem;
  final bool Function(T) afterCondition;

  Once(this.elem, Duration duration, this.afterCondition) : super(duration);
  Stream<T> call(T value) => (afterCondition.call(value))
      ? TimerStream(elem, duration)
      : Stream.empty();
}

class Interval<T> extends Schedule<Lifecycle<T>> with HasDuration {
  final T elem;
  final Lifecycle<T> after;
  final Future<dynamic> Function() endWhen;

  Interval(this.elem, Duration duration, this.after, {required this.endWhen})
      : super(duration);
  Stream<Lifecycle<T>> call(Lifecycle<T> value) => Schedule.emitStart<T>(
          elem, duration, after: after)
      .call(value)
      .asyncExpand((v) => Stream.value(v).concatWith(
          [Stream.fromFuture(endWhen().then((_) => Lifecycle.stop(elem)))]));
}

abstract class Schedule<T> {
  final Duration duration;
  const Schedule(this.duration);
  static Once<T> once<T>(T elem, Duration duration,
          {required bool Function(T) afterCondition}) =>
      Once(elem, duration, afterCondition);
  static Interval<T> emitInterval<T>(T elem, Duration duration,
          {required Lifecycle<T> after,
          required Future<dynamic> Function() endWhen}) =>
      Interval(elem, duration, after, endWhen: endWhen);
  static Once<T> emit<T>(T elem, Duration duration, {required T after}) =>
      Schedule.once(elem, duration, afterCondition: (e) => e == after);
  static Once<Lifecycle<T>> emitStart<T>(T elem, Duration duration,
          {required Lifecycle<T> after}) =>
      Schedule.emit<Lifecycle<T>>(Lifecycle.start(elem), duration,
          after: after);
}

@freezed
class Lifecycle<T> with _$Lifecycle<T> {
  const factory Lifecycle.start(T t) = Start;
  const factory Lifecycle.stop(T t) = Stop;
}
