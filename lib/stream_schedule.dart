import 'dart:async';

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:rxdart/rxdart.dart';
import 'package:stream_graph/stream_graph.dart';

part 'stream_schedule.freezed.dart';

typedef StreamPredicate<T> = bool Function(StreamElement<T>);
typedef StreamCondition = MapEntry<Stream? Function(Map<StreamNode, Stream>),
    Future<dynamic> Function(Stream?)>;

class StreamElement<T> {
  final T? elem;
  final int index;

  StreamElement(this.elem, this.index);
}

class Emission<T> extends Schedule<T> {
  final T emit;

  Emission(Duration duration,
      {required StreamPredicate<T> after, required this.emit})
      : super(duration, after);
  Stream<T> call(StreamElement<T> value) =>
      (after.call(value)) ? TimerStream(emit, duration) : Stream.empty();
}

class Interval<T> extends Schedule<Lifecycle<T>> {
  final T emitElem;
  final bool Function(StreamElement<Lifecycle<T>>) after;
  final StreamCondition stopWhen;

  Interval(Duration duration,
      {required this.after, required this.stopWhen, required T emit})
      : emitElem = emit,
        super(duration, after);
  Stream<Lifecycle<T>> call(
      StreamElement<Lifecycle<T>> value, Map<StreamNode, Stream> streams) {
    final endStream = stopWhen.key.call(streams);
    return Schedule.emission<Lifecycle<T>>(duration,
            after: after, emit: Lifecycle.start(emitElem))
        .call(value)
        .asyncExpand((v) => Stream.value(v).concatWith([
              Stream.fromFuture(stopWhen
                  .value(endStream)
                  .then((_) => Lifecycle.stop(emitElem)))
            ]));
  }

  @override
  Lifecycle<T> get emit => Lifecycle.start(emitElem);
}

abstract class Schedule<T> {
  T get emit;
  final Duration duration;

  final bool Function(StreamElement<T>) after;
  const Schedule(this.duration, this.after);
  static Emission<T> emission<T>(Duration duration,
          {required StreamPredicate<T> after, required T emit}) =>
      Emission(duration, after: after, emit: emit);
  static Interval<T> interval<T>(Duration duration,
          {required StreamPredicate<Lifecycle<T>> after,
          required T emit,
          required StreamCondition stopWhen}) =>
      Interval(duration, after: after, emit: emit, stopWhen: stopWhen);
  static Emission<Lifecycle<T>> start<T>(Duration duration,
          {required StreamPredicate<Lifecycle<T>> after, required T emit}) =>
      Schedule.emission<Lifecycle<T>>(duration,
          emit: Lifecycle.start(emit), after: after);
  static Emission<Lifecycle<T>> stop<T>(Duration duration,
          {required StreamPredicate<Lifecycle<T>> after, required T emit}) =>
      Schedule.emission<Lifecycle<T>>(duration,
          emit: Lifecycle.stop(emit), after: after);
}

@freezed
class Lifecycle<T> with _$Lifecycle<T> {
  const factory Lifecycle.start(T t) = Start;
  const factory Lifecycle.stop(T t) = Stop;
}

extension ScheduleListExtension<T> on Iterable<Schedule<T>> {
  Stream<T> stream([Stream<T>? startStr]) {
    final startStream = startStr ?? Stream<T>.empty();
    final emissionFunctions = this.whereType<Emission<T>>().map((e) => e.call);
    return startStream.asyncExpandMultipleRecursive(emissionFunctions);
  }
}

extension LifecycleScheduleListExtension<T>
    on Iterable<Schedule<Lifecycle<T>>> {
  Stream<Lifecycle<T>> lifecycleStream(
      {Map<StreamNode, Stream> streams = const {},
      Stream<Lifecycle<T>>? startStream}) {
    final startStr = startStream ?? Stream<Lifecycle<T>>.empty();
    final emissionFunctions =
        this.whereType<Emission<Lifecycle<T>>>().map((e) => e.call);
    final intervalFunctions = this
        .whereType<Interval<T>>()
        .map((e) => (StreamElement<Lifecycle<T>> t) => e.call(t, streams));

    return startStr.asyncExpandMultipleRecursive(
        emissionFunctions.followedBy(intervalFunctions));
  }
}

StreamPredicate<T> observingElement<T>(T e) => (StreamElement o) => e == o.elem;
StreamPredicate<T> streamStart<T>() =>
    (StreamElement o) => o.index == 0 && o.elem == null;

StreamCondition streamEmits(String streamName, dynamic value) => MapEntry(
    (streams) => streams.entries
        .firstWhere((element) => element.key.name == streamName)
        .value,
    (stream) => stream!.firstWhere((element) => element == value));

StreamCondition timePassed(Duration duration) =>
    MapEntry((_) => null, (_) => Future.delayed(duration));

extension AsyncExpandRecursive<T> on Stream<T> {
  Stream<T> asyncExpandRecursive(Stream<T> Function(StreamElement<T>) mapper) {
    StreamController<T?> controller = StreamController();
    int counter = 0;
    final stream = controller.stream.doOnData((e) {
      final mapped = mapper(StreamElement(e, counter++));
      mapped.forEach(controller.add).catchError(controller.addError);
    });
    controller.add(null);
    this.forEach(controller.add);

    return stream.skip(1).cast<T>();
  }

  Stream<T> asyncExpandMultipleRecursive(
      Iterable<Stream<T> Function(StreamElement<T>)> mappers) {
    final mapper = (StreamElement<T> t) => Rx.merge(mappers.map((m) => m(t)));
    return asyncExpandRecursive(mapper);
  }
}
