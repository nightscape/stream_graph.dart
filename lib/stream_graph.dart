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

abstract class HasInputStreamNodes {
  List<StreamNode> get inputs;
}

abstract class StreamNode<T> extends GraphNode with HasInputStreamNodes {
  StreamNode({String? name}) : super(name: name);
  StreamTransformer<T, T> streamTransformer(
          StreamTransformer<T, T> Function(StreamNode<T>) transformer) =>
      transformer(this);
  Stream<T> withDoOnData(
          Stream<T> input, void Function(dynamic, StreamNode<T>) onData) =>
      input.doOnData((event) => onData(event, this));
  TransformNode<T, U> transform<U>(StreamTransformer<T, U> transformer,
          {String? name}) =>
      TransformNode<T, U>(this, transformer, name: name);
  TransformNode<T, U> map<U>(U Function(T) mapper, {String? name}) =>
      transform(StreamTransformer.fromBind((stream) => stream.map(mapper)),
          name: name);

  FilterNode<T> where(bool Function(T) predicate, {String? name}) =>
      FilterNode(this, predicate, name: name);

  FilterNode<T> whereType<U extends T>({String? name}) =>
      where((e) => e is U, name: name);

  Partitioning<T> partition(bool Function(T x) predicate,
      {String? nameForMatches, String? nameForNonMatches}) {
    final matchesNode = this.where(predicate, name: nameForMatches);
    final nonMatchesNode =
        this.where((T e) => !predicate(e), name: nameForNonMatches);
    return Partitioning(matches: matchesNode, nonMatches: nonMatchesNode);
  }

  Grouping<T, K> groupBy<T, K>(StreamNode<T> node, K Function(T) grouper,
      {required List<K> possibleGroups, String? name}) {
    final groupNodes = {
      for (var key in possibleGroups)
        key: FilterNode<T>(node, (T e) => grouper(e) == key, name: '$name-$key')
    };
    return Grouping<T, K>(node, grouper, groupNodes);
  }

  GroupMapping<T, K, V> groupMapBy<K, V>(
      {required K Function(T) grouper,
      required V Function(T) mapper,
      required List<K> possibleGroups,
      String? name}) {
    final groupNodes = {
      for (var key in possibleGroups)
        key: this.where((T e) => grouper(e) == key, name: '$name-$key')
    };
    final mapNodes = {
      for (var key in possibleGroups)
        key:
            groupNodes[key]!.map((T e) => mapper(e), name: '$name-$key-mapping')
    };
    return GroupMapping<T, K, V>(this, grouper, mapNodes, mapper);
  }

  ScheduleNode<T> addSchedule(
          {String? name, required Iterable<Schedule<T>> schedule}) =>
      ScheduleNode<T>(this, schedule, name: name);

  ConversionNode<T, U> convert<U>(U Function(Stream<T>) converter,
          {String? name}) =>
      ConversionNode<T, U>(this, converter, name: name);
}

extension LifecycleStreamNode<T> on StreamNode<Lifecycle<T>> {
  LifecycleScheduleNode<T> addLifecycleSchedule(
          {String? name, required Iterable<Schedule<Lifecycle<T>>> schedule}) =>
      LifecycleScheduleNode<T>(this, schedule, name: name);
}

class SourceNode<T> extends StreamNode<T> {
  bool pauseable;
  late StreamController<T> controller;
  SourceNode({this.pauseable = true, String? name}) : super(name: name) {
    this.controller = StreamController<T>.broadcast();
  }

  MapEntry<StreamController<T>, StreamSubscription<T>> transformStreams(
          Map<StreamNode, Stream> existingStreams) =>
      MapEntry(controller,
          (existingStreams[this]! as Stream<T>).listen(controller.add));

  @override
  List<StreamNode> get inputs => [];
}

class EagerSourceNode<T> extends SourceNode<T> {
  final Stream<T> value;
  EagerSourceNode(this.value, {String? name, bool pauseable = true})
      : super(name: name, pauseable: pauseable);
  MapEntry<StreamController<T>, StreamSubscription<T>> transformStreams(
          Map<StreamNode, Stream> existingStreams) =>
      MapEntry(controller, value.listen(controller.add));
}

class CopyNode<T> extends StreamNode<T> {
  CopyNode({String? name}) : super(name: "copy-$name");
  final controller = StreamController<T>.broadcast();
  Stream<T> get stream => controller.stream;

  MapEntry<StreamController<T>, StreamSubscription<T>> attach(
      Map<StreamNode, Stream> existingStreams) {
    final searchedName = name?.replaceFirst(RegExp(r"copy-"), "");
    final copiedNodeAndStream = existingStreams.entries
        .firstWhere((element) => element.key.name == searchedName);
    final copiedStream = copiedNodeAndStream.value as Stream<T>;
    return MapEntry(
        controller, copiedStream.listen((event) => controller.add(event)));
  }

  @override
  List<StreamNode> get inputs => [];
}

class SingleInputNode<S, T> extends StreamNode<T> {
  final StreamNode<S> input;
  SingleInputNode(this.input, {String? name}) : super(name: name);

  @override
  List<StreamNode> get inputs => [input];
}

class TransformNode<S, T> extends SingleInputNode<S, T> {
  final StreamTransformer<S, T> mapping;
  TransformNode(StreamNode<S> input, this.mapping, {String? name})
      : super(input, name: name);

  Stream<T> transformStreams(Map<StreamNode, Stream> existingStreams) =>
      mapping.bind(existingStreams[input]! as Stream<S>);
}

class ScheduleNode<T> extends SingleInputNode<T, T> {
  final Iterable<Schedule<T>> schedule;

  ScheduleNode(StreamNode<T> input, this.schedule, {String? name})
      : super(input, name: name);

  Stream<T> transformStreams(Map<StreamNode, Stream> existingStreams) =>
      schedule.stream(existingStreams[input]! as Stream<T>);
}

class LifecycleScheduleNode<T>
    extends SingleInputNode<Lifecycle<T>, Lifecycle<T>> {
  final Iterable<Schedule<Lifecycle<T>>> schedule;

  LifecycleScheduleNode(StreamNode<Lifecycle<T>> input, this.schedule,
      {String? name})
      : super(input, name: name);

  Stream<Lifecycle<T>> transformStreams(
          Map<StreamNode, Stream> existingStreams) =>
      schedule.lifecycleStream(
          streams: existingStreams,
          startStream: existingStreams[input]! as Stream<Lifecycle<T>>);
}

class FilterNode<T> extends SingleInputNode<T, T> {
  final bool Function(T) predicate;
  FilterNode(StreamNode<T> input, this.predicate, {String? name})
      : super(input, name: name);
  Stream<T> transformStreams(Map<StreamNode, Stream> existingStreams) =>
      (existingStreams[input]! as Stream<T>).where(predicate);
}

class Partitioning<T> extends StreamNode<T> {
  final StreamNode<T> matches;
  final StreamNode<T> nonMatches;

  Partitioning({required this.matches, required this.nonMatches, String? name})
      : super(name: name);

  @override
  List<StreamNode> get inputs => [matches, nonMatches];
}

class Grouping<T, K> extends GraphNode with HasInputStreamNodes {
  StreamNode<T> node;
  K Function(T) grouper;
  Map<K, FilterNode<T>> groupNodes;
  Grouping(this.node, this.grouper, this.groupNodes);
  FilterNode<T> groupNode(K key) => groupNodes[key]!;

  @override
  List<StreamNode> get inputs => [node];
}

class GroupMapping<T, K, V> extends GraphNode with HasInputStreamNodes {
  StreamNode<T> node;
  K Function(T) grouper;
  Map<K, TransformNode<T, V>> groupNodes;
  V Function(T) mapper;
  GroupMapping(this.node, this.grouper, this.groupNodes, this.mapper);
  TransformNode<T, V> mapNode(K key) => groupNodes[key]!;

  @override
  List<StreamNode> get inputs => [node];
}

class Combine2Node<R, S, T> extends StreamNode<T> {
  final StreamNode<R> stream1;
  final StreamNode<S> stream2;
  final Stream<T> Function(Stream<R>, Stream<S>) combinator;
  Combine2Node(this.stream1, this.stream2, this.combinator, {String? name})
      : super(name: name);
  Stream<T> transformStreams(Map<StreamNode, Stream> inputs) => combinator(
      inputs[this.stream1]!.cast<R>(), inputs[this.stream2]!.cast<S>());

  @override
  List<StreamNode> get inputs => [stream1, stream2];
}

class CombineAllNode<S, T> extends StreamNode<T> {
  final List<StreamNode<S>> Function(StreamGraph) selector;
  final Stream<T> Function(List<Stream<S>>) combinator;
  List<StreamNode<S>>? _inputs;
  CombineAllNode(this.selector, this.combinator, {String? name})
      : super(name: name);
  void finalize(StreamGraph graph) {
    _inputs = selector(graph);
    graph.addNode(this);
  }

  Stream<T> transformStreams(Map<StreamNode, Stream> inputs) => combinator(this
      ._inputs!
      .map((i) => inputs[i]! as Stream<S>)
      .toList(growable: false));

  @override
  List<StreamNode> get inputs => _inputs ?? [];
}

List<StreamNode<S>> Function(StreamGraph) fromList<S>(
        List<StreamNode<S>> nodes) =>
    (_) => nodes;
List<StreamNode<S>> Function(StreamGraph) byName<S>(RegExp regExp) =>
    (graph) => graph.graph.vertices
        .where((v) => v is StreamNode<S> && regExp.hasMatch(v.name ?? ""))
        .cast<StreamNode<S>>()
        .toList(growable: false);

class ConversionNode<S, T> extends SingleInputNode<S, T> {
  final T Function(Stream<S>) converter;
  final String? name;
  ConversionNode(StreamNode<S> input, this.converter, {this.name})
      : super(input, name: name);
  T transformStream(Stream<S> input) => converter(input);
  @override
  String toString() => name ?? super.toString();
}

class StreamGraph {
  final graph = DirectedGraph<GraphNode>({});
  StreamGraph([Iterable<GraphNode> nodes = const []]) {
    graph.comparator = null;
    nodes.forEach(addNode);
  }

  static SourceNode<T> sourceNode<T>({String? name, bool pauseable = false}) =>
      SourceNode<T>(pauseable: pauseable, name: name);

  static SourceNode<T> eagerSourceNode<T>(Stream<T> stream,
          {String? name, bool pauseable = false}) =>
      EagerSourceNode<T>(stream, pauseable: pauseable, name: name);

  static CopyNode<T> copyNode<T>({required String nodeName}) =>
      CopyNode<T>(name: nodeName);

  static Combine2Node<R, S, T> combine2Node<R, S, T>(
          StreamNode<R> stream1,
          StreamNode<S> stream2,
          Stream<T> Function(Stream<R>, Stream<S>) combinator,
          {String? name}) =>
      Combine2Node<R, S, T>(stream1, stream2, combinator, name: name);
  static CombineAllNode<S, T> combineAllNode<S, T>(List<StreamNode<S>> list,
          Stream<T> Function(List<Stream<S>>) combinator,
          {String? name}) =>
      combineAllFromSelectorNode(fromList(list), combinator, name: name);

  static CombineAllNode<S, T> combineAllFromSelectorNode<S, T>(
          List<StreamNode<S>> Function(StreamGraph) selector,
          Stream<T> Function(List<Stream<S>>) combinator,
          {String? name}) =>
      CombineAllNode<S, T>(selector, combinator, name: name);

  void finalize() {
    for (final node in graph.vertices.toList(growable: false)) {
      if (node is CombineAllNode) {
        node.finalize(this);
      }
    }
  }

  CompiledStreamGraph compile(Map<SourceNode, Stream> binding,
      {StreamTransformer<T, T> Function<T>(StreamNode<T> node)? transformStream,
      void Function(dynamic, StreamNode)? doOnData}) {
    this.finalize();
    return CompiledStreamGraph(graph, binding,
        transformStream: transformStream, doOnData: doOnData);
  }

  T addNode<T extends GraphNode>(T node) {
    final edgeNodes = (node is HasInputStreamNodes)
        ? (node as HasInputStreamNodes).inputs
        : <StreamNode>[];
    graph.addEdges(node, {});
    edgeNodes.forEach((inputNode) {
      graph.addEdges(inputNode, {node});
      addNode(inputNode);
    });
    return node;
  }
}

class CompiledStreamGraph {
  late final Map<StreamNode, MapEntry<StreamController, StreamSubscription>>
      startStreams;
  final DirectedGraph<GraphNode> graph;
  final Map<StreamNode, Stream> streams = {};
  late final Map<String, GraphNode> nodesByName;
  final Map<ConversionNode, Object> outputs = {};
  final StreamTransformer<T, T> Function<T>(StreamNode<T> node)?
      transformStream;
  final void Function(dynamic o, StreamNode)? doOnData;

  CompiledStreamGraph(this.graph, Map<SourceNode, Stream> binding,
      {this.transformStream, this.doOnData}) {
    nodesByName = {
      for (var e
          in this.graph.vertices.where((element) => element.name != null))
        e.name!: e
    };
    final givenStreams = {...binding};
    final sourceNodes =
        graph.data.keys.whereType<SourceNode>().toList(growable: false);
    startStreams = Map.fromEntries(sourceNodes
        .map((node) => MapEntry(node, node.transformStreams(givenStreams))));
    startStreams.forEach((key, value) {
      _addStreamForNode(value.key.stream, key);
    });
    final sortedNodes = graph.sortedTopologicalOrdering!
        .whereType<StreamNode>()
        .toList(growable: false);
    sortedNodes.forEach((node) {
      Stream? newStream;
      if (node is SourceNode) {
        newStream = startStreams[node]!.key.stream;
      } else if (node is TransformNode) {
        newStream = node.transformStreams(streams);
      } else if (node is ScheduleNode) {
        newStream = node.transformStreams(streams);
      } else if (node is LifecycleScheduleNode) {
        newStream = node.transformStreams(streams);
      } else if (node is FilterNode) {
        newStream = node.transformStreams(streams);
      } else if (node is CombineAllNode) {
        newStream = node.transformStreams(streams);
      } else if (node is Combine2Node) {
        newStream = node.transformStreams(streams);
      } else if (node is CopyNode) {
        newStream = node.stream;
      } else if (node is ConversionNode || node is Partitioning) {
      } else {
        throw UnimplementedError('$node');
      }
      if (newStream != null) {
        _addStreamForNode(newStream, node);
      }
    });

    final mappings = graph
        .whereType<CopyNode>()
        .map((node) => MapEntry<StreamNode,
                MapEntry<StreamController, StreamSubscription>>(
            node, node.attach(streams)))
        .toList(growable: false);
    final copyStreams = Map<StreamNode,
        MapEntry<StreamController, StreamSubscription>>.fromEntries(mappings);
    copyStreams.forEach((key, value) {
      _addStreamForNode(value.key.stream, key);
    });
    startStreams.addAll(copyStreams);
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
