import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../widgets/ui/media.dart';
import '../logic/social_providers.dart';
import 'blend_screens.dart';
import 'collab_screens.dart';

/// Shared-playlist invites and Blend requests, on top of the Sessions page
/// where they can't be missed. Nothing renders when there are none.
class InvitationsSection extends ConsumerWidget {
  const InvitationsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collabs = [
      for (final p in ref.watch(collabListProvider).asData?.value ?? const []) if (p.invited) p,
    ];
    final blends = [
      for (final b in ref.watch(blendListProvider).asData?.value ?? const []) if (b.pending && b.incoming) b,
    ];
    if (collabs.isEmpty && blends.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionHeader(title: 'Invitations'),
      for (final p in collabs) CollabRow(playlist: p),
      for (final b in blends) BlendRow(blend: b),
    ]);
  }
}
