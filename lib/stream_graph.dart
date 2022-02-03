import 'dart:async';

import 'package:directed_graph/directed_graph.dart';

abstract class StreamNode<T> extends Comparable<dynamic> {
  String? name;
  StreamNode({this.name});
  @override
  int compareTo(dynamic other) => 0;
  String toString() => name ?? super.toString();
}

class SourceNode<T> extends StreamNode<T> {
  bool pauseable;
  late StreamController<T> controller;
  SourceNode({this.pauseable = true, String? name}) : super(name: name) {
    this.controller = StreamController<T>.broadcast();
  }
}

class TransformNode<S, T> extends StreamNode<T> {
  final StreamTransformer<S, T> mapping;
  final StreamNode<S> input;
  TransformNode(this.input, this.mapping, {String? name}) : super(name: name);
  Stream<T> transformStream(Stream<S> input) => mapping.bind(input);
}

class FilterNode<T> extends StreamNode<T> {
  final StreamNode<T> input;
  final bool Function(T) predicate;
  FilterNode(this.input, this.predicate, {String? name}) : super(name: name);
  Stream<T> transformStream(Stream<T> input) => input.where(predicate);
}

class Partitioning<T> extends StreamNode<T> {
  final StreamNode<T> matches;
  final StreamNode<T> nonMatches;

  Partitioning({required this.matches, required this.nonMatches, String? name})
      : super(name: name);
}

class CombineAllNode<T, U> extends StreamNode<U> {
  final List<StreamNode<T>> inputs;
  final Stream<U> Function(List<Stream<T>>) combinator;
  CombineAllNode(this.inputs, this.combinator, {String? name})
      : super(name: name);
  Stream<U> transformStreams(List<Stream<T>> inputs) => combinator(inputs);
}

class StreamGraph {
  final graph = DirectedGraph<StreamNode>({});
  final nodeNames = <StreamNode, String>{};
  StreamGraph() {
    graph.comparator = null;
  }

  CompiledStreamGraph compile(Map<SourceNode, Stream> binding) =>
      CompiledStreamGraph(graph, nodeNames, binding);

  void addNode(StreamNode node, String? name) {
    if (name != null) {
      nodeNames[node] = name;
    }
    graph.addEdges(node, {});
  }

  SourceNode<T> addStartNode<T>({String? name, bool pauseable = false}) {
    final node = SourceNode<T>(pauseable: pauseable, name: name);
    addNode(node, name);
    return node;
  }

  TransformNode<S, T> addTransformer<S, T>(
      StreamNode<S> input, StreamTransformer<S, T> streamTransformer,
      [String? name]) {
    final node = TransformNode<S, T>(input, streamTransformer, name: name);
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

  combineAll<T, U>(
      List<StreamNode<T>> list, Stream<U> Function(List<Stream<T>>) combinator,
      {String? name}) {
    final mergeNode = CombineAllNode(list, combinator, name: name);
    addNode(mergeNode, name);
    for (final node in list) {
      graph.addEdges(node, {mergeNode});
    }
    return mergeNode;
  }
}

class CompiledStreamGraph {
  late final Map<SourceNode, MapEntry<StreamController, StreamSubscription>>
      startStreams;
  final DirectedGraph<StreamNode> graph;
  final Map<StreamNode, Stream> streams = {};
  final Map<String, Stream> streamsByName = {};

  CompiledStreamGraph(this.graph, Map<StreamNode, String> nodeNames,
      Map<SourceNode, Stream> binding) {
    startStreams = binding.map((key, stream) {
      final controller = key.controller;
      final subscription = stream.listen(controller.add);
      return MapEntry(key, MapEntry(controller, subscription));
    });
    startStreams.forEach((key, value) {
      streams[key] = value.key.stream;
      if (nodeNames.containsKey(key)) {
        streamsByName[nodeNames[key]!] = value.key.stream;
      }
    });
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
  forEachStartStreamSubscription(void Function(StreamSubscription) f) {
    startStreams.values.forEach((e) => f(e.value));
  }

  forEachStartStreamController(void Function(StreamController) f) {
    startStreams.values.forEach((e) => f(e.key));
  }

  void pause() => forEachStartStreamSubscription((s) => s.pause());
  void resume() => forEachStartStreamSubscription((s) => s.resume());
  void close() {
    forEachStartStreamSubscription((s) => s.cancel());
    forEachStartStreamController((c) => c.close());
  }
}
