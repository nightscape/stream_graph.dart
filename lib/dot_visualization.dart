import 'package:directed_graph/directed_graph.dart';

extension DirectedGraphVis<T extends Object> on DirectedGraph<T> {
  String toDotString() {
    return '''
digraph "" {
graph [style=rounded fontname="Arial Black" fontsize=13 penwidth=2.6];
node [shape=rect style="filled,rounded" fontname=Arial fontsize=15 fillcolor=Lavender penwidth=1.3];
edge [penwidth=1.3];
${this.map((n) => '"$n"').join('\n')}
${this.expand((element) => this.edges(element).map((n) => '"$element" -> "$n"')).toList().join('\n')}
}''';
  }
}
