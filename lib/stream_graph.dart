import 'dart:async';

import 'package:directed_graph/directed_graph.dart';
import 'package:rxdart/rxdart.dart';

abstract class GraphNode extends Comparable<dynamic> {
  String? name;
  GraphNode({this.name});
  @override
  int compareTo(dynamic other) => 0;
  String get outputType => this.runtimeType.toString();
  @override
  String toString() => (name ?? super.toString()) + ":\n$outputType";
}

abstract class StreamNode<T> extends GraphNode {
  StreamNode({String? name}) : super(name: name);
  StreamTransformer<T, T> streamTransformer(
          StreamTransformer<T, T> Function(StreamNode<T>) transformer) =>
      transformer(this);
  Stream<T> withDoOnData(Stream<T> input, void Function(dynamic) onData) =>
      input.doOnData(onData);
}

class SourceNode<T> extends StreamNode<T> {
  bool pauseable;
  late StreamController<T> controller;
  SourceNode({this.pauseable = true, String? name}) : super(name: name) {
    this.controller = StreamController<T>.broadcast();
  }
  MapEntry<StreamController<T>, StreamSubscription<T>> attach(
          Stream<T> source) =>
      MapEntry(controller, source.listen(controller.add));
}

class TransformNode<S, T> extends StreamNode<T> {
  final StreamTransformer<S, T> mapping;
  final StreamNode<S> input;
  TransformNode(this.input, this.mapping, {String? name}) : super(name: name);

  Stream<T> transformStreams(Map<StreamNode, Stream> existingStreams) =>
      mapping.bind(existingStreams[input]! as Stream<S>);
}

class FilterNode<T> extends StreamNode<T> {
  final StreamNode<T> input;
  final bool Function(T) predicate;
  FilterNode(this.input, this.predicate, {String? name}) : super(name: name);
  Stream<T> transformStreams(Map<StreamNode, Stream> existingStreams) =>
      (existingStreams[input]! as Stream<T>).where(predicate);
}

class Partitioning<T> extends StreamNode<T> {
  final StreamNode<T> matches;
  final StreamNode<T> nonMatches;

  Partitioning({required this.matches, required this.nonMatches, String? name})
      : super(name: name);
}

class CombineAllNode<S, T> extends StreamNode<T> {
  final List<StreamNode<S>> inputs;
  final Stream<T> Function(List<Stream<S>>) combinator;
  CombineAllNode(this.inputs, this.combinator, {String? name})
      : super(name: name);
  Stream<T> transformStreams(Map<StreamNode, Stream> inputs) => combinator(
      this.inputs.map((i) => inputs[i]! as Stream<S>).toList(growable: false));
}

class ConversionNode<S, T> extends GraphNode {
  final StreamNode<S> input;
  final T Function(Stream<S>) converter;
  final String? name;
  ConversionNode(this.input, this.converter, {this.name});
  T transformStream(Stream<S> input) => converter(input);
  @override
  String toString() => name ?? super.toString();
}

class StreamGraph {
  final graph = DirectedGraph<GraphNode>({});
  final nodeNames = <GraphNode, String>{};
  StreamGraph() {
    graph.comparator = null;
  }

  CompiledStreamGraph compile(Map<SourceNode, Stream> binding,
          {StreamTransformer<T, T> Function<T>(StreamNode<T> node)?
              transformStream,
          void Function(dynamic)? doOnData}) =>
      CompiledStreamGraph(graph, nodeNames, binding,
          transformStream: transformStream, doOnData: doOnData);

  void addNode(GraphNode node, String? name) {
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
          StreamTransformer<S, T>.fromBind(
              (Stream<S> input) => input.map(mapping)),
          name);

  Partitioning<T> addPartitioning<T>(
      SourceNode<T> input, bool Function(T x) predicate,
      {String? nameForMatches, String? nameForNonMatches}) {
    final matchesNode = FilterNode<T>(input, predicate);
    final nonMatchesNode = FilterNode<T>(input, (T e) => !predicate(e));
    addNode(matchesNode, nameForMatches);
    addNode(nonMatchesNode, nameForNonMatches);
    graph.addEdges(input, {matchesNode});
    graph.addEdges(input, {nonMatchesNode});
    return Partitioning(matches: matchesNode, nonMatches: nonMatchesNode);
  }

  combineAll<S, T>(
      List<StreamNode<S>> list, Stream<T> Function(List<Stream<S>>) combinator,
      {String? name}) {
    final mergeNode = CombineAllNode<S, T>(list, combinator, name: name);
    addNode(mergeNode, name);
    for (final node in list) {
      graph.addEdges(node, {mergeNode});
    }
    return mergeNode;
  }

  ConversionNode<S, T> convert<S, T>(
      StreamNode<S> node, T Function(Stream<S>) converter,
      {String? name}) {
    final n = ConversionNode<S, T>(node, converter, name: name);
    addNode(n, name);
    graph.addEdges(node, {n});
    return n;
  }
}

class CompiledStreamGraph {
  late final Map<SourceNode, MapEntry<StreamController, StreamSubscription>>
      startStreams;
  final DirectedGraph<GraphNode> graph;
  final Map<StreamNode, Stream> streams = {};
  late final Map<String, GraphNode> nodesByName;
  final Map<ConversionNode, Object> outputs = {};
  final StreamTransformer<T, T> Function<T>(StreamNode<T> node)?
      transformStream;
  final void Function(dynamic o)? doOnData;

  CompiledStreamGraph(this.graph, Map<GraphNode, String> nodeNames,
      Map<SourceNode, Stream> binding,
      {this.transformStream, this.doOnData}) {
    nodesByName = {for (var e in nodeNames.entries) e.value: e.key};
    startStreams =
        binding.map((key, stream) => MapEntry(key, key.attach(stream)));
    startStreams.forEach((key, value) {
      _addStreamForNode(value.key.stream, key);
    });
    graph.sortedTopologicalOrdering!.whereType<StreamNode>().forEach((node) {
      final targetNodes = graph.edges(node);
      targetNodes.forEach((targetNode) {
        Stream? newStream;
        if (targetNode is TransformNode) {
          newStream = targetNode.transformStreams(streams);
        } else if (targetNode is FilterNode) {
          newStream = targetNode.transformStreams(streams);
        } else if (targetNode is CombineAllNode) {
          newStream = targetNode.transformStreams(streams);
        } else if (targetNode is ConversionNode) {
        } else {
          throw UnimplementedError('$targetNode');
        }
        if (newStream != null && targetNode is StreamNode) {
          _addStreamForNode(newStream, targetNode);
        }
      });
    });
  }
  void _addStreamForNode<T>(Stream<T> stream, StreamNode<T> node) {
    Stream<T> transformedStream =
        doOnData == null ? stream : node.withDoOnData(stream, doOnData!);
    streams[node] = transformedStream.asBroadcastStream();
  }

  Stream<S> forNode<S>(StreamNode<S> node) => streams[node]!.map((e) => e as S);
  Stream<S> forNodeName<S>(String name) =>
      forNode<S>(nodesByName[name]! as StreamNode<S>);
  Stream? operator [](String nodeName) =>
      forNode(nodesByName[nodeName]! as StreamNode);
  forEachStartStreamSubscription(void Function(StreamSubscription) f) {
    startStreams.values.forEach((e) => f(e.value));
  }

  T outputFor<T>(ConversionNode<dynamic, T> node) =>
      node.transformStream(streams[node.input]!);

  T outputForName<T>(String name) =>
      outputFor<T>(this.nodesByName[name] as ConversionNode<dynamic, T>);

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
