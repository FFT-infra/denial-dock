import 'package:denial_flutter_sdk/state.dart';
import 'package:denial_flutter_sdk/system_services.dart' show WifiNetwork;
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bar_icons.dart';
import '../bar_type.dart';
import 'mac_kit.dart';

/// The "Join “SSID”" dialog.
///
/// Ports NextKDE `NetworkPanel.qml`'s `networkDialogOverlay`. The reference
/// deliberately makes this a system dialog rather than an inline row: it closes
/// the Wi-Fi list first, then shows a 420 × 292 card with a 30 pt cancel ring
/// top-left, a 30 pt join ring top-right, a 58 × 48 blue Wi-Fi glyph, the
/// network's name at 18 bold, a 42 pt password field on a 14-radius pill, a
/// "✓ Password saved / Change / Forget" strip for a known profile, and the
/// "stored securely by NetworkManager" footnote.
///
/// The reference's note on focus is the reason this is a separate popup at all:
/// the field has to own keyboard focus, and a field nested in a scrolling list
/// competes with the list for it. Denial's popup host captures the keyboard
/// (`ShellKeyboardPolicy.capture`) and its `FocusScope` requests focus, so the
/// field can take the keys directly.
class WifiJoinDialog extends ConsumerStatefulWidget {
  const WifiJoinDialog({
    required this.network,
    required this.onClose,
    super.key,
  });

  final WifiNetwork network;
  final VoidCallback onClose;

  /// NextKDE sizes the card `min(420, overlay - 44)`; 292 is its personal
  /// (non-enterprise) height.
  static const double width = 420;
  static const double height = 292;

  @override
  ConsumerState<WifiJoinDialog> createState() => _WifiJoinDialogState();
}

class _WifiJoinDialogState extends ConsumerState<WifiJoinDialog> {
  final TextEditingController _password = TextEditingController();
  final FocusNode _focus = FocusNode();

  /// A known profile joins with the secret NetworkManager already holds, so the
  /// field starts hidden behind the "Password saved" strip.
  late bool _useSaved = widget.network.saved;

  /// Forget asks twice, the way the reference's strip does.
  bool _confirmForget = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // The popup's FocusScope claims focus in its own first frame; asking after
    // that frame is what actually puts the caret in the field.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_useSaved) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _password.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _busy => ref
      .watch(networkConnectivityProvider)
      .busyNetworks
      .contains(widget.network.identity);

  Future<void> _join() async {
    if (_busy) return;
    final password = _password.text;
    if (!_useSaved && password.isEmpty) {
      setState(() => _error = 'Enter the Wi‑Fi password');
      _focus.requestFocus();
      return;
    }
    setState(() => _error = null);
    final controller = ref.read(networkConnectivityProvider.notifier);
    await controller.connect(
      widget.network,
      password: _useSaved || password.isEmpty ? null : password,
    );
    if (!mounted) return;
    // `connect` reports failure through the provider rather than by throwing,
    // so the dialog reads the result back instead of catching.
    final error = ref.read(networkConnectivityProvider).error;
    if (error != null) {
      setState(() => _error = error);
      _focus.requestFocus();
      return;
    }
    widget.onClose();
  }

  Future<void> _forget() async {
    if (!_confirmForget) {
      setState(() => _confirmForget = true);
      return;
    }
    final controller = ref.read(networkConnectivityProvider.notifier);
    await controller.forget(widget.network);
    if (!mounted) return;
    final error = ref.read(networkConnectivityProvider).error;
    if (error != null) {
      setState(() {
        _confirmForget = false;
        _error = error;
      });
      return;
    }
    // The profile is gone, so the dialog turns into the new-network state
    // instead of making the user pick the row again.
    setState(() {
      _useSaved = false;
      _confirmForget = false;
      _error = null;
    });
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final dark = theme.colors.brightness == Brightness.dark;
    final ink = theme.colors.textPrimary;
    final secondary = ink.withValues(alpha: 0.62);
    final controlFill = dark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.black.withValues(alpha: 0.05);
    final controlBorder = dark
        ? Colors.white.withValues(alpha: 0.16)
        : Colors.black.withValues(alpha: 0.08);

    final ssid = widget.network.ssid;
    final subtitle = _busy
        ? 'Joining this WLAN…'
        : (_useSaved
              ? 'The saved password will be used to join this WLAN.'
              : 'Enter the password to join this WLAN.');

    return SizedBox(
      width: WifiJoinDialog.width,
      height: WifiJoinDialog.height,
      child: Stack(
        children: <Widget>[
          // Cancel ring, top-left.
          Positioned(
            left: 13,
            top: 12,
            child: _RingButton(
              glyph: BarIcons.xmark,
              glyphSize: 15,
              fill: controlFill,
              border: controlBorder,
              ink: ink,
              onTap: widget.onClose,
            ),
          ),
          // Join ring, top-right: a busy arc while the connection is in flight.
          Positioned(
            right: 13,
            top: 12,
            child: _RingButton(
              glyph: _busy ? null : BarIcons.checkmark,
              busy: _busy,
              glyphSize: 15,
              fill: controlFill,
              border: controlBorder,
              ink: ink,
              onTap: _busy ? null : _join,
            ),
          ),
          Positioned(
            top: 43,
            left: 0,
            right: 0,
            child: Center(
              child: BarGlyph(BarIcons.wifi, size: 44, color: macBlue),
            ),
          ),
          Positioned(
            left: 22,
            right: 22,
            top: 100,
            bottom: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'Join “$ssid”',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BarType.title.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  subtitle,
                  style: BarType.caption.copyWith(
                    fontSize: 13,
                    color: secondary,
                  ),
                ),
                const SizedBox(height: 11),
                if (!_useSaved)
                  _PasswordPill(
                    controller: _password,
                    focusNode: _focus,
                    dark: dark,
                    ink: ink,
                    hint: 'Password',
                    onSubmitted: _join,
                  )
                else
                  _SavedStrip(
                    ink: ink,
                    secondary: secondary,
                    busy: _busy,
                    confirmForget: _confirmForget,
                    onChange: () {
                      setState(() {
                        _useSaved = false;
                        _confirmForget = false;
                      });
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) _focus.requestFocus();
                      });
                    },
                    onForget: _forget,
                  ),
                if (!_useSaved) ...<Widget>[
                  const SizedBox(height: 9),
                  Text(
                    'The password will be stored securely by NetworkManager.',
                    style: BarType.caption.copyWith(
                      fontSize: 12,
                      color: ink.withValues(alpha: 0.45),
                    ),
                  ),
                ],
                if (_error != null) ...<Widget>[
                  const SizedBox(height: 9),
                  Text(
                    _error!,
                    style: BarType.caption.copyWith(
                      fontSize: 12,
                      color: const Color(0xffff6b61),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The reference's 30 pt control ring: a circle with a 1 px rim, a 0.55
/// opacity while the join is in flight, and a 900 ms arc when it is busy.
class _RingButton extends StatefulWidget {
  const _RingButton({
    required this.fill,
    required this.border,
    required this.ink,
    required this.glyphSize,
    this.glyph,
    this.busy = false,
    this.onTap,
  });

  final Color fill;
  final Color border;
  final Color ink;
  final double glyphSize;
  final IconData? glyph;
  final bool busy;
  final VoidCallback? onTap;

  @override
  State<_RingButton> createState() => _RingButtonState();
}

class _RingButtonState extends State<_RingButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.92 : 1,
          duration: const Duration(milliseconds: 90),
          curve: Curves.easeOut,
          child: Opacity(
            opacity: widget.busy ? 0.55 : 1,
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: _hovered && enabled
                    ? Color.alphaBlend(
                        widget.ink.withValues(alpha: 0.08),
                        widget.fill,
                      )
                    : widget.fill,
                shape: BoxShape.circle,
                border: Border.all(color: widget.border),
              ),
              child: Center(
                child: widget.busy
                    ? BarGlyph(BarIcons.ellipsis, size: 15, color: widget.ink)
                    : BarGlyph(
                        widget.glyph!,
                        size: widget.glyphSize,
                        color: widget.ink,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The 42 pt password field: a 14-radius pill that takes a 1 px blue rim while
/// it holds focus, matching the reference's `activeFocus` border.
class _PasswordPill extends StatefulWidget {
  const _PasswordPill({
    required this.controller,
    required this.focusNode,
    required this.dark,
    required this.ink,
    required this.hint,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool dark;
  final Color ink;
  final String hint;
  final VoidCallback onSubmitted;

  @override
  State<_PasswordPill> createState() => _PasswordPillState();
}

class _PasswordPillState extends State<_PasswordPill> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocus);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocus);
    super.dispose();
  }

  void _onFocus() {
    if (mounted) setState(() => _focused = widget.focusNode.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: widget.dark
            ? Colors.white.withValues(alpha: 0.10)
            : Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _focused
              ? macBlue.withValues(alpha: 0.80)
              : Colors.transparent,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: TextField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          obscureText: true,
          style: BarType.caption.copyWith(fontSize: 14, color: widget.ink),
          cursorColor: macBlue,
          onSubmitted: (_) => widget.onSubmitted(),
          decoration: InputDecoration(
            isDense: true,
            border: InputBorder.none,
            hintText: widget.hint,
            hintStyle: BarType.caption.copyWith(
              fontSize: 14,
              color: widget.ink.withValues(alpha: 0.45),
            ),
          ),
        ),
      ),
    );
  }
}

/// The known-profile strip: "✓ Password saved" on the left, then Change and
/// Forget on the right, with Forget asking a second time.
class _SavedStrip extends StatelessWidget {
  const _SavedStrip({
    required this.ink,
    required this.secondary,
    required this.busy,
    required this.confirmForget,
    required this.onChange,
    required this.onForget,
  });

  final Color ink;
  final Color secondary;
  final bool busy;
  final bool confirmForget;
  final VoidCallback onChange;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: macBlue.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: macBlue.withValues(alpha: 0.36)),
      ),
      child: Row(
        children: <Widget>[
          const SizedBox(width: 13),
          Expanded(
            child: Text(
              confirmForget ? 'Forget this network?' : '✓  Password saved',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: BarType.caption.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: ink,
              ),
            ),
          ),
          _StripAction(
            label: confirmForget ? 'Cancel' : 'Change',
            color: secondary,
            onTap: confirmForget ? onForget : onChange,
          ),
          const SizedBox(width: 14),
          _StripAction(
            label: busy ? '…' : (confirmForget ? 'Confirm' : 'Forget'),
            color: confirmForget ? const Color(0xffd93025) : secondary,
            enabled: !busy,
            onTap: onForget,
          ),
          const SizedBox(width: 13),
        ],
      ),
    );
  }
}

class _StripAction extends StatelessWidget {
  const _StripAction({
    required this.label,
    required this.color,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 8),
          child: Text(
            label,
            style: BarType.caption.copyWith(fontSize: 11, color: color),
          ),
        ),
      ),
    );
  }
}
