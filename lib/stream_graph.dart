import 'dart:async';

import 'package:directed_graph/directed_graph.dart';

abstract class StreamNode<T> extends Comparable<dynamic> {
  @override
  int compareTo(dynamic other) => 0;
}

class SourceNode<T> extends StreamNode<T> {}

class TransformNode<S, T> extends StreamNode<T> {
  final StreamTransformer<S, T> mapping;
  final StreamNode<S> input;
  TransformNode(this.input, this.mapping);
  Stream<T> transformStream(Stream<S> input) => mapping.bind(input);
}

class FilterNode<T> extends StreamNode<T> {
  final StreamNode<T> input;
  final bool Function(T) predicate;
  FilterNode(this.input, this.predicate);
  Stream<T> transformStream(Stream<T> input) => input.where(predicate);
}

class Partitioning<T> {
  final StreamNode<T> matches;
  final StreamNode<T> nonMatches;

  Partitioning({required this.matches, required this.nonMatches});
}

class StreamGraph<I> {
  final startNode = SourceNode<I>();
  final graph = DirectedGraph<StreamNode>({});
  final nodeNames = <StreamNode, String>{};
  StreamGraph() {
    graph.comparator = null;
    addNode(startNode, 'start');
  }

  void addNode(StreamNode node, String? name) {
    if (name != null) {
      nodeNames[node] = name;
    }
    graph.addEdges(node, {});
  }

  TransformNode<S, T> addTransformer<S, T>(
      StreamNode<S> input, StreamTransformer<S, T> streamTransformer,
      [String? name]) {
    final node = TransformNode<S, T>(input, streamTransformer);
    addNode(node, name);
    graph.addEdges(input, {node});
    return node;
  }

  StreamNode<T> addMapping<S, T>(StreamNode<S> input, T Function(S) mapping,
          [String? name]) =>
      addTransformer<S, T>(
          input,
          StreamTransformer.fromBind((Stream<S> input) => input.map(mapping)),
          name);

  CompiledStreamGraph<I> compile(Stream<I> source) =>
      CompiledStreamGraph(source, graph, nodeNames);

  Partitioning<T> addPartitioning<T>(
      SourceNode<T> input, bool Function(T x) predicate,
      {String? nameForMatches, String? nameForNonMatches}) {
    final matchesNode = FilterNode<T>(input, predicate);
    final nonMatchesNode = FilterNode(input, (T e) => !predicate(e));
    addNode(matchesNode, nameForMatches);
    addNode(nonMatchesNode, nameForNonMatches);
    graph.addEdges(input, {matchesNode});
    graph.addEdges(input, {nonMatchesNode});
    return Partitioning(matches: matchesNode, nonMatches: nonMatchesNode);
  }
}

class CompiledStreamGraph<I> {
  final Stream<I> source;
  final StreamController<I> controller = StreamController<I>();
  late final Stream<I> startStream;
  late final StreamSubscription<I> subscription;
  final DirectedGraph<StreamNode> graph;
  final Map<StreamNode, Stream> streams = {};
  final Map<String, Stream> streamsByName = {};

  CompiledStreamGraph(
      this.source, this.graph, Map<StreamNode, String> nodeNames) {
    startStream = controller.stream.asBroadcastStream();
    subscription = source.listen(controller.add);
    streams[graph.topologicalOrdering!.first] = startStream;
    streamsByName['start'] = startStream;
    graph.sortedTopologicalOrdering!.forEach((node) {
      var stream = streams[node]!;
      final edges = graph.edges(node);
      stream = stream.asBroadcastStream();
      edges.forEach((edge) {
        if (edge is TransformNode) {
          streams[edge] = edge.transformStream(stream);
        } else if (edge is FilterNode) {
          streams[edge] = edge.transformStream(stream);
        }
        if (nodeNames.containsKey(edge)) {
          streamsByName[nodeNames[edge]!] = streams[edge]!;
        }
      });
    });
  }
  Stream<S> forNode<S>(StreamNode<S> node) => streams[node]!.map((e) => e as S);
  Stream? operator [](String nodeName) => streamsByName[nodeName];
  void pause() => subscription.pause();
  void resume() => subscription.resume();
  void close() {
    subscription.cancel();
    controller.close();
  }
}
