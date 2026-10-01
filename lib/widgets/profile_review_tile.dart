import 'package:flutter/material.dart';

import '../services/play_review_service.dart';
import 'play_review_prompt.dart';

/// A voluntary direct link, always available regardless of prompt history.
class ProfileReviewTile extends StatefulWidget {
  const ProfileReviewTile({
    super.key,
    required this.foreground,
    this.enabled = true,
    this.service,
    this.canLaunch,
  });

  final Color foreground;
  final bool enabled;
  final PlayReviewService? service;
  final bool Function()? canLaunch;

  @override
  State<ProfileReviewTile> createState() => _ProfileReviewTileState();
}

class _ProfileReviewTileState extends State<ProfileReviewTile> {
  bool _opening = false;
  bool get _available =>
      mounted &&
      widget.enabled &&
      ModalRoute.of(context)?.isCurrent == true &&
      (WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed) ==
          AppLifecycleState.resumed &&
      (widget.canLaunch?.call() ?? reviewEnvironmentAvailable());

  Future<void> _open() async {
    if (_opening || !_available) return;
    setState(() => _opening = true);
    final opened = await (widget.service ?? PlayReviewService.instance)
        .openListing(canLaunch: () => _available);
    if (!mounted) return;
    setState(() => _opening = false);
    if (!opened && _available) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
        content: Text('No se pudo abrir Google Play. Vuelve a intentarlo.'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) => ListTile(
        key: const ValueKey('profile-play-review'),
        leading: Icon(Icons.rate_review_outlined, color: widget.foreground),
        title: Text('Valorar en Google Play',
            style: TextStyle(color: widget.foreground)),
        subtitle: _opening
            ? Text('Abriendo…', style: TextStyle(color: widget.foreground))
            : null,
        trailing: Icon(Icons.open_in_new, size: 20, color: widget.foreground),
        onTap: !widget.enabled || _opening ? null : _open,
      );
}
