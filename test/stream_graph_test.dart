import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:rxdart/rxdart.dart';
import 'package:stream_graph/dot_visualization.dart';
import 'package:stream_graph/stream_graph.dart';
import 'package:stream_graph/stream_schedule.dart';
import 'package:test/test.dart';

import 'absolute_time_interval.dart';

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
  test("Allows partitioning a stream into two streams according to a predicate",
      () {
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
  test("Allows grouping a stream into multiple streams with identical key", () {
    var graph = new StreamGraph();
    final startNode = graph.addStartNode<int>(pauseable: true);
    final grouping = graph.addGroupMapping<int, int, String>(startNode,
        grouper: (x) => x % 3,
        mapper: (x) => x.toString(),
        possibleGroups: [0, 1, 2],
        name: "mod3-equals");
    final source = Stream.fromIterable([1, 2, 3, 4, 5, 6, 7, 8, 9]);
    final compiledGraph = graph.compile({startNode: source});
    print(graph.graph.toDotString());
    final rest0 = compiledGraph.forNode(grouping.mapNode(0));
    expect(rest0, emitsInOrder(['3', '6', '9']));
    final rest1 = compiledGraph.forNode(grouping.mapNode(1));
    expect(rest1, emitsInOrder(['1', '4', '7']));
    final rest2 = compiledGraph.forNode(grouping.mapNode(2));
    expect(rest2, emitsInOrder(['2', '5', '8']));
  });
  test("Allows retrieving Streams by name", () {
    final graph = new StreamGraph();
    final startNode = graph.addStartNode<int>();
    final doubledNode =
        graph.addMapping<int, int>(startNode, (x) => x * 2, name: 'doubled');
    graph.addMapping<int, int>(startNode, (x) => x * 3, name: 'tripled');
    graph.addMapping<int, int>(doubledNode, (x) => x * 3,
        name: 'doubledTripled');
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
        graph.addMapping<int, int>(startNode, (x) => x * 2, name: 'doubled');
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
        graph.addMapping<int, int>(startNode, (x) => x * 2, name: 'doubled');
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
        graph.addMapping<int, int>(startNode, (x) => x * 2, name: 'doubled');
    final source = Stream.periodic(Duration(milliseconds: 10), (x) => x + 1);
    final compiledGraph = graph.compile({startNode: source});
    final originalStream = compiledGraph.forNode(startNode)!.toList();
    final doubledStream = compiledGraph.forNode(doubledNode)!.toList();
    await Future.delayed(Duration(milliseconds: 300));
    compiledGraph.close();
    expect(originalStream.then((value) => value.take(10)),
        completion([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]));
    expect(doubledStream.then((value) => value.take(10)),
        completion([2, 4, 6, 8, 10, 12, 14, 16, 18, 20]));
  });
  test("Allows working with multiple input streams", () async {
    final graph = new StreamGraph();
    final startNode1 = graph.addStartNode<int>(name: "s1");
    final startNode2 = graph.addStartNode<int>(name: "s2");
    final doubledNode1 =
        graph.addMapping<int, int>(startNode1, (x) => x * 2, name: 'doubled');
    final tripledNode2 =
        graph.addMapping<int, int>(startNode2, (x) => x * 3, name: 'tripled');
    final doubledTripledNode = graph.addMapping<int, int>(
        doubledNode1, (x) => x * 3,
        name: 'doubledTripled');
    final source1 = Stream.periodic(Duration(milliseconds: 13), (x) => x + 1);
    final source2 = Stream.periodic(Duration(milliseconds: 17), (x) => x + 100);
    final mergeDoubledAndTripled = graph.combineAll<int, int>(<StreamNode<int>>[
      doubledNode1,
      doubledTripledNode,
      tripledNode2
    ], Rx.merge<int>, name: "merge");
    final compiledGraph =
        graph.compile({startNode1: source1, startNode2: source2});
    final mergedStream =
        compiledGraph.forNode(mergeDoubledAndTripled)!.toList();
    await Future.delayed(Duration(milliseconds: 100));
    compiledGraph.close();
    expect(
        mergedStream,
        completion(allOf(containsAllInOrder([300, 303, 306, 309, 312]),
            containsAllInOrder([2, 4, 6, 8, 10, 12]))));
  });
  test("Allows combining multiple input streams by name", () async {
    final graph = new StreamGraph();
    final startNode1 = graph.addStartNode<int>(name: "s1");
    final startNode2 = graph.addStartNode<int>(name: "s2");
    final doubledNode1 =
        graph.addMapping<int, int>(startNode1, (x) => x * 2, name: 'doubled');
    final tripledNode2 =
        graph.addMapping<int, int>(startNode2, (x) => x * 3, name: 'tripled');
    final doubledTripledNode = graph.addMapping<int, int>(
        doubledNode1, (x) => x * 3,
        name: 'doubledTripled');
    final source1 = Stream.periodic(Duration(milliseconds: 13), (x) => x + 1);
    final source2 = Stream.periodic(Duration(milliseconds: 17), (x) => x + 100);
    final regex = RegExp(r'^doubled');
    final mergeDoubled = graph.combineAllFromSelector<int, int>(
        byName(regex), Rx.merge<int>,
        name: "merge");
    final compiledGraph =
        graph.compile({startNode1: source1, startNode2: source2});
    final mergedStream = compiledGraph.forNode(mergeDoubled)!.toList();
    await Future.delayed(Duration(milliseconds: 100));
    compiledGraph.close();
    expect(mergedStream, completion(containsAllInOrder([2, 4, 6, 8, 10, 12])));
  });
  test("Allows working with multiple input streams of different types",
      () async {
    final graph = new StreamGraph();
    final startNode1 = graph.addStartNode<int>(name: "s1");
    final startNode2 = graph.addStartNode<int>(name: "s2");
    final doubledNode1 = graph.addMapping<int, String>(
        startNode1, (x) => x.toString(),
        name: 'string');
    final tripledNode2 =
        graph.addMapping<int, int>(startNode2, (x) => x * 3, name: 'tripled');
    final source1 = Stream.periodic(Duration(milliseconds: 10), (x) => x + 1);
    final source2 = Stream.periodic(Duration(milliseconds: 50), (x) => x + 100);
    final mergeDoubledAndTripled = graph.combine2<int, String, String>(
        tripledNode2,
        doubledNode1,
        (s1, s2) => Rx.combineLatest2<int, String, String>(
            s1, s2, (e1, e2) => "${e1}${e2}"),
        name: "merge");
    final compiledGraph =
        graph.compile({startNode1: source1, startNode2: source2});
    final mergedStream =
        compiledGraph.forNode(mergeDoubledAndTripled)!.toList();
    await Future.delayed(Duration(milliseconds: 100));
    compiledGraph.close();
    expect(
        mergedStream,
        completion(
          containsAllInOrder([
            '3004',
            '3005',
            '3006',
            '3007',
            '3008',
            '3009',
            '3039',
            '30310',
          ]),
        ));
  });
  test("Allows scheduling items in a stream", () async {
    final graph = new StreamGraph();
    final startNode = graph.addStartNode<Lifecycle<int>>(name: "s1");
    final scheduleNode =
        graph.addLifecycleScheduleNode<int>(startNode, name: "s2", schedule: [
      Schedule.start(
          duration: Duration(milliseconds: 200),
          after: observingElement(Lifecycle.start(0)),
          emit: 1),
      Schedule.interval(
          duration: Duration(milliseconds: 300),
          after: observingElement(Lifecycle.start(1)),
          emit: 2,
          stopWhen: streamEmits("s1", Lifecycle.start(5))),
      Schedule.start(
          duration: Duration(milliseconds: 500),
          after: observingElement(Lifecycle.stop(2)),
          emit: 3)
    ]);
    final compiledGraph = graph.compile({
      startNode: TimerStream<Lifecycle<int>>(
              Lifecycle.start(0), Duration(milliseconds: 100))
          .concatWith(
              [TimerStream(Lifecycle.start(5), Duration(milliseconds: 700))])
    });
    final doubledStream = compiledGraph
        .forNode(scheduleNode)!
        .absoluteTimeInterval()
        .doOnData(print)
        .take(6)
        .toList();
    await Future.delayed(Duration(milliseconds: 2000));
    compiledGraph.close();
    expect(
        doubledStream,
        completion(containsAllInOrder([
          afterRoughlyMillis<Lifecycle<int>>(100, Lifecycle.start(0)),
          afterRoughlyMillis<Lifecycle<int>>(300, Lifecycle.start(1)),
          afterRoughlyMillis<Lifecycle<int>>(600, Lifecycle.start(2)),
          afterRoughlyMillis<Lifecycle<int>>(800, Lifecycle.start(5)),
          afterRoughlyMillis<Lifecycle<int>>(800, Lifecycle.stop(2)),
          afterRoughlyMillis<Lifecycle<int>>(1300, Lifecycle.start(3)),
        ])));
  });
  test("Allows creating cycles using CopyNodes", () {
    final graph = new StreamGraph();
    final copyNode = graph.addCopyNode<int>(nodeName: "merge");
    final copyTransformedNode = graph.addTransformer<int, int>(
        copyNode,
        StreamTransformer.fromBind((s) => Stream.fromFuture(
            s.firstWhere((e) => e == 2).then((e) => e * 10))));
    final startNode = graph.addStartNode<int>(pauseable: true, name: "source");
    final merged = graph.combineAll<int, int>(<StreamNode<int>>[
      startNode,
      copyTransformedNode,
    ], Rx.merge<int>, name: "merge");

    final compiledGraph = graph.compile({
      startNode: Stream<int>.fromIterable([1, 2, 3])
    });
    final mergedStream = compiledGraph.forNode(merged);
    expect(mergedStream, emitsInOrder([1, 2, 20, 3]));
  });
  test("Allows transforming generated Streams", () async {
    var graph = new StreamGraph();
    final startNode = graph.addStartNode<int>(pauseable: true, name: 'start');
    final doubledNode =
        graph.addMapping<int, int>(startNode, (x) => x * 2, name: 'doubled');
    final source = Stream.fromIterable([1, 2, 3]);
    final StreamController<String> sideChannel = StreamController<String>();

    final compiledGraph = graph.compile({startNode: source},
        doOnData: (event, node) => sideChannel.add("${node.name}: $event"));
    final sideChannelFutureList = sideChannel.stream.toList();
    final stream1List = compiledGraph.forNode(startNode)!.toList();
    final stream2List = compiledGraph.forNode(doubledNode)!.toList();
    await Future.delayed(Duration(milliseconds: 1));
    compiledGraph.close();
    expect(stream1List, completion([1, 2, 3]));
    expect(stream2List, completion([2, 4, 6]));
    expect(
        sideChannelFutureList,
        completion([
          "start: 1",
          "doubled: 2",
          "start: 2",
          "doubled: 4",
          "start: 3",
          "doubled: 6"
        ]));
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
