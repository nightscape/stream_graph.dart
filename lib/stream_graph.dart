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
        final edgeTransformer = edge as TransformNode;
        streams[edge] = edgeTransformer.transformStream(stream);
      });
    });
  }
  Stream<S> forNode<S>(StreamNode<S> node) => streams[node]!.map((e) => e as S);
}
