/// Publication towards a training application: the transport of the host.
library;

export 'publisher_port.dart';
export 'web_publisher.dart' if (dart.library.io) 'network_publisher.dart';
