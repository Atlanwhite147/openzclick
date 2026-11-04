import 'package:flutter_test/flutter_test.dart';
import 'package:openzclick/net/local_address.dart';

/// The interfaces of a Windows laptop that carries a VPN, Hyper-V and a
/// Bluetooth PAN, as `NetworkInterface.list` reports them there: the overlay
/// adapter is named with a capital letter, the virtual switch comes with a
/// bracketed qualifier, and the disconnected adapters hold link-local
/// addresses.
List<LocalInterface> windowsLaptop({
  String wifi = '192.168.1.18',
}) => <LocalInterface>[
  const LocalInterface(
    name: 'Connexion réseau Bluetooth',
    addresses: <String>['169.254.156.229'],
  ),
  const LocalInterface(
    name: 'vEthernet (Default Switch)',
    addresses: <String>['172.17.112.1'],
  ),
  const LocalInterface(
    name: 'Connexion au réseau local* 1',
    addresses: <String>['169.254.48.67'],
  ),
  LocalInterface(name: 'Wi-Fi', addresses: <String>[wifi]),
  const LocalInterface(name: 'Tailscale', addresses: <String>['100.76.28.61']),
];

void main() {
  test('the address shown to a phone is the Wi-Fi one, not the VPN overlay', () {
    // Measured on Windows: the adapter is named `Tailscale`, and the exclusion
    // list compared it case-sensitively, so the QR code carried an address no
    // phone on the home network could reach.
    expect(chooseLocalAddress(windowsLaptop()), '192.168.1.18');
  });

  test('a virtual switch and a Bluetooth PAN are never picked', () {
    final List<LocalInterface> interfaces = <LocalInterface>[
      const LocalInterface(
        name: 'vEthernet (Default Switch)',
        addresses: <String>['172.17.112.1'],
      ),
      const LocalInterface(
        name: 'Connexion réseau Bluetooth',
        addresses: <String>['169.254.156.229'],
      ),
    ];
    // Nothing usable: the screen says "this device" instead of a plausible
    // address that reaches nothing.
    expect(chooseLocalAddress(interfaces), isNull);
  });

  test('an overlay address alone is not a candidate', () {
    expect(
      chooseLocalAddress(const <LocalInterface>[
        LocalInterface(name: 'tailscale0', addresses: <String>['100.76.28.61']),
      ]),
      isNull,
    );
    // Even when the interface name is not on the list: 100.64/10 is a
    // carrier-grade NAT range, which only exists inside an overlay.
    expect(
      chooseLocalAddress(const <LocalInterface>[
        LocalInterface(name: 'eth9', addresses: <String>['100.76.28.61']),
      ]),
      isNull,
    );
  });

  test('a public address is a last resort, after every private one', () {
    expect(
      chooseLocalAddress(const <LocalInterface>[
        LocalInterface(name: 'eth0', addresses: <String>['203.0.113.9']),
        LocalInterface(name: 'eth1', addresses: <String>['10.0.0.4']),
      ]),
      '10.0.0.4',
    );
    expect(
      chooseLocalAddress(const <LocalInterface>[
        LocalInterface(name: 'eth0', addresses: <String>['203.0.113.9']),
      ]),
      '203.0.113.9',
    );
  });

  test('every private range is recognised, and nothing else is', () {
    for (final String address in <String>[
      '10.0.0.1',
      '10.255.255.254',
      '172.16.0.1',
      '172.31.255.254',
      '192.168.0.1',
      '192.168.1.18',
    ]) {
      expect(isPrivateIPv4(address), isTrue, reason: address);
    }
    for (final String address in <String>[
      '172.15.0.1',
      '172.32.0.1',
      '192.169.1.1',
      '169.254.1.1',
      '100.76.28.61',
      '8.8.8.8',
      'not-an-address',
      '',
    ]) {
      expect(isPrivateIPv4(address), isFalse, reason: address);
    }
  });

  test('the addresses that must never be offered', () {
    for (final String address in <String>[
      '127.0.0.1',
      '169.254.156.229',
      '100.76.28.61',
      '224.0.0.1',
      '0.0.0.0',
      '192.168.1',
      '192.168.1.300',
    ]) {
      expect(isUnusableIPv4(address), isTrue, reason: address);
    }
    expect(isUnusableIPv4('192.168.1.18'), isFalse);
  });
}
