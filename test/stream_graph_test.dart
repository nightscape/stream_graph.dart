import 'dart:async';

import 'package:neurosphere_data_processing/stream_graph.dart';
import 'package:test/test.dart';

void main() {
  test(
      'Allows constructing a directed acyclic graph of Streams where edges are transformations',
      () {
    var graph = new StreamGraph<int>();
    final startNode = graph.startNode;
    final doubledNode = graph.addMapping<int, int>(startNode, (x) => x * 2);
    final tripledNode = graph.addMapping<int, int>(startNode, (x) => x * 3);
    final doubledTripledNode =
        graph.addMapping<int, int>(doubledNode, (x) => x * 3);
    final source = Stream.fromIterable([1, 2, 3]);
    final compiledGraph = graph.compile(source);
    final doubledStream = compiledGraph.forNode(doubledNode);
    expect(doubledStream, emitsInOrder([2, 4, 6]));
    final tripledStream = compiledGraph.forNode(tripledNode);
    expect(tripledStream, emitsInOrder([3, 6, 9]));
    final doubledTripledStream = compiledGraph.forNode(doubledTripledNode);
    expect(doubledTripledStream, emitsInOrder([6, 12, 18]));
  });
  test("Allows applying a StreamTransformer", () {
    var graph = new StreamGraph<int>();
    final startNode = graph.startNode;
    final streamTransformer = StreamTransformer.fromBind(
        (Stream<int> p) => p.map((x) => (x * 2).toString()));
    final doubledStringNode =
        graph.addTransformer<int, String>(startNode, streamTransformer);
    final source = Stream.fromIterable([1, 2, 3]);
    final compiledGraph = graph.compile(source);
    final doubledStream = compiledGraph.forNode(doubledStringNode);
    expect(doubledStream, emitsInOrder(['2', '4', '6']));
  });
  test("Allows partitioning a stream into multiple streams", () {
    var graph = new StreamGraph<int>();
    final startNode = graph.startNode;
    final partitioning =
        graph.addPartitioning<int>(startNode, (x) => x % 3 == 0);
    final source = Stream.fromIterable([1, 2, 3, 4, 5, 6, 7, 8, 9]);
    final compiledGraph = graph.compile(source);
    final multiplesOf3 = compiledGraph.forNode(partitioning.matches);
    expect(multiplesOf3, emitsInOrder([3, 6, 9]));
    final nonMultiplesOf3 = compiledGraph.forNode(partitioning.nonMatches);
    expect(nonMultiplesOf3, emitsInOrder([1, 2, 4, 5, 7, 8]));
  });
  test("Allows retrieving Streams by name", () {
    final graph = new StreamGraph<int>();
    final startNode = graph.startNode;
    final doubledNode =
        graph.addMapping<int, int>(startNode, (x) => x * 2, 'doubled');
    graph.addMapping<int, int>(startNode, (x) => x * 3, 'tripled');
    graph.addMapping<int, int>(doubledNode, (x) => x * 3, 'doubledTripled');
    final source = Stream.fromIterable([1, 2, 3]);
    final compiledGraph = graph.compile(source);
    final doubledStream = compiledGraph['doubled'];
    expect(doubledStream, emitsInOrder([2, 4, 6]));
    final tripledStream = compiledGraph['tripled'];
    expect(tripledStream, emitsInOrder([3, 6, 9]));
    final doubledTripledStream = compiledGraph['doubledTripled'];
    expect(doubledTripledStream, emitsInOrder([6, 12, 18]));
  });
  test("Allows retrieving a Stream even when downstream Streams depend on it",
      () {
    final graph = new StreamGraph<int>();
    final startNode = graph.startNode;
    final doubledNode =
        graph.addMapping<int, int>(startNode, (x) => x * 2, 'doubled');
    final doubleTripledNode =
        graph.addMapping<int, int>(doubledNode, (x) => x * 3);
    final source = Stream.fromIterable([1, 2, 3]);
    final compiledGraph = graph.compile(source);
    final doubledStream = compiledGraph.forNode(doubledNode);
    expect(doubledStream, emitsInOrder([2, 4, 6]));
    final doubledStreamByName = compiledGraph['doubled'];
    expect(doubledStreamByName, emitsInOrder([2, 4, 6]));
    final doubleTripledStream = compiledGraph.forNode(doubleTripledNode);
    expect(doubleTripledStream, emitsInOrder([6, 12, 18]));
  });
  test("Allows pausing and resuming reading from the input stream", () async {
    final graph = new StreamGraph<int>();
    final startNode = graph.startNode;
    final doubledNode =
        graph.addMapping<int, int>(startNode, (x) => x * 2, 'doubled');
    final controller = StreamController<int>();
    final compiledGraph = graph.compile(controller.stream);
    final doubledStream = compiledGraph.forNode(doubledNode);
    [1, 2, 3].forEach(controller.add);
    expect(doubledStream, emitsInOrder([2, 4, 6]));
    await Future.delayed(Duration(milliseconds: 100));
    compiledGraph.close();
    [4, 5, 6].forEach(controller.add);
    expect(doubledStream, emitsDone);
  });
}
