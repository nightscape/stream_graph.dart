import 'dart:async';

import 'package:rxdart/rxdart.dart';
import 'package:stream_graph/schedule.dart';

extension AsyncExpandRecursive<T> on Stream<T> {
  Stream<T> asyncMapRecursive(Iterable<Future<T>> Function(T) mapper) {
    StreamController<T> controller = StreamController();
    void emit(Future<T> fut) =>
        fut.then(controller.add).catchError(controller.addError);

    final stream = controller.stream.doOnData((e) {
      final mapped = mapper(e);
      mapped.forEach(emit);
    });
    this.forEach(controller.add);

    return stream;
  }

  Stream<T> asyncMapMultipleRecursive(
      Iterable<Iterable<Future<T>> Function(T)> mappers) {
    final mapper = (T t) => mappers.expand((m) => m(t));
    return asyncMapRecursive(mapper);
  }

  Stream<T> asyncExpandRecursive(Stream<T> Function(T) mapper) {
    StreamController<T> controller = StreamController();
    final stream = controller.stream.doOnData((e) {
      final mapped = mapper(e);
      mapped.forEach(controller.add).catchError(controller.addError);
    });
    this.forEach(controller.add);

    return stream;
  }

  Stream<T> asyncExpandMultipleRecursive(
      Iterable<Stream<T> Function(T)> mappers) {
    final mapper = (T t) => Rx.merge(mappers.map((m) => m(t)));
    return asyncExpandRecursive(mapper);
  }
}
