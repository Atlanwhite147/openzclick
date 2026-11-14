/// The application's visual language: an instrument, not a dashboard.
///
/// A rider glances at this screen mid-effort, sweating, from arm's length. What
/// has to be readable in that glance is one number and one state. So the surface
/// is dark and quiet, the gear is set in tabular figures large enough to read
/// without focusing, and exactly one colour is spent on "engaged" — a warm signal
/// amber that appears nowhere else. Everything else is a hairline or a muted
/// label.
///
/// The alternative, and the reason this file exists, was Material's default:
/// every section in an identical rounded card with a soft shadow, a generic blue
/// seed, and no way to tell a status from a setting. Cards remain for things that
/// genuinely group, but the readout, the ladder and the shift paddles are drawn
/// here so that they cannot drift back into that shape.
library;

import 'package:flutter/material.dart';

/// Colours, spacing and radii, in one place.
abstract final class Tokens {
  /// The page behind everything.
  static const Color ink = Color(0xFF0B0F10);

  /// A grouped surface, one step above [ink].
  static const Color surface = Color(0xFF141A1C);

  /// A surface that expects a press.
  static const Color raised = Color(0xFF1C2427);

  /// Body text.
  static const Color text = Color(0xFFECF1F2);

  /// Labels, units, secondary sentences.
  static const Color muted = Color(0xFF8A979C);

  /// The engaged gear, a live link, the one thing to look at. Used once.
  static const Color signal = Color(0xFFFFC24B);

  /// Information that is neither a warning nor a confirmation.
  static const Color steel = Color(0xFF7FA8BE);

  /// Something the rider has to act on.
  static const Color alarm = Color(0xFFFF6B5A);

  /// A link that works, a battery that is fine.
  static const Color good = Color(0xFF63D2A4);

  /// Space between two blocks.
  static const double gap = 12;

  /// Padding inside a surface.
  static const double pad = 18;

  /// Corner radius of a surface.
  static const double radius = 16;

  /// Thickness of a rule.
  static const double hairline = 1;
}

/// Text styles that carry the instrument.
abstract final class Type {
  /// A number to read at a glance: tabular figures, tight spacing, no wobble.
  ///
  /// Tabular figures are the point: a gear that goes 9 → 10 must not shift the
  /// layout sideways, and a rider reads the change, not the movement.
  static TextStyle readout(BuildContext context) =>
      Theme.of(context).textTheme.displayLarge!.copyWith(
        fontSize: 76,
        height: 0.9,
        fontWeight: FontWeight.w600,
        letterSpacing: -2,
        color: Tokens.text,
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      );

  /// The unit or the total next to a readout.
  static TextStyle unit(BuildContext context) =>
      Theme.of(context).textTheme.titleMedium!
          .copyWith(color: Tokens.muted, fontWeight: FontWeight.w500);

  /// A section's name, in sentence case.
  static TextStyle section(BuildContext context) => Theme.of(context)
      .textTheme
      .labelLarge!
      .copyWith(
        color: Tokens.muted,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      );

  /// Small print: explanations, hints, report text.
  static TextStyle small(BuildContext context) =>
      Theme.of(context).textTheme.bodySmall!
          .copyWith(color: Tokens.muted, height: 1.35);
}

/// A one-line rule, the only separator this design uses.
class Hairline extends StatelessWidget {
  /// Creates a rule.
  const Hairline({this.indent = 0, super.key});

  /// Space kept free on the left, to align the rule with text.
  final double indent;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(left: indent),
      height: Tokens.hairline,
      color: Tokens.text.withValues(alpha: 0.08),
    );
  }
}

/// A small lamp and its sentence: the state of the link, of the publication.
///
/// A lamp rather than a chip: a chip is a label, and a rider reading "Connected"
/// in the same weight as "Settings" has to read both words to tell them apart.
class Lamp extends StatelessWidget {
  /// Creates a lamp.
  const Lamp({
    required this.on,
    required this.label,
    this.color = Tokens.good,
    this.blink = false,
    super.key,
  });

  /// Whether the lamp is lit.
  final bool on;

  /// The sentence next to it.
  final String label;

  /// Colour of the lit state.
  final Color color;

  /// Whether the lit state is still being established.
  final bool blink;

  @override
  Widget build(BuildContext context) {
    final Color lit = blink ? Tokens.signal : color;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on ? lit : Colors.transparent,
            border: Border.all(
              color: on ? lit : Tokens.muted.withValues(alpha: 0.5),
              width: 1.5,
            ),
            boxShadow: on
                ? <BoxShadow>[
                    BoxShadow(
                      color: lit.withValues(alpha: 0.45),
                      blurRadius: 8,
                    ),
                  ]
                : null,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium!
              .copyWith(color: on ? Tokens.text : Tokens.muted),
        ),
      ],
    );
  }
}

/// The cassette, drawn as ticks: where the rider is on the ladder.
///
/// The readout says which gear; the ladder says how much room is left, which is
/// the question a rider actually has before a climb. It replaces a sentence like
/// "9 / 12", which answers the same question in words.
class GearLadder extends StatelessWidget {
  /// Creates a ladder of [count] gears, [gear] being the engaged one.
  const GearLadder({required this.gear, required this.count, super.key});

  /// Engaged gear, one-based.
  final int gear;

  /// Number of gears.
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        for (int i = 1; i <= count; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i == count ? 0 : 4),
              child: Container(
                key: i == gear ? const Key('gear-ladder-engaged') : null,
                height: i == gear ? 22 : 10,
                decoration: BoxDecoration(
                  color: i == gear
                      ? Tokens.signal
                      : i < gear
                      ? Tokens.muted.withValues(alpha: 0.55)
                      : Tokens.muted.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A shift paddle: the two controls a rider presses without looking.
class Paddle extends StatelessWidget {
  /// Creates a paddle.
  const Paddle({
    required this.label,
    required this.icon,
    required this.onPressed,
    super.key,
  });

  /// What the press does, in the rider's words.
  final String label;

  /// Direction of the shift.
  final IconData icon;

  /// Null disables the paddle, at the ends of the ladder.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      child: Material(
        color: enabled ? Tokens.raised : Tokens.raised.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(Tokens.radius),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(Tokens.radius),
          child: Container(
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Tokens.radius),
              border: Border.all(
                color: Tokens.text.withValues(alpha: enabled ? 0.10 : 0.04),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  icon,
                  size: 22,
                  color: enabled ? Tokens.text : Tokens.muted,
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: Theme.of(context).textTheme.titleMedium!.copyWith(
                    color: enabled ? Tokens.text : Tokens.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A grouped block of content, with a rule instead of a shadow.
class Panel extends StatelessWidget {
  /// Creates a panel around [child].
  const Panel({required this.child, this.title, this.trailing, super.key});

  /// The content.
  final Widget child;

  /// Optional sentence-case name of the block.
  final String? title;

  /// Optional control aligned with the title.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    // A Material, not a decorated box: a ListTile or an ExpansionTile inside a
    // coloured container paints its background and its ink on the nearest
    // Material ancestor, which a plain box hides. Flutter asserts on it, and the
    // assertion is right — the press feedback would have been invisible.
    return Padding(
      padding: const EdgeInsets.only(bottom: Tokens.gap),
      child: Material(
        color: Tokens.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radius),
          side: BorderSide(color: Tokens.text.withValues(alpha: 0.06)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(Tokens.pad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (title != null) ...<Widget>[
                Row(
                  children: <Widget>[
                    Expanded(child: Text(title!, style: Type.section(context))),
                    ?trailing,
                  ],
                ),
                const SizedBox(height: Tokens.gap),
              ],
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// The application's theme, built from the tokens above.
ThemeData openzclickTheme() {
  final ColorScheme scheme =
      ColorScheme.fromSeed(
        seedColor: Tokens.signal,
        brightness: Brightness.dark,
      ).copyWith(
        primary: Tokens.signal,
        onPrimary: Tokens.ink,
        secondary: Tokens.steel,
        onSecondary: Tokens.ink,
        surface: Tokens.surface,
        onSurface: Tokens.text,
        onSurfaceVariant: Tokens.muted,
        error: Tokens.alarm,
        onError: Tokens.ink,
        outline: Tokens.text.withValues(alpha: 0.14),
      );

  final ThemeData base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Tokens.ink,
  );

  return base.copyWith(
    appBarTheme: AppBarTheme(
      backgroundColor: Tokens.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: base.textTheme.titleLarge!.copyWith(
        color: Tokens.text,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Tokens.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Tokens.signal.withValues(alpha: 0.16),
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>(
        (Set<WidgetState> states) => base.textTheme.labelMedium!.copyWith(
          color: states.contains(WidgetState.selected)
              ? Tokens.text
              : Tokens.muted,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w600
              : FontWeight.w400,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith<IconThemeData>(
        (Set<WidgetState> states) => IconThemeData(
          size: 22,
          color: states.contains(WidgetState.selected)
              ? Tokens.signal
              : Tokens.muted,
        ),
      ),
    ),
    cardTheme: CardThemeData(
      color: Tokens.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.radius),
        side: BorderSide(color: Tokens.text.withValues(alpha: 0.06)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Tokens.signal,
        foregroundColor: Tokens.ink,
        minimumSize: const Size(0, 48),
        textStyle: base.textTheme.titleSmall!.copyWith(
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radius - 4),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Tokens.text,
        minimumSize: const Size(0, 48),
        side: BorderSide(color: Tokens.text.withValues(alpha: 0.18)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radius - 4),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: Tokens.signal),
    ),
    dividerTheme: DividerThemeData(
      color: Tokens.text.withValues(alpha: 0.08),
      thickness: Tokens.hairline,
      space: Tokens.pad,
    ),
    expansionTileTheme: ExpansionTileThemeData(
      backgroundColor: Colors.transparent,
      collapsedBackgroundColor: Colors.transparent,
      iconColor: Tokens.muted,
      collapsedIconColor: Tokens.muted,
      textColor: Tokens.text,
      collapsedTextColor: Tokens.text,
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(top: 8),
      shape: const Border(),
      collapsedShape: const Border(),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: Tokens.muted,
      contentPadding: EdgeInsets.zero,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Tokens.raised,
      contentTextStyle: base.textTheme.bodyMedium!.copyWith(color: Tokens.text),
      behavior: SnackBarBehavior.floating,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: Tokens.signal,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith<Color>(
        (Set<WidgetState> states) => states.contains(WidgetState.selected)
            ? Tokens.signal
            : Tokens.muted,
      ),
      trackColor: WidgetStateProperty.resolveWith<Color>(
        (Set<WidgetState> states) => states.contains(WidgetState.selected)
            ? Tokens.signal.withValues(alpha: 0.35)
            : Tokens.muted.withValues(alpha: 0.18),
      ),
    ),
  );
}
