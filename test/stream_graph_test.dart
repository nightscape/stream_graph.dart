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
}
