import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/media_kit_video_controls/media_kit_video_controls.dart';

void main() {
  group('controls visibility notifier', () {
    test('mobile theme copyWith preserves and replaces notifier', () {
      final original = ValueNotifier<bool>(false);
      final replacement = ValueNotifier<bool>(true);
      final theme = MaterialVideoControlsThemeData(visible: original);

      expect(theme.visible, same(original));
      expect(theme.copyWith().visible, same(original));
      expect(theme.copyWith(visible: replacement).visible, same(replacement));
    });

    test('desktop theme copyWith preserves and replaces notifier', () {
      final original = ValueNotifier<bool>(false);
      final replacement = ValueNotifier<bool>(true);
      final theme = MaterialDesktopVideoControlsThemeData(visible: original);

      expect(theme.visible, same(original));
      expect(theme.copyWith().visible, same(original));
      expect(theme.copyWith(visible: replacement).visible, same(replacement));
    });
  });
}
