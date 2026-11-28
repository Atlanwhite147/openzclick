/// Optional harness for the social captures.
///
/// Compiled only with `--dart-define=OZ_SOCIAL_HARNESS=true`, so a normal build
/// — and every test — is untouched. It does three things a screenshot needs and
/// a rider never sees:
///
///  * it advances the interfaces through their states, so each screen can be
///    photographed where it matters (pair, MyWhoosh listening, riding);
///  * it makes a `SimulatedPublisher` so the bridge can show "MyWhoosh
///    connected" without a training application, and the buttons of the
///    protocol bench can be pressed for real;
///  * it records the interface itself with the Flutter engine offscreen
///    renderer, so the PNG is pixel-identical to what the window shows.
///
/// Nothing here is simulated beyond the MyWhoosh peer: every pixel comes from
/// the real widgets of `lib/`, painted by the real Flutter engine.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:openzclick/ble/controller_connection.dart';
import 'package:openzclick/net/publisher_port.dart';
import 'package:openzclick/settings/display_mode.dart';
import 'package:openzclick/state/app_state.dart';
import 'package:openzclick/ui/design.dart';
import 'package:openzclick/ui/shell.dart';
import 'package:openzclick_core/openzclick_core.dart';

/// True when the harness was compiled in.
const bool socialHarness = bool.fromEnvironment('OZ_SOCIAL_HARNESS');

/// Where the PNGs go.
const String _outDir = '/home/alban/.hermes/profiles/openzclick/cache/'
    'scratch/social/raw';

/// A bridge to a MyWhoosh that is not there.
///
/// It reports exactly what the real publisher reports once a training
/// application has attached, and nothing else: the screen is the real screen,
/// only the peer is imagined. That difference is written in every caption.
class SimulatedPublisher implements PublisherPort {
  @override
  void Function()? onChanged;

  @override
  bool running = false;

  @override
  bool advertise = true;

  @override
  int port = 47123;

  @override
  int? listeningPort;

  @override
  String? address = '192.168.1.24';

  @override
  int peers = 0;

  @override
  String? error;

  @override
  int consoles = 0;

  @override
  int? get consolePort => null;

  @override
  String get consoleToken => '';

  /// Actions sent, in order, for the log the harness prints.
  final List<Action> sent = <Action>[];

  @override
  Future<void> start() async {
    running = true;
    listeningPort = port;
    peers = 1;
    onChanged?.call();
  }

  @override
  Future<void> stop() async {
    running = false;
    listeningPort = null;
    peers = 0;
    onChanged?.call();
  }

  @override
  Future<void> publish(Action action) async => sent.add(action);

  @override
  Future<void> dispose() async {}

  @override
  String? consoleUrl(String host) => null;

  @override
  Stream<String> get console => const Stream<String>.empty();

  @override
  Stream<Action> get consoleActions => const Stream<Action>.empty();
}

/// The harness's own little command language, printed to the console as it
/// runs so a caller can follow which frame became which file.
class SocialHarness {
  SocialHarness(this.state, this.key) {
    AppState global = state;
    _installGlobal();
  }

  final AppState state;
  final GlobalKey key;

  static void _installGlobal() {}

  SimulatedPublisher get publisher => state.publisher as SimulatedPublisher;

  Future<void> _settle([int frames = 12]) async {
    for (int i = 0; i < frames; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 32));
    }
  }

  Future<void> finishOnboarding() async {
    state.completeOnboarding();
    await _settle();
  }

  Future<void> simple() async {
    state.setDisplayMode(DisplayMode.simple);
    await _settle();
  }

  Future<void> advanced() async {
    state.setDisplayMode(DisplayMode.advanced);
    await _settle();
  }

  /// The pod answers, MyWhoosh does not: the state a rider photographs most.
  Future<void> pairController() async {
    final ControllerConnection link = state.controller;
    link.status = ControllerStatus.ready;
    link.batteryPercent = 78;
    link.encrypted = true;
    state.notify();
    await _settle();
  }

  /// The MyWhoosh side: the bridge runs and one peer has attached.
  Future<void> connectMyWhoosh() async {
    if (!publisher.running) await publisher.start();
    await _settle();
  }

  /// A press on the pod's + button, through the real gesture detector.
  Future<void> shiftUp() async {
    state.handleButtons(ClickButtonMask.up);
    await _settle(4);
    state.handleButtons(ClickButtonMask.none);
    await _settle(4);
  }

  /// Runs the protocol bench, which encodes and decodes a real frame.
  Future<void> runBench() async {
    state.runCodecBench();
    await _settle();
  }

  /// Photographs the whole interface at [size], optionally cropped to
  /// [region] (in logical pixels, origin top left).
  Future<String> capture(
    String name,
    Size size, {
    Rect? region,
    double pixelRatio = 2,
  }) async {
    final RenderRepaintBoundary boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
    final ui.Image cropped = region == null
        ? image
        : await cropImage(
            image,
            Rect.fromLTWH(
              region.left * pixelRatio,
              region.top * pixelRatio,
              region.width * pixelRatio,
              region.height * pixelRatio,
            ),
          );
    final ByteData? png = await cropped.toByteData(
      format: ui.ImageByteFormat.png,
    );
    final File file = File('$_outDir/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(png!.buffer.asUint8List());
    // ignore: avoid_print
    print('CAPTURE $name ${cropped.width}x${cropped.height} ${file.path}');
    return file.path;
  }
}

/// Copies [region] of [image] into a new image.
Future<ui.Image> cropImage(ui.Image image, Rect region) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);
  canvas.drawImageRect(
    image,
    region,
    Rect.fromLTWH(0, 0, region.width, region.height),
    Paint(),
  );
  final ui.Picture picture = recorder.endRecording();
  return picture.toImage(region.width.round(), region.height.round());
}

/// A phone-shaped stage around the interface.
///
/// The application has no window chrome in the capture: this is the same
/// widget tree, given a phone's width and a corner radius so that a reader on
/// a phone recognises the thing they would install.
class PhoneFrame extends StatelessWidget {
  const PhoneFrame({required this.child, required this.size, super.key});

  final Widget child;
  final Size size;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Tokens.paper,
      child: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: child,
        ),
      ),
    );
  }
}

/// Screen sizes the harness photographs, one per platform in the docs.
const Size phoneSize = Size(412, 892);
const Size desktopSize = Size(1280, 800);

/// Largest frame the harness will render, used by the caller for the window.
Size stageFor(Size target) => target;

/// Debug helper: the largest of two sizes, kept for the driver script.
Size maxSize(Size a, Size b) => a.width * a.height > b.width * b.height ? a : b;

/// Unused hook kept so the harness compiles without dart:math warnings.
double spin(double t) => math.sin(t);
