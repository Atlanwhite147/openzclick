/// Transport layer of the bridge.
///
/// Four mediums, a single contract ([Transport]):
/// * [MdnsTcpTransport] - TCP server advertised over mDNS, fully functional;
/// * [BlePeripheralTransport] - Bluetooth peripheral, complete skeleton, native
///   backend to be supplied;
/// * [LocalInjectionTransport] - key and tap injection into the local session;
/// * [TrainerProxy] - grade relay to a home trainer, FTMS link to be supplied.
library;

export 'ble_peripheral_transport.dart';
export 'events.dart';
export 'local_injection_transport.dart';
export 'mdns_advertiser.dart';
export 'mdns_tcp_transport.dart';
export 'tcp_server.dart';
export 'trainer_proxy.dart';
export 'transport.dart';
