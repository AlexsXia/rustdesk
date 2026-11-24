import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/peer_model.dart';

import '../theme.dart';
import '../uu_peer.dart';
import 'uu_platform_icon.dart';

class UuDeviceCard extends StatelessWidget {
  const UuDeviceCard({
    super.key,
    required this.peer,
    required this.onConnect,
  });

  final Peer peer;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: UuTheme.surface,
        borderRadius: BorderRadius.circular(UuTheme.cardRadius),
        boxShadow: UuTheme.cardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(UuTheme.cardRadius),
          onTap: onConnect,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    UuPlatformIcon(peer.platform),
                    const Spacer(),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color:
                            peer.online ? UuTheme.online : UuTheme.offline,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  uuPeerName(peer),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: UuTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  uuPeerSubtitle(peer),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: UuTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: onConnect,
                    style: FilledButton.styleFrom(
                      backgroundColor: UuTheme.accent,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(translate('Connect')),
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
