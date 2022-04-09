import 'package:freezed_annotation/freezed_annotation.dart';

class Schedule {
  static List<Future<T>> Function(T) once<T>(T elem, Duration duration,
          {bool Function(T)? afterCondition}) =>
      (T t) => [
            if (afterCondition?.call(t) ?? true)
              Future.delayed(duration, () => elem)
          ];
  static List<Future<T>> Function(T) emit<T>(T elem, Duration duration,
          {T? after}) =>
      after == null
          ? Schedule.once(elem, duration)
          : Schedule.once(elem, duration, afterCondition: (e) => e == after);
}
