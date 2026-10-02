// State-machine tests for the permission → timeout → fallback → late-fix
// flow (guide v2.1 §5.1–§5.4, DoD §22). Time is driven by fake_async; no test
// waits in real time.
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/core/errors/app_failure.dart';
import 'package:sg_smart_commute/core/geo/geo.dart';
import 'package:sg_smart_commute/core/location/location_service.dart';
import 'package:sg_smart_commute/features/origin/domain/origin.dart';
import 'package:sg_smart_commute/features/origin/domain/origin_controller.dart';

import '../../../integration_test/fakes/fake_location_service.dart';

const bishan = LatLng(1.3508, 103.8485);
const mountainView = LatLng(37.4220, -122.0841);
const tampines = LatLng(1.3530, 103.9450);
const jurong = LatLng(1.3329, 103.7436);

void main() {
  late FakeLocationService location;

  // Called inside fakeAsync: the fake's completers must belong to the fake
  // zone, or their callbacks would run on the real microtask queue.
  ProviderContainer makeContainer() {
    location = FakeLocationService();
    final c = ProviderContainer(
      overrides: [
        locationServiceProvider.overrideWithValue(location),
        locationTimeoutProvider.overrideWithValue(const Duration(seconds: 10)),
        locationPermissionTimeoutProvider.overrideWithValue(
          const Duration(seconds: 10),
        ),
      ],
    );
    c.listen(originControllerProvider, (_, _) {});
    return c;
  }

  test('starts by checking permission, without blocking on it', () {
    fakeAsync((async) {
      final c = makeContainer();
      async.flushMicrotasks();
      final s = c.read(originControllerProvider);
      expect(s.phase, OriginPhase.checkingPermission);
      expect(s.origin, isNull);
      expect(location.accessRequests, 1);
      c.dispose();
    });
  });

  for (final (access, failureType) in [
    (LocationAccess.denied, LocationPermissionDenied),
    (LocationAccess.deniedForever, LocationPermissionPermanentlyDenied),
    (LocationAccess.serviceDisabled, LocationServiceDisabled),
  ]) {
    test('$access → manual origin immediately, no position request', () {
      fakeAsync((async) {
        final c = makeContainer();
        location.answer(access);
        async.flushMicrotasks();
        final s = c.read(originControllerProvider);
        expect(s.phase, OriginPhase.needsManual);
        expect(s.fallbackReason.runtimeType, failureType);
        expect(location.positionRequests, 0);
        c.dispose();
      });
    });
  }

  test('granted + valid SG fix within the timeout → GPS origin', () {
    fakeAsync((async) {
      final c = makeContainer();
      location.grant();
      async.flushMicrotasks();
      expect(c.read(originControllerProvider).phase, OriginPhase.acquiring);

      async.elapse(const Duration(seconds: 3));
      location.fix(bishan);
      async.flushMicrotasks();

      final s = c.read(originControllerProvider);
      expect(s.phase, OriginPhase.ready);
      expect(s.origin!.provenance, OriginProvenance.gps);
      expect(s.origin!.position, bishan);
      expect(s.origin!.label, 'Current location');

      // The timeout no longer fires once resolved.
      async.elapse(const Duration(seconds: 20));
      expect(c.read(originControllerProvider).phase, OriginPhase.ready);
      c.dispose();
    });
  });

  test('the acquisition timeout starts only once permission is granted', () {
    fakeAsync((async) {
      final c = makeContainer();
      async.elapse(const Duration(seconds: 5)); // dialog open, answered at 5 s
      expect(
        c.read(originControllerProvider).phase,
        OriginPhase.checkingPermission,
      );

      location.grant();
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 9999));
      expect(c.read(originControllerProvider).phase, OriginPhase.acquiring);
      async.elapse(const Duration(milliseconds: 1));
      final s = c.read(originControllerProvider);
      expect(s.phase, OriginPhase.needsManual);
      expect(s.fallbackReason, isA<LocationTimeout>());
      c.dispose();
    });
  });

  // A browser location prompt left open never resolves (issue #9).
  group('unanswered permission prompt', () {
    void leaveUnanswered(FakeAsync async) {
      async.elapse(const Duration(milliseconds: 9999));
      async.flushMicrotasks();
    }

    test('falls back to manual entry after the permission timeout', () {
      fakeAsync((async) {
        final c = makeContainer();
        leaveUnanswered(async);
        expect(
          c.read(originControllerProvider).phase,
          OriginPhase.checkingPermission,
        );
        async.elapse(const Duration(milliseconds: 1));
        final s = c.read(originControllerProvider);
        expect(s.phase, OriginPhase.needsManual);
        expect(s.fallbackReason, isA<LocationPermissionUnanswered>());
        expect(location.positionRequests, 0);
        c.dispose();
      });
    });

    test('granted later, nothing typed → acquires and sets the GPS origin', () {
      fakeAsync((async) {
        final c = makeContainer();
        async.elapse(const Duration(seconds: 30));
        location.grant();
        async.flushMicrotasks();
        expect(c.read(originControllerProvider).phase, OriginPhase.acquiring);
        location.fix(bishan);
        async.flushMicrotasks();
        final s = c.read(originControllerProvider);
        expect(s.phase, OriginPhase.ready);
        expect(s.origin!.provenance, OriginProvenance.gps);
        c.dispose();
      });
    });

    test('granted later while typing → the fix is only offered', () {
      fakeAsync((async) {
        final c = makeContainer();
        async.elapse(const Duration(seconds: 30));
        c.read(originControllerProvider.notifier).beginManualEntry();
        location.grant();
        async.flushMicrotasks();
        expect(c.read(originControllerProvider).phase, OriginPhase.needsManual);
        location.fix(bishan);
        async.flushMicrotasks();
        final s = c.read(originControllerProvider);
        expect(s.origin, isNull);
        expect(s.offeredGpsFix, bishan);
        c.dispose();
      });
    });

    // M5, seen live in Chrome: after a late "Allow" the prompt still said the
    // request had not been answered.
    test('granted later while typing → the "not answered" note is cleared', () {
      fakeAsync((async) {
        final c = makeContainer();
        async.elapse(const Duration(seconds: 30));
        c.read(originControllerProvider.notifier).beginManualEntry();
        expect(
          c.read(originControllerProvider).fallbackReason,
          isA<LocationPermissionUnanswered>(),
        );
        location.grant();
        async.flushMicrotasks();
        final s = c.read(originControllerProvider);
        expect(s.phase, OriginPhase.needsManual);
        expect(s.manualEntryInProgress, isTrue);
        expect(s.fallbackReason, isNull);
        c.dispose();
      });
    });

    test('denied later → the reason becomes "denied"', () {
      fakeAsync((async) {
        final c = makeContainer();
        async.elapse(const Duration(seconds: 30));
        location.answer(LocationAccess.denied);
        async.flushMicrotasks();
        expect(
          c.read(originControllerProvider).fallbackReason,
          isA<LocationPermissionDenied>(),
        );
        c.dispose();
      });
    });

    test(
      'a manual origin chosen meanwhile is kept; a later fix is offered',
      () {
        fakeAsync((async) {
          final c = makeContainer();
          async.elapse(const Duration(seconds: 30));
          c
              .read(originControllerProvider.notifier)
              .selectManualOrigin('Tampines', tampines);
          location.grant();
          async.flushMicrotasks();
          location.fix(bishan);
          async.flushMicrotasks();
          final s = c.read(originControllerProvider);
          expect(s.origin!.provenance, OriginProvenance.manual);
          expect(s.offeredGpsFix, bishan);
          c.dispose();
        });
      },
    );
  });

  test('out-of-Singapore fix (emulator default) → manual origin', () {
    fakeAsync((async) {
      final c = makeContainer();
      location.grant();
      async.flushMicrotasks();
      location.fix(mountainView);
      async.flushMicrotasks();
      final s = c.read(originControllerProvider);
      expect(s.phase, OriginPhase.needsManual);
      expect(s.fallbackReason, isA<LocationOutsideSingapore>());
      expect(s.origin, isNull);
      c.dispose();
    });
  });

  test('non-finite fix → manual origin', () {
    fakeAsync((async) {
      final c = makeContainer();
      location.grant();
      async.flushMicrotasks();
      location.fix(const LatLng(double.nan, double.nan));
      async.flushMicrotasks();
      expect(
        c.read(originControllerProvider).fallbackReason,
        isA<LocationOutsideSingapore>(),
      );
      c.dispose();
    });
  });

  test(
    'position error before the timeout → manual origin with that reason',
    () {
      fakeAsync((async) {
        final c = makeContainer();
        location.grant();
        async.flushMicrotasks();
        location.fail(const LocationServiceDisabled());
        async.flushMicrotasks();
        final s = c.read(originControllerProvider);
        expect(s.phase, OriginPhase.needsManual);
        expect(s.fallbackReason, isA<LocationServiceDisabled>());
        c.dispose();
      });
    },
  );

  test('unexpected position error is wrapped as LocationUnavailable', () {
    fakeAsync((async) {
      final c = makeContainer();
      location.grant();
      async.flushMicrotasks();
      location.fail(StateError('boom'));
      async.flushMicrotasks();
      expect(
        c.read(originControllerProvider).fallbackReason,
        isA<LocationUnavailable>(),
      );
      c.dispose();
    });
  });

  group('late fix (§5.4)', () {
    void timeOut(FakeAsync async, ProviderContainer c) {
      location.grant();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 10));
      expect(c.read(originControllerProvider).phase, OriginPhase.needsManual);
    }

    test('never overwrites a manually selected origin; offered instead', () {
      fakeAsync((async) {
        final c = makeContainer();
        timeOut(async, c);
        final ctl = c.read(originControllerProvider.notifier);
        ctl.selectManualOrigin('Tampines', tampines);
        expect(
          c.read(originControllerProvider).origin!.provenance,
          OriginProvenance.manual,
        );

        location.fix(bishan);
        async.flushMicrotasks();

        final s = c.read(originControllerProvider);
        expect(s.phase, OriginPhase.ready);
        expect(s.origin!.provenance, OriginProvenance.manual);
        expect(s.origin!.position, tampines);
        expect(s.origin!.label, 'Tampines');
        expect(s.offeredGpsFix, bishan);
        c.dispose();
      });
    });

    test('never overwrites while the user is mid-entry; offered instead', () {
      fakeAsync((async) {
        final c = makeContainer();
        timeOut(async, c);
        c.read(originControllerProvider.notifier).beginManualEntry();
        location.fix(bishan);
        async.flushMicrotasks();
        final s = c.read(originControllerProvider);
        expect(s.phase, OriginPhase.needsManual);
        expect(s.origin, isNull);
        expect(s.offeredGpsFix, bishan);
        c.dispose();
      });
    });

    test('populates the origin if the user has not chosen anything', () {
      fakeAsync((async) {
        final c = makeContainer();
        timeOut(async, c);
        location.fix(bishan);
        async.flushMicrotasks();
        final s = c.read(originControllerProvider);
        expect(s.phase, OriginPhase.ready);
        expect(s.origin!.provenance, OriginProvenance.gps);
        expect(s.fallbackReason, isNull);
        c.dispose();
      });
    });

    test('an out-of-Singapore late fix is ignored entirely', () {
      fakeAsync((async) {
        final c = makeContainer();
        timeOut(async, c);
        location.fix(mountainView);
        async.flushMicrotasks();
        final s = c.read(originControllerProvider);
        expect(s.phase, OriginPhase.needsManual);
        expect(s.fallbackReason, isA<LocationTimeout>());
        expect(s.offeredGpsFix, isNull);
        c.dispose();
      });
    });

    test('a late error is ignored', () {
      fakeAsync((async) {
        final c = makeContainer();
        timeOut(async, c);
        location.fail(const LocationServiceDisabled());
        async.flushMicrotasks();
        expect(
          c.read(originControllerProvider).fallbackReason,
          isA<LocationTimeout>(),
        );
        c.dispose();
      });
    });

    test(
      '"Use my current location" switches to the offered fix explicitly',
      () {
        fakeAsync((async) {
          final c = makeContainer();
          timeOut(async, c);
          final ctl = c.read(originControllerProvider.notifier);
          ctl.selectManualOrigin('Tampines', tampines);
          location.fix(bishan);
          async.flushMicrotasks();

          ctl.useCurrentLocation();
          final s = c.read(originControllerProvider);
          expect(s.origin!.provenance, OriginProvenance.gps);
          expect(s.origin!.position, bishan);
          expect(s.offeredGpsFix, isNull);
          c.dispose();
        });
      },
    );
  });

  test('a manual origin outside Singapore is rejected', () {
    fakeAsync((async) {
      final c = makeContainer();
      location.answer(LocationAccess.denied);
      async.flushMicrotasks();
      final ctl = c.read(originControllerProvider.notifier);
      expect(
        () => ctl.selectManualOrigin('Nowhere', mountainView),
        throwsArgumentError,
      );
      expect(c.read(originControllerProvider).origin, isNull);
      c.dispose();
    });
  });

  test('changeOrigin reopens manual entry and keeps the current origin', () {
    fakeAsync((async) {
      final c = makeContainer();
      location.grant();
      async.flushMicrotasks();
      location.fix(bishan);
      async.flushMicrotasks();
      c.read(originControllerProvider.notifier).changeOrigin();
      final s = c.read(originControllerProvider);
      expect(s.phase, OriginPhase.needsManual);
      expect(s.manualEntryInProgress, isTrue);
      expect(s.origin!.position, bishan);
      expect(s.fallbackReason, isNull);
      c.dispose();
    });
  });

  group('cancelChange ("Keep this origin")', () {
    test('returns to the same GPS origin after Change', () {
      fakeAsync((async) {
        final c = makeContainer();
        location.grant();
        async.flushMicrotasks();
        location.fix(bishan);
        async.flushMicrotasks();
        final ctl = c.read(originControllerProvider.notifier);
        final before = c.read(originControllerProvider).origin;
        ctl
          ..changeOrigin()
          ..cancelChange();
        final s = c.read(originControllerProvider);
        expect(s.phase, OriginPhase.ready);
        expect(s.origin, same(before));
        expect(s.manualEntryInProgress, isFalse);
        c.dispose();
      });
    });

    test('does nothing on the fallback prompt (no origin to keep)', () {
      fakeAsync((async) {
        final c = makeContainer();
        location.answer(LocationAccess.denied);
        async.flushMicrotasks();
        c.read(originControllerProvider.notifier).cancelChange();
        final s = c.read(originControllerProvider);
        expect(s.phase, OriginPhase.needsManual);
        expect(s.fallbackReason, isA<LocationPermissionDenied>());
        c.dispose();
      });
    });
  });

  // "Try location again" behind a manual origin (issue #13).
  group('background retry with a manual origin', () {
    ProviderContainer manualAfterDenial(FakeAsync async) {
      final c = makeContainer();
      location.answer(LocationAccess.denied);
      async.flushMicrotasks();
      c
          .read(originControllerProvider.notifier)
          .selectManualOrigin('Tampines', tampines);
      location.reset();
      c.read(originControllerProvider.notifier).retryLocation();
      async.flushMicrotasks();
      return c;
    }

    void expectTampinesKept(OriginState s) {
      expect(s.phase, OriginPhase.ready);
      expect(s.origin!.provenance, OriginProvenance.manual);
      expect(s.origin!.position, tampines);
    }

    test('reports progress, then offers the fix', () {
      fakeAsync((async) {
        final c = manualAfterDenial(async);
        expect(c.read(originControllerProvider).locatingInBackground, isTrue);
        location.grant();
        async.flushMicrotasks();
        location.fix(bishan);
        async.flushMicrotasks();
        final s = c.read(originControllerProvider);
        expectTampinesKept(s);
        expect(s.locatingInBackground, isFalse);
        expect(s.backgroundFailure, isNull);
        expect(s.offeredGpsFix, bishan);
        c.dispose();
      });
    });

    test('a denial is reported and keeps the origin', () {
      fakeAsync((async) {
        final c = manualAfterDenial(async);
        location.answer(LocationAccess.denied);
        async.flushMicrotasks();
        final s = c.read(originControllerProvider);
        expectTampinesKept(s);
        expect(s.locatingInBackground, isFalse);
        expect(s.backgroundFailure, isA<LocationPermissionDenied>());
        c.dispose();
      });
    });

    test('a timeout is reported; a fix after it is still offered', () {
      fakeAsync((async) {
        final c = manualAfterDenial(async);
        location.grant();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 10));
        var s = c.read(originControllerProvider);
        expectTampinesKept(s);
        expect(s.backgroundFailure, isA<LocationTimeout>());

        location.fix(bishan);
        async.flushMicrotasks();
        s = c.read(originControllerProvider);
        expectTampinesKept(s);
        expect(s.offeredGpsFix, bishan);
        expect(s.backgroundFailure, isNull);
        c.dispose();
      });
    });

    test('an unanswered prompt is reported too', () {
      fakeAsync((async) {
        final c = manualAfterDenial(async);
        async.elapse(const Duration(seconds: 10));
        final s = c.read(originControllerProvider);
        expectTampinesKept(s);
        expect(s.backgroundFailure, isA<LocationPermissionUnanswered>());
        c.dispose();
      });
    });

    test('a prompt answered after the timeout resumes and reports its own '
        'outcome', () {
      fakeAsync((async) {
        final c = manualAfterDenial(async);
        async.elapse(const Duration(seconds: 10));
        expect(
          c.read(originControllerProvider).backgroundFailure,
          isA<LocationPermissionUnanswered>(),
        );
        location.grant();
        async.flushMicrotasks();
        var s = c.read(originControllerProvider);
        expect(s.locatingInBackground, isTrue);
        expect(s.backgroundFailure, isNull);

        async.elapse(const Duration(seconds: 10)); // no fix
        s = c.read(originControllerProvider);
        expectTampinesKept(s);
        expect(s.locatingInBackground, isFalse);
        expect(s.backgroundFailure, isA<LocationTimeout>());
        c.dispose();
      });
    });

    // Regression: a non-granted answer after the permission timeout used to
    // be dropped, leaving the "not answered yet" note in place.
    for (final (access, failureType) in [
      (LocationAccess.denied, LocationPermissionDenied),
      (LocationAccess.deniedForever, LocationPermissionPermanentlyDenied),
      (LocationAccess.serviceDisabled, LocationServiceDisabled),
    ]) {
      test('permission timeout, then a late $access: the note changes from '
          'unanswered to $failureType; the manual origin is kept', () {
        fakeAsync((async) {
          final c = manualAfterDenial(async);
          final origin = c.read(originControllerProvider).origin;
          async.elapse(const Duration(seconds: 10));
          expect(
            c.read(originControllerProvider).backgroundFailure,
            isA<LocationPermissionUnanswered>(),
          );

          location.answer(access);
          async.flushMicrotasks();
          final s = c.read(originControllerProvider);
          expectTampinesKept(s);
          expect(s.origin, same(origin));
          expect(s.backgroundFailure.runtimeType, failureType);
          expect(s.locatingInBackground, isFalse);
          expect(s.offeredGpsFix, isNull);
          expect(location.positionRequests, 0);
          c.dispose();
        });
      });
    }

    test('permission timeout, then the permission request throws: reported '
        'as unavailable; the manual origin is kept', () {
      fakeAsync((async) {
        final c = manualAfterDenial(async);
        async.elapse(const Duration(seconds: 10));
        location.failAccess(StateError('prompt dismissed'));
        async.flushMicrotasks();
        final s = c.read(originControllerProvider);
        expectTampinesKept(s);
        expect(s.backgroundFailure, isA<LocationUnavailable>());
        expect(s.locatingInBackground, isFalse);
        c.dispose();
      });
    });

    test('a superseded attempt answering late changes nothing', () {
      fakeAsync((async) {
        final c = manualAfterDenial(async); // attempt B
        async.elapse(const Duration(seconds: 10));
        final staleAccess = location.pendingAccess;
        location.reset();
        c.read(originControllerProvider.notifier).retryLocation(); // C
        async.flushMicrotasks();

        staleAccess.complete(LocationAccess.denied); // B answers late
        async.flushMicrotasks();
        final s = c.read(originControllerProvider);
        expectTampinesKept(s);
        expect(s.locatingInBackground, isTrue, reason: 'C is still running');
        expect(s.backgroundFailure, isNull);
        c.dispose();
      });
    });

    test('an out-of-Singapore fix is reported, never offered', () {
      fakeAsync((async) {
        final c = manualAfterDenial(async);
        location.grant();
        async.flushMicrotasks();
        location.fix(mountainView);
        async.flushMicrotasks();
        final s = c.read(originControllerProvider);
        expectTampinesKept(s);
        expect(s.offeredGpsFix, isNull);
        expect(s.backgroundFailure, isA<LocationOutsideSingapore>());
        c.dispose();
      });
    });
  });

  test('retryLocation runs the flow again and ignores the stale attempt', () {
    fakeAsync((async) {
      final c = makeContainer();
      location.answer(LocationAccess.serviceDisabled);
      async.flushMicrotasks();
      final ctl = c.read(originControllerProvider.notifier);
      ctl.openSettings();
      async.flushMicrotasks();
      expect(location.settingsOpened, [LocationAccess.serviceDisabled]);

      location.reset();
      ctl.retryLocation();
      async.flushMicrotasks();
      expect(
        c.read(originControllerProvider).phase,
        OriginPhase.checkingPermission,
      );
      location.grant();
      async.flushMicrotasks();
      location.fix(bishan);
      async.flushMicrotasks();
      expect(
        c.read(originControllerProvider).origin!.provenance,
        OriginProvenance.gps,
      );
      expect(location.accessRequests, 2);
      c.dispose();
    });
  });

  // Two overlapping attempts: A (launch) and B ("Try location again"). The
  // fake keeps A's position completer after reset(), so A can answer late.
  group('overlapping attempts (A then B)', () {
    OriginState read(ProviderContainer c) => c.read(originControllerProvider);
    OriginController ctl(ProviderContainer c) =>
        c.read(originControllerProvider.notifier);

    void timeOutA(FakeAsync async, ProviderContainer c) {
      location.grant();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 10));
      expect(read(c).fallbackReason, isA<LocationTimeout>());
    }

    void startB(FakeAsync async, ProviderContainer c) {
      location.reset();
      ctl(c).retryLocation();
      location.grant();
      async.flushMicrotasks();
    }

    void expectManualTampines(OriginState s) {
      expect(s.phase, OriginPhase.ready);
      expect(s.origin!.provenance, OriginProvenance.manual);
      expect(s.origin!.position, tampines);
      expect(s.fallbackReason, isNull);
    }

    test('(a) A times out → manual → B fix is only offered → chip → GPS', () {
      fakeAsync((async) {
        final c = makeContainer();
        timeOutA(async, c);
        ctl(c).selectManualOrigin('Tampines', tampines);
        startB(async, c);
        expect(location.positionRequests, 2);
        // B runs in the background: the manual origin stays in effect.
        expectManualTampines(read(c));

        location.fixAttempt(1, bishan);
        async.flushMicrotasks();
        expectManualTampines(read(c));
        expect(read(c).offeredGpsFix, bishan);

        // B's timer is a no-op once B has answered.
        async.elapse(const Duration(seconds: 20));
        expectManualTampines(read(c));

        ctl(c).useCurrentLocation();
        final s = read(c);
        expect(s.origin!.provenance, OriginProvenance.gps);
        expect(s.origin!.position, bishan);
        expect(s.offeredGpsFix, isNull);
        c.dispose();
      });
    });

    test(
      '(b) manual before A times out → B → A late, then B: stays manual',
      () {
        fakeAsync((async) {
          final c = makeContainer();
          location.grant();
          async.flushMicrotasks();
          async.elapse(const Duration(seconds: 3));
          ctl(c).selectManualOrigin('Tampines', tampines);
          expectManualTampines(read(c));

          startB(async, c);
          expectManualTampines(read(c));

          // A is superseded: its late fix is dropped, not offered.
          location.fixAttempt(0, jurong);
          async.flushMicrotasks();
          expectManualTampines(read(c));
          expect(read(c).offeredGpsFix, isNull);

          // A's and B's deadlines pass without disturbing the manual origin.
          async.elapse(const Duration(seconds: 15));
          expectManualTampines(read(c));

          location.fixAttempt(1, bishan);
          async.flushMicrotasks();
          expectManualTampines(read(c));
          expect(read(c).offeredGpsFix, bishan);
          c.dispose();
        });
      },
    );

    test("(c) A's late fix after B started is dropped; B's fix governs", () {
      fakeAsync((async) {
        final c = makeContainer();
        timeOutA(async, c); // t = 10 s, nothing chosen
        startB(async, c);
        expect(read(c).phase, OriginPhase.acquiring);

        async.elapse(const Duration(seconds: 2));
        location.fixAttempt(0, jurong);
        async.flushMicrotasks();
        var s = read(c);
        expect(s.phase, OriginPhase.acquiring, reason: 'not B completing');
        expect(s.origin, isNull);
        expect(s.offeredGpsFix, isNull);

        async.elapse(const Duration(seconds: 2));
        location.fixAttempt(1, bishan);
        async.flushMicrotasks();
        s = read(c);
        expect(s.phase, OriginPhase.ready);
        expect(s.origin!.provenance, OriginProvenance.gps);
        expect(s.origin!.position, bishan);
        c.dispose();
      });
    });

    test("(c) A's late fix after B started does not stop B's timeout", () {
      fakeAsync((async) {
        final c = makeContainer();
        timeOutA(async, c);
        startB(async, c); // B's deadline: 10 s from now
        location.fixAttempt(0, jurong);
        async.flushMicrotasks();

        async.elapse(const Duration(milliseconds: 9999));
        expect(read(c).phase, OriginPhase.acquiring);
        async.elapse(const Duration(milliseconds: 1));
        final s = read(c);
        expect(s.phase, OriginPhase.needsManual);
        expect(s.fallbackReason, isA<LocationTimeout>());
        expect(s.origin, isNull);
        c.dispose();
      });
    });

    test("(d) A's late error and old deadline do not change B's state", () {
      fakeAsync((async) {
        final c = makeContainer();
        location.grant();
        async.flushMicrotasks(); // A acquiring, deadline t = 10 s
        async.elapse(const Duration(seconds: 5));
        startB(async, c); // B acquiring, deadline t = 15 s

        location.failAttempt(0, const LocationServiceDisabled());
        async.flushMicrotasks();
        expect(read(c).phase, OriginPhase.acquiring);
        expect(read(c).fallbackReason, isNull);

        async.elapse(const Duration(seconds: 5)); // A's deadline passes
        expect(read(c).phase, OriginPhase.acquiring);

        async.elapse(const Duration(seconds: 5)); // B's deadline
        expect(read(c).fallbackReason, isA<LocationTimeout>());
        c.dispose();
      });
    });

    test("(d) A's late error after A timed out leaves B acquiring", () {
      fakeAsync((async) {
        final c = makeContainer();
        timeOutA(async, c);
        startB(async, c);
        location.failAttempt(0, StateError('late'));
        async.flushMicrotasks();
        expect(read(c).phase, OriginPhase.acquiring);
        expect(read(c).fallbackReason, isNull);
        c.dispose();
      });
    });

    test('B outside Singapore, failing or denied never disturbs manual', () {
      fakeAsync((async) {
        final c = makeContainer();
        timeOutA(async, c);
        ctl(c).selectManualOrigin('Tampines', tampines);

        startB(async, c);
        location.fixAttempt(1, mountainView);
        async.flushMicrotasks();
        expectManualTampines(read(c));
        expect(read(c).offeredGpsFix, isNull);

        startB(async, c); // attempt C
        location.failAttempt(2, const LocationUnavailable());
        async.flushMicrotasks();
        expectManualTampines(read(c));

        location.reset();
        ctl(c).retryLocation();
        location.answer(LocationAccess.denied);
        async.flushMicrotasks();
        expectManualTampines(read(c));
        c.dispose();
      });
    });

    test('manual chosen while B checks permission: B fix is only offered', () {
      fakeAsync((async) {
        final c = makeContainer();
        timeOutA(async, c);
        location.reset();
        ctl(c).retryLocation();
        async.flushMicrotasks();
        expect(read(c).phase, OriginPhase.checkingPermission);
        ctl(c).selectManualOrigin('Tampines', tampines);

        location.grant();
        async.flushMicrotasks();
        expectManualTampines(read(c)); // not flipped to acquiring
        async.elapse(const Duration(seconds: 10));
        expectManualTampines(read(c)); // B's timeout is a no-op

        location.fixAttempt(1, bishan);
        async.flushMicrotasks();
        expectManualTampines(read(c));
        expect(read(c).offeredGpsFix, bishan);
        c.dispose();
      });
    });
  });
}
