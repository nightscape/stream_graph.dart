import 'dart:async';

import 'package:directed_graph/directed_graph.dart';
import 'package:rxdart/rxdart.dart';
import 'package:stream_graph/stream_schedule.dart';

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
  Stream<T> withDoOnData(
          Stream<T> input, void Function(dynamic, StreamNode<T>) onData) =>
      input.doOnData((event) => onData(event, this));
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

class ScheduleNode<T> extends SourceNode<T> {
  final List<Schedule<T>> schedule;
  ScheduleNode(this.schedule, {String? name}) : super(name: name);

  MapEntry<StreamController<T>, StreamSubscription<T>> start() {
    final scheduledStream = StreamSchedule<T>().scheduleStream(schedule);
    return attach(scheduledStream);
  }
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

class Grouping<T, K> {
  StreamNode<T> node;
  K Function(T) grouper;
  Map<K, FilterNode<T>> groupNodes;
  Grouping(this.node, this.grouper, this.groupNodes);
  FilterNode<T> groupNode(K key) => groupNodes[key]!;
}

class GroupMapping<T, K, V> {
  StreamNode<T> node;
  K Function(T) grouper;
  Map<K, StreamNode<V>> groupNodes;
  V Function(T) mapper;
  GroupMapping(this.node, this.grouper, this.groupNodes, this.mapper);
  StreamNode<V> mapNode(K key) => groupNodes[key]!;
}

class Combine2Node<R, S, T> extends StreamNode<T> {
  final StreamNode<R> stream1;
  final StreamNode<S> stream2;
  final Stream<T> Function(Stream<R>, Stream<S>) combinator;
  Combine2Node(this.stream1, this.stream2, this.combinator, {String? name})
      : super(name: name);
  Stream<T> transformStreams(Map<StreamNode, Stream> inputs) => combinator(
      inputs[this.stream1]!.cast<R>(), inputs[this.stream2]!.cast<S>());
}

class CombineAllNode<S, T> extends StreamNode<T> {
  final List<StreamNode<S>> Function(StreamGraph) selector;
  final Stream<T> Function(List<Stream<S>>) combinator;
  List<StreamNode<S>>? inputs;
  CombineAllNode(this.selector, this.combinator, {String? name})
      : super(name: name);
  void finalize(StreamGraph graph) {
    inputs = selector(graph);
    for (final node in inputs!) {
      graph.graph.addEdges(node, {this});
    }
  }

  Stream<T> transformStreams(Map<StreamNode, Stream> inputs) => combinator(
      this.inputs!.map((i) => inputs[i]! as Stream<S>).toList(growable: false));
}

List<StreamNode<S>> Function(StreamGraph) fromList<S>(
        List<StreamNode<S>> nodes) =>
    (_) => nodes;
List<StreamNode<S>> Function(StreamGraph) byName<S>(RegExp regExp) =>
    (graph) => graph.graph.vertices
        .where((v) => v is StreamNode<S> && regExp.hasMatch(v.name ?? ""))
        .cast<StreamNode<S>>()
        .toList(growable: false);

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

  void finalize() {
    for (final node in graph.vertices) {
      if (node is CombineAllNode) {
        node.finalize(this);
      }
    }
  }

  CompiledStreamGraph compile(Map<SourceNode, Stream> binding,
      {StreamTransformer<T, T> Function<T>(StreamNode<T> node)? transformStream,
      void Function(dynamic, StreamNode)? doOnData}) {
    this.finalize();
    return CompiledStreamGraph(graph, nodeNames, binding,
        transformStream: transformStream, doOnData: doOnData);
  }

  T addNode<T extends GraphNode>(T node, String? name) {
    if (name != null) {
      nodeNames[node] = name;
    }
    graph.addEdges(node, {});
    return node;
  }

  SourceNode<T> addStartNode<T>({String? name, bool pauseable = false}) =>
      addNode(SourceNode<T>(pauseable: pauseable, name: name), name);

  ScheduleNode<T> addScheduleNode<T>(
          {String? name, required List<Schedule<T>> schedule}) =>
      addNode(ScheduleNode<T>(schedule, name: name), name);

  TransformNode<S, T> addTransformer<S, T>(
      StreamNode<S> input, StreamTransformer<S, T> streamTransformer,
      {String? name}) {
    final node = TransformNode<S, T>(input, streamTransformer, name: name);
    addNode(node, name);
    graph.addEdges(input, {node});
    return node;
  }

  StreamNode<T> addMapping<S, T>(StreamNode<S> input, T Function(S) mapping,
          {String? name}) =>
      addTransformer<S, T>(
          input,
          StreamTransformer<S, T>.fromBind(
              (Stream<S> input) => input.map(mapping)),
          name: name);

  Partitioning<T> addPartitioning<T>(
      StreamNode<T> input, bool Function(T x) predicate,
      {String? nameForMatches, String? nameForNonMatches}) {
    final matchesNode = FilterNode<T>(input, predicate, name: nameForMatches);
    final nonMatchesNode =
        FilterNode<T>(input, (T e) => !predicate(e), name: nameForNonMatches);
    addNode(matchesNode, nameForMatches);
    addNode(nonMatchesNode, nameForNonMatches);
    graph.addEdges(input, {matchesNode});
    graph.addEdges(input, {nonMatchesNode});
    return Partitioning(matches: matchesNode, nonMatches: nonMatchesNode);
  }

  Combine2Node<R, S, T> combine2<R, S, T>(
      StreamNode<R> stream1,
      StreamNode<S> stream2,
      Stream<T> Function(Stream<R>, Stream<S>) combinator,
      {String? name}) {
    final mergeNode =
        Combine2Node<R, S, T>(stream1, stream2, combinator, name: name);
    addNode(mergeNode, name);
    for (final node in [stream1, stream2]) {
      graph.addEdges(node, {mergeNode});
    }
    return mergeNode;
  }

  CombineAllNode<S, T> combineAll<S, T>(List<StreamNode<S>> list,
          Stream<T> Function(List<Stream<S>>) combinator,
          {String? name}) =>
      combineAllFromSelector(fromList(list), combinator, name: name);

  CombineAllNode<S, T> combineAllFromSelector<S, T>(
      List<StreamNode<S>> Function(StreamGraph) selector,
      Stream<T> Function(List<Stream<S>>) combinator,
      {String? name}) {
    final comb = CombineAllNode<S, T>(selector, combinator, name: name);
    addNode(comb, name);
    return comb;
  }

  ConversionNode<S, T> convert<S, T>(
      StreamNode<S> node, T Function(Stream<S>) converter,
      {String? name}) {
    final n = ConversionNode<S, T>(node, converter, name: name);
    addNode(n, name);
    graph.addEdges(node, {n});
    return n;
  }

  Grouping<T, K> addGrouping<T, K>(StreamNode<T> node, K Function(T) grouper,
      {required List<K> possibleGroups, String? name}) {
    final groupNodes = {
      for (var key in possibleGroups)
        key: FilterNode<T>(node, (T e) => grouper(e) == key, name: '$name-$key')
    };
    groupNodes.values
        .forEach((groupNode) => addNode(groupNode, groupNode.name));
    graph.addEdges(node, groupNodes.values.toSet());
    return Grouping<T, K>(node, grouper, groupNodes);
  }

  GroupMapping<T, K, V> addGroupMapping<T, K, V>(StreamNode<T> node,
      {required K Function(T) grouper,
      required V Function(T) mapper,
      required List<K> possibleGroups,
      String? name}) {
    final groupNodes = {
      for (var key in possibleGroups)
        key: FilterNode<T>(node, (T e) => grouper(e) == key, name: '$name-$key')
    };
    groupNodes.values
        .forEach((groupNode) => addNode(groupNode, groupNode.name));
    final mapNodes = {
      for (var key in possibleGroups)
        key: addMapping(groupNodes[key]!, (T e) => mapper(e),
            name: '$name-$key-mapping')
    };
    graph.addEdges(node, groupNodes.values.toSet());
    possibleGroups.forEach((element) {
      graph.addEdges(groupNodes[element]!, {mapNodes[element]!});
    });
    return GroupMapping<T, K, V>(node, grouper, mapNodes, mapper);
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
  final void Function(dynamic o, StreamNode)? doOnData;

  CompiledStreamGraph(this.graph, Map<GraphNode, String> nodeNames,
      Map<SourceNode, Stream> binding,
      {this.transformStream, this.doOnData}) {
    nodesByName = {for (var e in nodeNames.entries) e.value: e.key};
    startStreams = binding
        .map((key, stream) => MapEntry(key, key.attach(stream)))
      ..addEntries(nodeNames.keys
          .whereType<ScheduleNode>()
          .map((s) => MapEntry(s, s.start())));
    startStreams.forEach((key, value) {
      _addStreamForNode(value.key.stream, key);
    });
    graph.sortedTopologicalOrdering!.whereType<StreamNode>().forEach((node) {
      Stream? newStream;
      if (node is SourceNode || node is ScheduleNode) {
        newStream = startStreams[node]!.key.stream;
      } else if (node is TransformNode) {
        newStream = node.transformStreams(streams);
      } else if (node is FilterNode) {
        newStream = node.transformStreams(streams);
      } else if (node is CombineAllNode) {
        newStream = node.transformStreams(streams);
      } else if (node is Combine2Node) {
        newStream = node.transformStreams(streams);
      } else if (node is ConversionNode) {
      } else {
        throw UnimplementedError('$node');
      }
      if (newStream != null) {
        _addStreamForNode(newStream, node);
      }
      //});
    });
  }
  void _addStreamForNode<T>(Stream<T> stream, StreamNode<T> node) {
    Stream<T> transformedStream =
        doOnData == null ? stream : node.withDoOnData(stream, doOnData!);
    streams[node] = transformedStream.asBroadcastStream();
  }

  Stream<S>? forNode<S>(StreamNode<S> node) =>
      streams[node]!.map((e) => e as S);
  Stream<S>? forNodeName<S>(String name) => nodesByName.containsKey(name)
      ? forNode<S>(nodesByName[name] as StreamNode<S>)
      : null;
  Stream? operator [](String nodeName) => forNodeName(nodeName);
  forEachStartStreamSubscription(void Function(StreamSubscription) f) {
    startStreams.values.forEach((e) => f(e.value));
  }

  T? outputFor<T>(ConversionNode<dynamic, T> node) =>
      streams.containsKey(node.input)
          ? node.transformStream(streams[node.input]!)
          : null;

  T? outputForName<T>(String name) => nodesByName.containsKey(name)
      ? outputFor(nodesByName[name] as ConversionNode<dynamic, T>)
      : null;

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

extension IncomingEdges<T extends Object> on DirectedGraph<T> {
  Iterable<T> incomingEdges(T node) {
    return this.where((element) => this.edges(element).contains(node));
  }
}
