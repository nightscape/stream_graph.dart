import 'dart:async';

import 'package:directed_graph/directed_graph.dart';

abstract class StreamNode<T> extends Comparable<dynamic> {
  @override
  int compareTo(dynamic other) => 0;
}

class SourceNode<T> extends StreamNode<T> {}

class TransformNode<S, T> extends StreamNode<T> {
  final T Function(S) mapping;
  final StreamNode<S> input;
  TransformNode(this.input, this.mapping);
  T transformElement(S input) => mapping(input);
  Stream<T> transformStream(Stream<S> input) => input.map(mapping);
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
  StreamGraph() {
    graph.comparator = null;
    graph.addEdges(startNode, {});
  }
  StreamNode<T> addMapping<S, T>(StreamNode<S> input, T Function(S) mapping) {
    final node = TransformNode<S, T>(input, mapping);
    graph.addEdges(node, {});
    graph.addEdges(input, {node});
    return node;
  }

  CompiledStreamGraph compile(Stream<I> source) =>
      CompiledStreamGraph(source, graph);

  Partitioning<T> addPartitioning<T>(
      SourceNode<T> input, bool Function(T x) predicate) {
    final matchesNode = FilterNode<T>(input, predicate);
    final nonMatchesNode = FilterNode(input, (T e) => !predicate(e));
    graph.addEdges(input, {matchesNode});
    graph.addEdges(input, {nonMatchesNode});
    return Partitioning(matches: matchesNode, nonMatches: nonMatchesNode);
  }
}

class CompiledStreamGraph<I> {
  final Stream<I> startStream;
  final DirectedGraph<StreamNode> graph;
  final Map<StreamNode, Stream> streams = {};

  CompiledStreamGraph(this.startStream, this.graph) {
    streams[graph.topologicalOrdering!.first] = startStream;
    graph.sortedTopologicalOrdering!.forEach((node) {
      var stream = streams[node]!;
      final edges = graph.edges(node);
      if (edges.length > 1) stream = stream.asBroadcastStream();
      edges.forEach((edge) {
        if (edge is TransformNode) {
          streams[edge] = edge.transformStream(stream);
        } else if (edge is FilterNode) {
          streams[edge] = edge.transformStream(stream);
        }
      });
    });
  }
  Stream<S> forNode<S>(StreamNode<S> node) => streams[node]!.map((e) => e as S);
}
