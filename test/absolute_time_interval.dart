import 'dart:async';

import 'package:rxdart/rxdart.dart';
import 'package:rxdart/src/utils/forwarding_sink.dart';
import 'package:rxdart/src/utils/forwarding_stream.dart';
import 'package:test/expect.dart';

class _AbsoluteTimeIntervalStreamSink<S>
    extends ForwardingSink<S, TimeInterval<S>> {
  final _stopwatch = Stopwatch();

  @override
  void onData(S data) {
    sink.add(
      TimeInterval<S>(
        data,
        Duration(
          microseconds: _stopwatch.elapsedMicroseconds,
        ),
      ),
    );
  }

  @override
  void onError(Object e, StackTrace st) => sink.addError(e, st);

  @override
  void onDone() => sink.close();

  @override
  FutureOr onCancel() {}

  @override
  void onListen() => _stopwatch.start();

  @override
  void onPause() {}

  @override
  void onResume() {}
}

/// Records the time interval between consecutive values in an stream
/// sequence.
///
/// ### Example
///
///     Stream.fromIterable([1])
///       .transform(IntervalStreamTransformer(Duration(seconds: 1)))
///       .transform(TimeIntervalStreamTransformer())
///       .listen(print); // prints TimeInterval{interval: 0:00:01, value: 1}
class AbsoluteTimeIntervalStreamTransformer<S>
    extends StreamTransformerBase<S, TimeInterval<S>> {
  /// Constructs a [StreamTransformer] which emits events from the
  /// source [Stream] as snapshots in the form of [TimeInterval].
  AbsoluteTimeIntervalStreamTransformer();

  @override
  Stream<TimeInterval<S>> bind(Stream<S> stream) =>
      forwardStream(stream, () => _AbsoluteTimeIntervalStreamSink());
}

/// Extends the Stream class with the ability to record the time interval
/// between consecutive values in an stream
extension AbsoluteTimeIntervalExtension<T> on Stream<T> {
  /// Records the time interval between consecutive values in a Stream sequence.
  ///
  /// ### Example
  ///
  ///     Stream.fromIterable([1])
  ///       .interval(Duration(seconds: 1))
  ///       .timeInterval()
  ///       .listen(print); // prints TimeInterval{interval: 0:00:01, value: 1}
  Stream<TimeInterval<T>> absoluteTimeInterval() =>
      transform(AbsoluteTimeIntervalStreamTransformer<T>());
}

final int speedup = 1000;

Matcher matcherOrCloseTo(dynamic valueOrMatcher) {
  if (valueOrMatcher is Matcher) {
    return valueOrMatcher;
  } else {
    return closeTo(valueOrMatcher as num, 30);
  }
}

Matcher afterRoughlyMillis<T>(dynamic valueOrMatcher, T value) {
  return TypeMatcher<TimeInterval<T>>()
      .having((ti) => ti.value, "value", value)
      .having((ti) => ti.interval.inMilliseconds * speedup ~/ 1000, 'interval',
          matcherOrCloseTo(valueOrMatcher));
}

Matcher emitsRoughlyAfterSeconds<T>(List<MapEntry<int, T>> elements) {
  final elementsWithIntervals = elements.map((e) {
    return afterRoughlyMillis<T>(e.key, e.value);
  });
  return emitsInOrder(elementsWithIntervals);
}
