import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../game/voice_controller.dart';
import '../../i18n.dart';
import '../../theme.dart';
import 'common.dart';

/// Optional voice chat controls (start, end, mute microphone, mute speaker).
class VoiceBar extends StatelessWidget {
  const VoiceBar({super.key});

  String _statusKey(VoiceController v) {
    if (v.reconnecting) return 'voiceReconnecting';
    switch (v.state) {
      case VoiceState.calling:
        return 'voiceCalling';
      case VoiceState.incoming:
        return 'voiceIncoming';
      case VoiceState.connecting:
        return 'voiceConnecting';
      case VoiceState.connected:
        return 'voiceConnected';
      case VoiceState.idle:
        return v.canCall ? 'voiceIdle' : 'voiceNeedPlayer';
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = context.watch<VoiceController>();
    final busy = v.state == VoiceState.calling || v.state == VoiceState.connecting || v.reconnecting;
    const red = Color(0xFFEF4444);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: LC.card2(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: LC.border(context)),
      ),
      child: Column(children: [
        Row(children: [
          Icon(Icons.mic_rounded, size: 18, color: LC.soft(context)),
          const SizedBox(width: 8),
          Text(context.tr('voice'), style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(width: 10),
          Expanded(
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              if (busy) ...[
                const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  context.tr(_statusKey(v)),
                  textAlign: TextAlign.end,
                  style: TextStyle(fontSize: 12, color: LC.soft(context)),
                ),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        if (v.state == VoiceState.idle)
          SizedBox(
            width: double.infinity,
            child: GradientButton(
              label: context.tr('voiceStart'),
              icon: Icons.call_rounded,
              compact: true,
              onPressed: v.canCall ? v.startCall : null,
            ),
          )
        else if (v.inCall)
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: red, minimumSize: const Size.fromHeight(44)),
                onPressed: v.endCall,
                icon: const Icon(Icons.call_end_rounded),
                label: Text(context.tr('voiceEnd')),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.outlined(
              tooltip: context.tr(v.micMuted ? 'micUnmute' : 'micMute'),
              color: v.micMuted ? red : null,
              onPressed: v.toggleMic,
              icon: Icon(v.micMuted ? Icons.mic_off_rounded : Icons.mic_rounded),
            ),
            IconButton.outlined(
              tooltip: context.tr(v.spkMuted ? 'spkUnmute' : 'spkMute'),
              color: v.spkMuted ? red : null,
              onPressed: v.toggleSpeaker,
              icon: Icon(v.spkMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded),
            ),
          ]),
      ]),
    );
  }
}
