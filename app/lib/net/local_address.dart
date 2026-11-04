/// Which address to show a phone, when a host has several networks.
///
/// The choice is not cosmetic: the address is printed on the screen and encoded
/// in the QR code a rider scans, and a wrong one produces a page that loads
/// nothing, with no error anywhere. The traps are all on a real desktop:
///
///  * a VPN adapter (Tailscale, ZeroTier, WireGuard) is up and holds a
///    plausible-looking address that no phone on the home Wi-Fi can reach;
///  * a virtual switch (Hyper-V, VMware, VirtualBox) holds a private range of
///    its own, and is enumerated first on some Windows machines;
///  * a Bluetooth PAN and a disconnected adapter both sit on 169.254/16;
///  * the adapter is named `Tailscale` on Windows, with a capital letter.
///
/// So the choice is: prefer a real private LAN address, never a link-local or
/// a carrier-grade NAT one, and treat the interface names as hints rather than
/// as the rule.
library;

/// One network interface, reduced to what the choice needs.
class LocalInterface {
  /// Builds an interface entry.
  const LocalInterface({required this.name, required this.addresses});

  /// Interface name, as the platform reports it (`Wi-Fi`, `Tailscale`, ...).
  final String name;

  /// Addresses of the interface, in the order the platform reports them.
  final List<String> addresses;
}

/// Interface names that never carry the address a rider should type.
///
/// Compared case-insensitively and by prefix: Windows capitalises the adapter
/// name (`Tailscale`), and the virtual switches bracket a qualifier
/// (`vEthernet (Default Switch)`).
const List<String> _excludedPrefixes = <String>[
  'docker',
  'br-',
  'veth',
  'virbr',
  'lxc',
  'waydroid',
  'tun',
  'tap',
  'tailscale',
  'zerotier',
  'nordlynx',
  'vethernet',
  'vmware',
  'virtualbox',
  'wsl',
  'hyper-v',
];

/// Returns the address whose interface is plausibly on the rider's own network.
///
/// Returns `null` when no usable IPv4 address exists, which the caller reports
/// as "this device" rather than inventing one.
String? chooseLocalAddress(Iterable<LocalInterface> interfaces) {
  String? fallback;
  for (final LocalInterface interface in interfaces) {
    final String name = interface.name.toLowerCase();
    if (_excludedPrefixes.any(name.startsWith)) continue;
    for (final String address in interface.addresses) {
      // A link-local or overlay address is not a candidate at all: it is what
      // the wrong interface looks like, not a fallback.
      if (isUnusableIPv4(address)) continue;
      if (isPrivateIPv4(address)) return address;
      // A public address on a normal adapter is still better than nothing, but
      // only once every private one has been ruled out.
      fallback ??= address;
    }
  }
  return fallback;
}

/// True when [address] is an IPv4 address a home network can use.
///
/// Link-local (169.254/16) and carrier-grade NAT (100.64/10, what Tailscale
/// hands out) are excluded: the first means the adapter found no network, the
/// second means the address only exists inside an overlay.
bool isPrivateIPv4(String address) {
  final List<int>? octets = _octets(address);
  if (octets == null) return false;
  final int a = octets[0];
  final int b = octets[1];
  if (a == 10) return true;
  if (a == 172 && b >= 16 && b <= 31) return true;
  if (a == 192 && b == 168) return true;
  return false;
}

/// True when [address] must never be offered to a phone.
bool isUnusableIPv4(String address) {
  final List<int>? octets = _octets(address);
  if (octets == null) return true;
  final int a = octets[0];
  final int b = octets[1];
  if (a == 0 || a == 127) return true;
  if (a == 169 && b == 254) return true; // link-local
  if (a == 100 && b >= 64 && b <= 127) return true; // carrier-grade NAT
  if (a >= 224) return true; // multicast and reserved
  return false;
}

List<int>? _octets(String address) {
  final List<String> parts = address.split('.');
  if (parts.length != 4) return null;
  final List<int> octets = <int>[];
  for (final String part in parts) {
    final int? value = int.tryParse(part);
    if (value == null || value < 0 || value > 255) return null;
    octets.add(value);
  }
  return octets;
}
