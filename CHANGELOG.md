0.3.9
=====
* Automatically publish to pub.dev
0.3.3
=====
* Allow freezed 2.2.0,  build_runner <2.4.0, test <1.21.6

0.3.2
=====
* Add ShutdownNode to emit value when calling close()

0.3.1
=====
* Add whereType<U>()

0.3.0
=====
* Remove most instance methods on StreamGraph

0.2.6
=====
* Add Stream-like methods to StreamNodes
* Remove unnecessary field

0.2.5
=====
* Add EagerSourceNode which directly takes a Stream

0.2.4
=====
* Add CopyNode to lazily copy a Stream

0.2.3
=====
* Make duration parameter in Schedule optional and default to 0

0.2.2
=====
* Interval#stopWhen can read other Streams from the CompiledStreamGraph

0.2.1
=====
* Include generated freezed files

0.2.0
=====
* Initial release
* Generate a DAG of StreamNodes which can be compiled to a DAG of Streams
* Recursively schedule items into a Stream
* Generate .dot files visualizing Stream DAGs
