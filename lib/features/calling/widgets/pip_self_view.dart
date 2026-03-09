import 'package:flutter/material.dart';
import 'package:lattice/features/calling/models/call_participant.dart';
import 'package:lattice/features/calling/widgets/participant_tile.dart';

class PipSelfView extends StatefulWidget {
  const PipSelfView({required this.participant, super.key});

  final CallParticipant participant;

  static const double width = 120;
  static const double height = 160;
  static const double _margin = 16;

  @override
  State<PipSelfView> createState() => _PipSelfViewState();
}

class _PipSelfViewState extends State<PipSelfView> {
  double? _x;
  double? _y;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxX = constraints.maxWidth - PipSelfView.width - PipSelfView._margin;
        final maxY = constraints.maxHeight - PipSelfView.height - PipSelfView._margin;
        final x = _x ?? maxX;
        final y = _y ?? maxY;

        return Positioned(
          left: x.clamp(PipSelfView._margin, maxX),
          top: y.clamp(PipSelfView._margin, maxY),
          child: GestureDetector(
            onPanUpdate: (details) {
              setState(() {
                _x = ((_x ?? maxX) + details.delta.dx).clamp(PipSelfView._margin, maxX);
                _y = ((_y ?? maxY) + details.delta.dy).clamp(PipSelfView._margin, maxY);
              });
            },
            onPanEnd: (_) => _snapToCorner(constraints),
            child: SizedBox(
              width: PipSelfView.width,
              height: PipSelfView.height,
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: ParticipantTile(participant: widget.participant),
              ),
            ),
          ),
        );
      },
    );
  }

  void _snapToCorner(BoxConstraints constraints) {
    final maxX = constraints.maxWidth - PipSelfView.width - PipSelfView._margin;
    final maxY = constraints.maxHeight - PipSelfView.height - PipSelfView._margin;
    final cx = _x ?? maxX;
    final cy = _y ?? maxY;

    final midX = constraints.maxWidth / 2;
    final midY = constraints.maxHeight / 2;

    setState(() {
      _x = cx < midX ? PipSelfView._margin : maxX;
      _y = cy < midY ? PipSelfView._margin : maxY;
    });
  }
}
