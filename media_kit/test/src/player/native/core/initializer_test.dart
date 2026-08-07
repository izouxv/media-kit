/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.

import 'dart:io';
import 'dart:ffi';
import 'dart:async';
import 'dart:isolate';
import 'package:path/path.dart';
import 'package:test/test.dart';

import 'package:media_kit/ffi/ffi.dart';

import 'package:media_kit/src/player/native/core/initializer.dart';
import 'package:media_kit/src/player/native/core/native_library.dart';

import 'package:media_kit/generated/libmpv/bindings.dart';

MPV? _mpv;
MPV get mpv => _mpv!;

Future<void> _createHandleAndExit(List<Object> arguments) async {
  final sendPort = arguments[0] as SendPort;
  final libmpv = arguments[1] as String;
  final childMpv = MPV(DynamicLibrary.open(libmpv));
  final handle = await Initializer(childMpv).create((_) async {});
  Isolate.exit(sendPort, handle.address);
}

void main() {
  setUp(() {
    NativeLibrary.ensureInitialized();
    _mpv = MPV(DynamicLibrary.open(NativeLibrary.path));
  });
  test(
    'initializer-init',
    () {
      expect(
        Initializer(mpv).create((_) async {}),
        completes,
      );
    },
  );
  test(
    'initializer-create',
    () {
      expect(
        Initializer(mpv).create((_) async {}),
        completes,
      );
    },
  );
  test(
    'initializer-dispose',
    () async {
      final handle = await Initializer(mpv).create((_) async {});
      expect(
        () => Initializer(mpv).dispose(handle),
        returnsNormally,
      );
    },
  );
  test(
    'initializer-dispose-detaches-wakeup-callback-before-shutdown',
    () async {
      final handle = await Initializer(mpv).create((_) async {});
      final command = 'quit'.toNativeUtf8();

      Initializer(mpv).dispose(handle);

      try {
        expect(
          mpv.mpv_command_string(handle, command.cast()),
          0,
        );

        var shutdownReceived = false;
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (!shutdownReceived && DateTime.now().isBefore(deadline)) {
          final event = mpv.mpv_wait_event(handle, 0.1);
          shutdownReceived =
              event.ref.event_id == mpv_event_id.MPV_EVENT_SHUTDOWN;
        }
        expect(shutdownReceived, isTrue);
      } finally {
        calloc.free(command);
        mpv.mpv_destroy(handle);
      }
    },
    timeout: const Timeout(Duration(seconds: 10)),
  );
  test(
    'initializer-recovers-handle-from-terminated-isolate',
    () async {
      final receiver = ReceivePort();
      await Isolate.spawn(
        _createHandleAndExit,
        <Object>[receiver.sendPort, NativeLibrary.path],
      );
      final address = await receiver.first as int;
      receiver.close();

      final handle = Pointer<mpv_handle>.fromAddress(address);
      final command = 'quit'.toNativeUtf8();

      // A new isolate has no Dart-side bookkeeping for the old handle. It
      // must still detach the stale native callback before shutdown.
      Initializer(mpv).dispose(handle);

      try {
        expect(
          mpv.mpv_command_string(handle, command.cast()),
          0,
        );

        var shutdownReceived = false;
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (!shutdownReceived && DateTime.now().isBefore(deadline)) {
          final event = mpv.mpv_wait_event(handle, 0.1);
          shutdownReceived =
              event.ref.event_id == mpv_event_id.MPV_EVENT_SHUTDOWN;
        }
        expect(shutdownReceived, isTrue);
      } finally {
        calloc.free(command);
        mpv.mpv_destroy(handle);
      }
    },
    timeout: const Timeout(Duration(seconds: 10)),
  );
  test(
    'initializer-callback',
    () async {
      final shutdown = Completer();

      final expectPauseTrue = expectAsync1((value) {
        print(value);
        expect(value, isTrue);
        shutdown.complete();
      });
      final expectShutdown = expectAsync0(() {
        print('shutdown');
        expect(true, isTrue);
      });

      final handle = await Initializer(mpv).create(
        (event) async {
          if (event.ref.event_id == mpv_event_id.MPV_EVENT_PROPERTY_CHANGE) {
            final prop = event.ref.data.cast<mpv_event_property>();
            if (prop.ref.name.cast<Utf8>().toDartString() == 'pause' &&
                prop.ref.format == mpv_format.MPV_FORMAT_FLAG) {
              final value = prop.ref.data.cast<Bool>().value;
              expectPauseTrue(value);
            }
          }
          if (event.ref.event_id == mpv_event_id.MPV_EVENT_SHUTDOWN) {
            expectShutdown();
          }
        },
      );
      await Future.delayed(Duration(seconds: 5));
      {
        final name = 'pause'.toNativeUtf8();
        mpv.mpv_observe_property(
          handle,
          0,
          name.cast(),
          mpv_format.MPV_FORMAT_FLAG,
        );
        calloc.free(name);
      }
      {
        final command = 'cycle pause'.toNativeUtf8();
        mpv.mpv_command_string(
          handle,
          command.cast(),
        );
        calloc.free(command);
      }
      await shutdown.future;
      {
        final command = 'quit 0'.toNativeUtf8();
        mpv.mpv_command_string(
          handle,
          command.cast(),
        );
        calloc.free(command);
      }

      await Future.delayed(const Duration(seconds: 5));

      Initializer(mpv).dispose(handle);
    },
  );
  test(
    'initializer-options-with-callback',
    () async {
      final handle = await Initializer(mpv).create(
        (_) async {},
        options: {
          'config': 'yes',
          'config-dir': dirname(Platform.script.toFilePath()),
        },
      );
      {
        final name = 'config'.toNativeUtf8();
        final value = mpv.mpv_get_property_string(
          handle,
          name.cast(),
        );
        calloc.free(name);
        expect(
          value.cast<Utf8>().toDartString(),
          'yes',
        );
      }
      {
        final name = 'config-dir'.toNativeUtf8();
        final value = mpv.mpv_get_property_string(
          handle,
          name.cast(),
        );
        calloc.free(name);
        expect(
          value.cast<Utf8>().toDartString(),
          dirname(Platform.script.toFilePath()),
        );
      }

      await Future.delayed(const Duration(seconds: 5));

      Initializer(mpv).dispose(handle);
    },
  );
}
