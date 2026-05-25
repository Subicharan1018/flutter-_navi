import os
import re

with open('lib/screens/replay_screen.dart', 'r') as f:
    lines = f.readlines()

split_idx = 0
for i, line in enumerate(lines):
    if '// =============================================================================' in line and '// Header — clean' in lines[i+1]:
        split_idx = i
        break

main_screen = lines[:split_idx]
widgets = lines[split_idx:]

renames = [
    ('_ReplayHeader', 'ReplayHeader'),
    ('_ReplayTabContent', 'ReplayTabContent'),
    ('_ReplayList', 'ReplayList'),
    ('_DailyListeningChart', 'DailyListeningChart'),
    ('_DashedLine', 'DashedLine'),
    ('_StatsCard', 'StatsCard'),
    ('_InlineStatRow', 'InlineStatRow'),
    ('_ReplaySongRow', 'ReplaySongRow'),
    ('_EmptyReplay', 'EmptyReplay'),
]

main_screen_str = ''.join(main_screen)
for old, new in renames:
    main_screen_str = main_screen_str.replace(old, new)

widgets_str = ''.join(widgets)
for old, new in renames:
    widgets_str = widgets_str.replace(old, new)

widgets_import = """import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../providers/replay_provider.dart';
import '../../../providers/player_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../core/theme.dart';
import '../../../services/subsonic_service.dart';

"""
widgets_str = widgets_import + widgets_str

main_screen_str = main_screen_str.replace(
    "import '../widgets/mini_player.dart';", 
    "import '../widgets/mini_player.dart';\nimport 'replay/widgets/replay_widgets.dart';"
)

os.makedirs('lib/screens/replay/widgets', exist_ok=True)
with open('lib/screens/replay/widgets/replay_widgets.dart', 'w') as f:
    f.write(widgets_str)

with open('lib/screens/replay_screen.dart', 'w') as f:
    f.write(main_screen_str)
