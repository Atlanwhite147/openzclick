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
///
/// The palette is taken from the pod itself. A Zwift Click has four buttons and
/// four colours — orange, rose, blue, green — and those four are the only accents
/// this application spends: orange for the harder gear, rose for the easier one,
/// blue for information, green for a link that works. Nothing here was chosen
/// because it looks technical; it was chosen because the rider is holding it.
abstract final class Tokens {
  /// The page behind everything: a cool paper, not a warm cream.
  static const Color paper = Color(0xFFF5F7F9);

  /// A surface that groups content.
  static const Color surface = Color(0xFFFFFFFF);

  /// A surface that expects a press, or a field.
  static const Color raised = Color(0xFFEDF1F4);

  /// Body text.
  static const Color ink = Color(0xFF11171B);

  /// Labels, units, secondary sentences.
  static const Color muted = Color(0xFF66727C);

  /// The pod's left button (Z): the harder gear.
  static const Color orange = Color(0xFFE8622C);

  /// The pod's bottom button (B): the easier gear.
  static const Color rose = Color(0xFFD6427E);

  /// The pod's top button (Y): information.
  static const Color blue = Color(0xFF2F6BEA);

  /// The pod's right button (A): a link that works.
  static const Color green = Color(0xFF17A673);

  /// Kept for the names the rest of the code already uses.
  static const Color text = ink;
  static const Color signal = orange;
  static const Color steel = blue;
  static const Color good = green;
  static const Color alarm = rose;

  /// Space between two blocks.
  static const double gap = 14;

  /// Padding inside a surface.
  static const double pad = 20;

  /// Corner radius of a surface.
  static const double radius = 20;

  /// Thickness of a rule.
  static const double hairline = 1;

  /// The shadow a surface carries: one soft lift, never a glow.
  static List<BoxShadow> get lift => <BoxShadow>[
    BoxShadow(
      color: ink.withValues(alpha: 0.05),
      blurRadius: 2,
      offset: const Offset(0, 1),
    ),
    BoxShadow(
      color: ink.withValues(alpha: 0.06),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
  ];
}

/// Text styles that carry the instrument.
abstract final class Type {
  /// A number to read at a glance: tabular figures, tight spacing, no wobble.
  ///
  /// Tabular figures are the point: a gear that goes 9 → 10 must not shift the
  /// layout sideways, and a rider reads the change, not the movement.
  static TextStyle readout(BuildContext context) =>
      Theme.of(context).textTheme.displayLarge!.copyWith(
        fontSize: 84,
        height: 0.9,
        fontWeight: FontWeight.w600,
        letterSpacing: -3,
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
      color: Tokens.ink.withValues(alpha: 0.08),
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
    this.color = Tokens.orange,
    super.key,
  });

  /// The pod colour of this shift: orange up, rose down.
  final Color color;

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
      // Solid, in the pod's own colour. A tinted button at twelve percent is a
      // button nobody notices, and the whole point of the palette is that the
      // screen and the object in the rider's hand look like the same thing.
      child: Material(
        color: enabled ? color : Tokens.raised,
        borderRadius: BorderRadius.circular(Tokens.radius),
        elevation: enabled ? 2 : 0,
        shadowColor: enabled ? color.withValues(alpha: 0.45) : null,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(Tokens.radius),
          child: SizedBox(
            height: 68,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  icon,
                  size: 24,
                  color: enabled ? Colors.white : Tokens.muted,
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: Theme.of(context).textTheme.titleMedium!.copyWith(
                    color: enabled ? Colors.white : Tokens.muted,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
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

/// One button of the pod, in its own colour, with what the application does with
/// it.
///
/// It answers the question a rider actually asks at a controller screen — "which
/// one did I just press?" — and it is the only place where all four pod colours
/// appear side by side.
class ButtonSwatch extends StatelessWidget {
  /// Creates a swatch.
  const ButtonSwatch({
    required this.label,
    required this.color,
    required this.meaning,
    super.key,
  });

  /// The letter printed on the button.
  final String label;

  /// The colour of that button.
  final Color color;

  /// What the application does with it.
  final String meaning;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 16,
            height: 16,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            meaning,
            style: Theme.of(context).textTheme.labelMedium!
                .copyWith(color: color, fontWeight: FontWeight.w600),
          ),
        ],
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
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Tokens.radius),
          boxShadow: Tokens.lift,
        ),
        child: Material(
          color: Tokens.surface,
          clipBehavior: Clip.antiAlias,
          borderRadius: BorderRadius.circular(Tokens.radius),
          child: Padding(
            padding: const EdgeInsets.all(Tokens.pad),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (title != null) ...<Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(title!, style: Type.section(context)),
                      ),
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
      ),
    );
  }
}

/// The application's theme, built from the tokens above.
///
/// Light, because the screen sits in a lit room and the numbers have to read from
/// a metre away. The four pod colours are the only accents: a Material seed
/// colour would have produced a palette with no relation to the thing in the
/// rider's hands.
ThemeData openzclickTheme() {
  final ColorScheme scheme =
      ColorScheme.fromSeed(
        seedColor: Tokens.orange,
        brightness: Brightness.light,
      ).copyWith(
        primary: Tokens.orange,
        onPrimary: Colors.white,
        secondary: Tokens.blue,
        onSecondary: Colors.white,
        surface: Tokens.surface,
        onSurface: Tokens.ink,
        onSurfaceVariant: Tokens.muted,
        error: Tokens.rose,
        onError: Colors.white,
        outline: Tokens.ink.withValues(alpha: 0.14),
        outlineVariant: Tokens.ink.withValues(alpha: 0.08),
      );

  final ThemeData base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Tokens.paper,
    fontFamily: null,
  );

  return base.copyWith(
    appBarTheme: AppBarTheme(
      backgroundColor: Tokens.paper,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: base.textTheme.titleLarge!.copyWith(
        color: Tokens.ink,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Tokens.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Tokens.orange.withValues(alpha: 0.14),
      elevation: 0,
      height: 70,
      labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>(
        (Set<WidgetState> states) => base.textTheme.labelMedium!.copyWith(
          color: states.contains(WidgetState.selected)
              ? Tokens.ink
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
              ? Tokens.orange
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
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Tokens.orange,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 52),
        textStyle: base.textTheme.titleSmall!.copyWith(
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radius - 6),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Tokens.ink,
        minimumSize: const Size(0, 48),
        side: BorderSide(color: Tokens.ink.withValues(alpha: 0.16)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radius - 6),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: Tokens.orange),
    ),
    dividerTheme: DividerThemeData(
      color: Tokens.ink.withValues(alpha: 0.08),
      thickness: Tokens.hairline,
      space: Tokens.pad,
    ),
    expansionTileTheme: ExpansionTileThemeData(
      backgroundColor: Colors.transparent,
      collapsedBackgroundColor: Colors.transparent,
      iconColor: Tokens.muted,
      collapsedIconColor: Tokens.muted,
      textColor: Tokens.ink,
      collapsedTextColor: Tokens.ink,
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
      backgroundColor: Tokens.ink,
      contentTextStyle: base.textTheme.bodyMedium!.copyWith(
        color: Colors.white,
      ),
      behavior: SnackBarBehavior.floating,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: Tokens.orange,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith<Color>(
        (Set<WidgetState> states) => states.contains(WidgetState.selected)
            ? Colors.white
            : Tokens.surface,
      ),
      trackColor: WidgetStateProperty.resolveWith<Color>(
        (Set<WidgetState> states) => states.contains(WidgetState.selected)
            ? Tokens.green
            : Tokens.ink.withValues(alpha: 0.14),
      ),
    ),
  );
}
