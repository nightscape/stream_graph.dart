import 'dart:async';
import 'dart:io';

import 'package:rxdart/rxdart.dart';
import 'package:stream_graph/dot_visualization.dart';
import 'package:stream_graph/stream_graph.dart';
import 'package:test/test.dart';

void main() {
  test(
      'Allows constructing a directed acyclic graph of Streams where edges are transformations',
      () {
    var graph = new StreamGraph();
    final startNode = graph.addStartNode<int>(pauseable: true);
    final doubledNode = graph.addMapping<int, int>(startNode, (x) => x * 2);
    final tripledNode = graph.addMapping<int, int>(startNode, (x) => x * 3);
    final doubledTripledNode =
        graph.addMapping<int, int>(doubledNode, (x) => x * 3);
    final source = Stream.fromIterable([1, 2, 3]);
    final compiledGraph = graph.compile({startNode: source});
    final doubledStream = compiledGraph.forNode(doubledNode);
    expect(doubledStream, emitsInOrder([2, 4, 6]));
    final tripledStream = compiledGraph.forNode(tripledNode);
    expect(tripledStream, emitsInOrder([3, 6, 9]));
    final doubledTripledStream = compiledGraph.forNode(doubledTripledNode);
    expect(doubledTripledStream, emitsInOrder([6, 12, 18]));
  });
  test("Allows applying a StreamTransformer", () {
    var graph = new StreamGraph();
    final startNode = graph.addStartNode<int>(pauseable: true);
    final streamTransformer = StreamTransformer.fromBind(
        (Stream<int> p) => p.map((x) => (x * 2).toString()));
    final doubledStringNode =
        graph.addTransformer<int, String>(startNode, streamTransformer);
    final source = Stream.fromIterable([1, 2, 3]);
    final compiledGraph = graph.compile({startNode: source});
    final doubledStream = compiledGraph.forNode(doubledStringNode);
    expect(doubledStream, emitsInOrder(['2', '4', '6']));
  });
  test("Allows partitioning a stream into multiple streams", () {
    var graph = new StreamGraph();
    final startNode = graph.addStartNode<int>(pauseable: true);
    final partitioning =
        graph.addPartitioning<int>(startNode, (x) => x % 3 == 0);
    final source = Stream.fromIterable([1, 2, 3, 4, 5, 6, 7, 8, 9]);
    final compiledGraph = graph.compile({startNode: source});
    final multiplesOf3 = compiledGraph.forNode(partitioning.matches);
    expect(multiplesOf3, emitsInOrder([3, 6, 9]));
    final nonMultiplesOf3 = compiledGraph.forNode(partitioning.nonMatches);
    expect(nonMultiplesOf3, emitsInOrder([1, 2, 4, 5, 7, 8]));
  });
  test("Allows retrieving Streams by name", () {
    final graph = new StreamGraph();
    final startNode = graph.addStartNode<int>();
    final doubledNode =
        graph.addMapping<int, int>(startNode, (x) => x * 2, 'doubled');
    graph.addMapping<int, int>(startNode, (x) => x * 3, 'tripled');
    graph.addMapping<int, int>(doubledNode, (x) => x * 3, 'doubledTripled');
    final source = Stream.fromIterable([1, 2, 3]);
    final compiledGraph = graph.compile({startNode: source});
    final doubledStream = compiledGraph['doubled'];
    expect(doubledStream, emitsInOrder([2, 4, 6]));
    final tripledStream = compiledGraph['tripled'];
    expect(tripledStream, emitsInOrder([3, 6, 9]));
    final doubledTripledStream = compiledGraph['doubledTripled'];
    expect(doubledTripledStream, emitsInOrder([6, 12, 18]));
  });
  test("Allows retrieving a Stream even when downstream Streams depend on it",
      () {
    final graph = new StreamGraph();
    final startNode = graph.addStartNode<int>();
    final doubledNode =
        graph.addMapping<int, int>(startNode, (x) => x * 2, 'doubled');
    final doubleTripledNode =
        graph.addMapping<int, int>(doubledNode, (x) => x * 3);
    final source = Stream.fromIterable([1, 2, 3]);
    final compiledGraph = graph.compile({startNode: source});
    final originalStream = compiledGraph.forNode(startNode);
    expect(originalStream, emitsInOrder([1, 2, 3]));
    final doubledStream = compiledGraph.forNode(doubledNode);
    expect(doubledStream, emitsInOrder([2, 4, 6]));
    final doubledStreamByName = compiledGraph['doubled'];
    expect(doubledStreamByName, emitsInOrder([2, 4, 6]));
    final doubleTripledStream = compiledGraph.forNode(doubleTripledNode);
    expect(doubleTripledStream, emitsInOrder([6, 12, 18]));
  });
  test("Allows pausing and resuming reading from the input stream", () async {
    final graph = new StreamGraph();
    final startNode = graph.addStartNode<int>(pauseable: true);
    final doubledNode =
        graph.addMapping<int, int>(startNode, (x) => x * 2, 'doubled');
    final controller = StreamController<int>();
    final compiledGraph = graph.compile({startNode: controller.stream});
    final doubledStream = compiledGraph.forNode(doubledNode);
    [1, 2, 3].forEach(controller.add);
    expect(doubledStream, emitsInOrder([2, 4, 6]));
    await Future.delayed(Duration(milliseconds: 100));
    compiledGraph.close();
    [4, 5, 6].forEach(controller.add);
    expect(doubledStream, emitsDone);
  });
  test("Allows working with infinite streams", () async {
    final graph = new StreamGraph();
    final startNode = graph.addStartNode<int>();
    final doubledNode =
        graph.addMapping<int, int>(startNode, (x) => x * 2, 'doubled');
    final source = Stream.periodic(Duration(milliseconds: 10), (x) => x + 1);
    final compiledGraph = graph.compile({startNode: source});
    final originalStream = compiledGraph.forNode(startNode).toList();
    final doubledStream = compiledGraph.forNode(doubledNode).toList();
    await Future.delayed(Duration(milliseconds: 95));
    compiledGraph.close();
    expect(originalStream, completion([1, 2, 3, 4, 5, 6, 7, 8, 9]));
    expect(doubledStream, completion([2, 4, 6, 8, 10, 12, 14, 16, 18]));
  });
  test("Allows working with multiple input streams", () async {
    final graph = new StreamGraph();
    final startNode1 = graph.addStartNode<int>(name: "s1");
    final startNode2 = graph.addStartNode<int>(name: "s2");
    final doubledNode1 =
        graph.addMapping<int, int>(startNode1, (x) => x * 2, 'doubled');
    final tripledNode2 =
        graph.addMapping<int, int>(startNode2, (x) => x * 3, 'tripled');
    final source1 = Stream.periodic(Duration(milliseconds: 13), (x) => x + 1);
    final source2 = Stream.periodic(Duration(milliseconds: 17), (x) => x + 100);
    final mergeDoubledAndTripled = graph.combineAll<int, int>(<StreamNode<int>>[
      doubledNode1,
      tripledNode2
    ], (streams) => Rx.merge<int>(streams), name: "merge");
    File("delete_me.dot").writeAsString(graph.graph.toDotString());
    final compiledGraph =
        graph.compile({startNode1: source1, startNode2: source2});
    final mergedStream = compiledGraph.forNode(mergeDoubledAndTripled).toList();
    await Future.delayed(Duration(milliseconds: 100));
    compiledGraph.close();
    expect(
        mergedStream,
        completion(containsAllInOrder(
            [2, 300, 4, 303, 6, 306, 8, 10, 309, 12, 312, 14])));
  });
  test("Allows transforming generated Streams", () async {
    var graph = new StreamGraph();
    final startNode = graph.addStartNode<int>(pauseable: true);
    final doubledNode =
        graph.addMapping<int, int>(startNode, (x) => x * 2, 'doubled');
    final source = Stream.fromIterable([1, 2, 3]);
    final StreamController<int> sideChannel = StreamController<int>();

    final compiledGraph = graph.compile({startNode: source},
        doOnData: (event) => sideChannel.add(event * 3));
    final sideChannelFutureList = sideChannel.stream.toList();
    final stream1List = compiledGraph.forNode(startNode).toList();
    final stream2List = compiledGraph.forNode(doubledNode).toList();
    await Future.delayed(Duration(milliseconds: 1));
    compiledGraph.close();
    expect(stream1List, completion([1, 2, 3]));
    expect(stream2List, completion([2, 4, 6]));
    expect(sideChannelFutureList, completion([3, 6, 6, 12, 9, 18]));
    sideChannel.close();
  });
  test("Allows converting Streams to arbitrary objects", () async {
    var graph = new StreamGraph();
    final startNode = graph.addStartNode<int>(pauseable: true);
    final converted = graph.convert<int, Future<List<int>>>(
        startNode, (stream) => stream.toList());
    final source = Stream.fromIterable([1, 2, 3]);
    final compiledGraph = graph.compile({startNode: source});
    final convertedToFutureList = compiledGraph.outputFor(converted);
    await Future.delayed(Duration(milliseconds: 1));
    compiledGraph.close();
    expect(convertedToFutureList, completion([1, 2, 3]));
  });
}
