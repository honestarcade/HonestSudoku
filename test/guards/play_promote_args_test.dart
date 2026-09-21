@Tags(['guard'])
library;

// Guard for #21: the promote script refuses what it must, without a credential.
//
// The refusals are checked before the token is, deliberately, so that every
// one of them can be proven here — on a laptop, in CI, on a fork — with no
// Play access at all. A refusal that can only be tested by someone holding the
// production credential is a refusal nobody tests.
//
// The one that matters most is `production`. The service account's Console
// permission set is the real barrier and it is granted by a human who can
// change it; this script is the barrier that lives in the repository, where a
// change to it shows up in a diff.
//
// What this does NOT cover: anything past the argument checks. A fake token
// proves the script reaches the API and stops there; it proves nothing about
// the edits flow, which needs real credentials and is verified by dispatch.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'repo_files.dart';
import 'workflow_yaml.dart';

const _script = 'tools/play_promote.sh';
const _package = 'com.honestarcade.sudoku';

/// A loopback port nothing listens on, so the API layer is reached and
/// refused without leaving the machine.
///
/// The exit-5 test used to let the script hit the real Play API, so
/// `flutter test` — and therefore `tools/gate.sh`, and therefore every CI
/// run — made an unauthenticated request to Google on every invocation, in a
/// project whose first invariant is no network (#147). It also made the
/// assertion weaker than it read: offline it passed for a different reason.
/// Pointing it here keeps the discriminator (still 5, still distinct from an
/// argument refusal's 2) and means the same thing on every machine.
const _unreachableApi = 'http://127.0.0.1:1';

/// Answers a POST with an edit id and everything else with 500; a DELETE
/// exits 22, which is what `curl --fail` does on a 4xx or 5xx.
const _curlStub = r"""#!/bin/sh
out=""; method="GET"; want_status=0; prev=""
for a in "$@"; do
  case "$prev" in
    -o) out="$a" ;;
    -X) method="$a" ;;
  esac
  if [ "$a" = "-w" ]; then want_status=1; fi
  prev="$a"
done
case "$method" in
  POST)
    if [ -n "$out" ]; then printf '{"id":"E1"}' > "$out"; fi
    if [ "$want_status" = 1 ]; then printf '200'; fi
    exit 0 ;;
  DELETE)
    # A 500, and let curl's own --fail decide the exit status. The stub
    # exited 22 unconditionally, which is what --fail already does — so it
    # could not tell a script WITH --fail from one without, and removing
    # --fail left the whole suite green (#183).
    if [ -n "$out" ]; then printf '{"error":"boom"}' > "$out"; fi
    if [ "$want_status" = 1 ]; then printf '500'; fi
    case " $* " in *" --fail "*) exit 22 ;; esac
    exit 0 ;;
  *)
    if [ -n "$out" ]; then printf '{"error":"boom"}' > "$out"; fi
    if [ "$want_status" = 1 ]; then printf '500'; fi
    exit 0 ;;
esac
""";

({int code, String out, String err}) _run(List<String> args, {String? token}) {
  final r = Process.runSync(
    _script,
    args,
    workingDirectory: repoRoot.path,
    includeParentEnvironment: false,
    environment: {
      'PATH': Platform.environment['PATH'] ?? '/usr/bin:/bin',
      'PLAY_TOKEN': ?token,
      'HS_PLAY_API': _unreachableApi,
    },
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  return (code: r.exitCode, out: r.stdout.toString(), err: r.stderr.toString());
}

/// Runs a refusal step's `run:` body under bash with the dispatch inputs set,
/// and returns its exit code. The body is pure shell — no external command —
/// so this needs no stubs and no network.
int _runRefusal(String script, String fromTrack, String toTrack) {
  final dir = Directory.systemTemp.createTempSync('hs-refusal');
  try {
    final file = File('${dir.path}/refuse.sh')..writeAsStringSync(script);
    final r = Process.runSync(
      '/bin/bash',
      [file.path],
      includeParentEnvironment: false,
      environment: {
        'PATH': '/usr/bin:/bin',
        'FROM_TRACK': fromTrack,
        'TO_TRACK': toTrack,
      },
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    return r.exitCode;
  } finally {
    dir.deleteSync(recursive: true);
  }
}

void _assertPromoteShape(Workflow wf) {
  expect(wf.problem, isNull, reason: 'refusal: ${wf.problem}');
  expect(wf.jobs, isNotEmpty, reason: 'refusal: no jobs parsed');

  // The first barrier, asserted for the first time. #165 made both inputs
  // `type: choice` so `production` is not selectable in the UI, and nothing
  // checked it — reverting either to free text was green. #21's post-merge
  // criterion asked for a dispatch with `to_track: production` as evidence,
  // which `choice` makes unproducible from the UI; this is what replaces
  // that criterion, on the owner's call to keep `choice` (#179).
  for (final name in const ['from_track', 'to_track']) {
    final input = wf.dispatchInputs[name];
    expect(input, isNotNull, reason: 'refusal: no `$name` input');
    expect(
      input!.type,
      'choice',
      reason:
          'refusal: `$name` is `${input.type ?? 'free text'}` — free text '
          'let a crafted value forge a "-> production" line into the run '
          'summary and title a refused run as a promotion to production',
    );
    expect(input.options, [
      'internal',
      'alpha',
      'beta',
    ], reason: 'refusal: `$name` offers a track outside the testing tracks');
    expect(
      input.options,
      isNot(contains('production')),
      reason: 'refusal: production is selectable in the UI',
    );
  }

  for (final job in wf.jobs) {
    // A job with no steps used to `continue`, so a reusable-workflow job was
    // invisible to every check below — and `secrets: inherit` hands it the
    // service-account key. That is precisely what the failure message one
    // line down warns about, so skipping it was the hole (#171).
    expect(
      job.uses,
      isNull,
      reason:
          'refusal: job `${job.name}` calls the reusable workflow '
          '`${job.uses}`, whose steps are not in this file and cannot be '
          'checked. A job without a refusal can mint the credential and '
          'promote unchecked',
    );
    expect(
      job.steps,
      isNotEmpty,
      reason: 'refusal: job `${job.name}` has no steps',
    );
    expect(
      job.continueOnError,
      isFalse,
      reason:
          'refusal: job `${job.name}` carries `continue-on-error`, so its '
          'refusal failing would not stop what depends on it',
    );

    final refuse = job.steps.first;

    // Behaviour, not text. `refuse.run.contains('exit 1')` was satisfied by
    // any `exit 1` that never executes: inside a shell comment, inside an
    // uncalled function, inside `if false; then … fi`. All three were green
    // while the workflow promoted whatever the script allowed (#171). So the
    // step is RUN, with the dispatch inputs set, and judged by its exit code.
    expect(
      refuse.run,
      isNotNull,
      reason:
          'refusal: the first step of `${job.name}` is '
          '`${refuse.uses ?? refuse.id}`, not a refusal that runs',
    );
    // The refusal must read the DISPATCH INPUTS, not constants. _runRefusal
    // supplies FROM_TRACK/TO_TRACK from Dart's own environment and never
    // looked at the step's `env:`, so rewiring it to
    // `FROM_TRACK: internal / TO_TRACK: alpha` — or deleting the block —
    // left a refusal that always passes while the real inputs flowed on to
    // `promote`, with the suite green (#184).
    for (final wiring in const [
      (name: 'FROM_TRACK', input: 'from_track'),
      (name: 'TO_TRACK', input: 'to_track'),
    ]) {
      expect(
        refuse.env[wiring.name],
        '\${{ inputs.${wiring.input} }}',
        reason:
            'refusal: the refusal step\'s ${wiring.name} is '
            '`${refuse.env[wiring.name]}`, not the dispatch input. It would '
            'evaluate something the user never typed',
      );
    }

    for (final probe in const [
      (from: 'internal', to: 'production', shouldPass: false),
      (from: 'production', to: 'alpha', shouldPass: false),
      (from: 'internal', to: 'nonsense', shouldPass: false),
      (from: 'alpha', to: 'alpha', shouldPass: false),
      (from: 'internal', to: 'alpha', shouldPass: true),
    ]) {
      final code = _runRefusal(refuse.run!, probe.from, probe.to);
      if (probe.shouldPass) {
        expect(
          code,
          0,
          reason:
              'refusal: `${probe.from} -> ${probe.to}` is a legitimate '
              'promotion and was refused — a refusal that blocks everything '
              'is not a working guard',
        );
      } else {
        expect(
          code,
          isNot(0),
          reason:
              'refusal: `${probe.from} -> ${probe.to}` was ACCEPTED by the '
              'refusal step in `${job.name}`',
        );
      }
    }

    expect(
      refuse.isUnconditional,
      isTrue,
      reason:
          'refusal: the refusal in `${job.name}` is conditional '
          '(if: ${refuse.ifExpression}, continue-on-error: '
          '${refuse.continueOnError}) — it would be skipped or ignored',
    );

    // Every step that ACTS must be unconditional. Only the first step was
    // checked, so `if: always()` on `promote` was green and the "a failed
    // refusal stops the run" guarantee was gone (#171). The reporting and
    // cleanup steps are the deliberate exceptions: they exist to run on the
    // refusal path, and they are named rather than pattern-matched.
    const mayAlwaysRun = {'summary', 'forget'};
    for (final step in job.steps) {
      if (mayAlwaysRun.contains(step.id)) {
        expect(
          step.ifExpression,
          'always()',
          reason:
              'refusal: `${step.id}` is allowed to run after a refusal only '
              'as `if: always()`',
        );
        continue;
      }
      expect(
        step.isUnconditional,
        isTrue,
        reason:
            'refusal: step `${step.id ?? step.index}` of `${job.name}` is '
            'conditional (if: ${step.ifExpression}, continue-on-error: '
            '${step.continueOnError}), so it can run although the refusal '
            'failed',
      );
    }
  }
}

void main() {
  test('the script exists and is executable', () {
    expect(pathExists(_script), isTrue);
    final mode = File('${repoRoot.path}/$_script').statSync().mode;
    expect(mode & 0x40, isNot(0), reason: '$_script is not executable');
  });

  group('refuses before it ever looks for a token', () {
    test('production as the target', () {
      // Checked with a valid token present, so the refusal cannot be
      // attributed to the missing credential.
      final r = _run([_package, 'internal', 'production'], token: 'fake');
      expect(r.code, 2, reason: 'production-refused: ${r.err}');
      expect(r.out.trim(), isEmpty);
      expect(r.err.toLowerCase(), contains('production'));
    });

    test('production as the source', () {
      final r = _run([_package, 'production', 'alpha'], token: 'fake');
      expect(r.code, 2);
      expect(r.out.trim(), isEmpty);
    });

    for (final track in const ['internal', 'alpha', 'beta']) {
      test('$track to itself', () {
        final r = _run([_package, track, track], token: 'fake');
        expect(r.code, 2, reason: 'same-track: $track to $track was allowed');
        expect(r.out.trim(), isEmpty);
      });
    }

    for (final bad in const ['staging', 'Internal', 'prod', '']) {
      test('the unknown track `$bad`', () {
        final r = _run([_package, 'internal', bad], token: 'fake');
        expect(r.code, 2, reason: 'allowlist: `$bad` was allowed');
        expect(r.out.trim(), isEmpty);
      });
    }

    test('a missing package argument', () {
      expect(_run(['', 'internal', 'alpha'], token: 'fake').code, 2);
      expect(_run(const [], token: 'fake').code, 2);
      expect(_run([_package, 'internal'], token: 'fake').code, 2);
    });
  });

  test('a missing token is refused, with valid arguments', () {
    // The order matters and is asserted: arguments first, token second.
    final r = _run([_package, 'internal', 'alpha']);
    expect(r.code, 2, reason: 'no-token: ${r.err}');
    expect(r.out.trim(), isEmpty);
    expect(r.err.toUpperCase(), contains('PLAY_TOKEN'));
  });

  test('valid arguments and a fake token reach the API and stop', () {
    // Exit 5 is the API layer, distinct from 2. If this ever returns 2 the
    // argument checks have started rejecting something they should accept,
    // and the refusal tests above would still pass while the script had
    // stopped working. The API is a closed loopback port, not Google — see
    // _unreachableApi.
    final r = _run([_package, 'internal', 'alpha'], token: 'not-a-real-token');
    expect(
      r.code,
      5,
      reason:
          'api-reached: expected the API failure code, not an argument '
          'refusal.\n${r.err}',
    );
  });

  test('the workflow refuses at its own layer too', () {
    // Two barriers at different layers: the workflow exits 1 before any API
    // call, the script exits 2. Either alone would be enough; both means a
    // change to one does not silently remove the guarantee.
    final workflow = readFile('.github/workflows/play-promote.yml');
    expect(workflow, contains('production'));
    expect(
      workflow,
      contains('exit 1'),
      reason:
          'workflow-refusal: the dispatch step must refuse before the '
          'script is ever called',
    );
  });

  test('the refusal is first, unconditional, and nothing else mints a credential', () {
    // Parsed, not grepped. The line-scan version was defeated four ways with a
    // green suite: `exit 1` present only in a comment, `continue-on-error` on
    // the refusal, `if: always()` on the steps after it, and an entire second
    // job with no refusal at all (#154).
    _assertPromoteShape(
      Workflow.parse(
        '.github/workflows/play-promote.yml',
        readFile('.github/workflows/play-promote.yml'),
      ),
    );
  });

  test('the refusal rule catches each way it was defeated', () {
    final text = readFile('.github/workflows/play-promote.yml');
    final mutations = <String, String Function(String)>{
      'refusal moved to last': (t) {
        final blocks = t.split(RegExp(r'^(?=      - )', multiLine: true));
        final refuse = blocks.firstWhere(
          (b) => b.startsWith('      - id: refuse'),
        );
        final rest = blocks.where((b) => b != refuse).toList();
        return rest.join() + refuse;
      },
      'refusal disabled with if: false': (t) => t.replaceFirst(
        '      - id: refuse\n',
        '      - id: refuse\n        if: false\n',
      ),
      'refusal made advisory with continue-on-error': (t) => t.replaceFirst(
        '      - id: refuse\n',
        '      - id: refuse\n        continue-on-error: true\n',
      ),
      'an id-less step mints the credential first': (t) => t.replaceFirst(
        '      - id: refuse\n',
        '      - name: mint early\n'
            '        run: gcloud auth activate-service-account\n'
            '      - id: refuse\n',
      ),
      'a second job with no refusal': (t) =>
          '$t\n  sneaky:\n    runs-on: ubuntu-latest\n    steps:\n'
          '      - id: token\n        run: gcloud auth activate-service-account\n'
          '      - id: promote\n        run: tools/play_promote.sh pkg internal production\n',
      // #179 / #165: the input constraint reverted.
      'to_track reverted to free text': (t) => t.replaceFirst(
        '        default: alpha\n'
            '        type: choice\n'
            '        options: [internal, alpha, beta]\n',
        '        default: alpha\n        type: string\n',
      ),
      'production added to the options': (t) => t.replaceAll(
        'options: [internal, alpha, beta]',
        'options: [internal, alpha, beta, production]',
      ),
      // #171: the four remaining defeats of the text-matching version.
      'every exit 1 becomes a shell comment': (t) => t.replaceAllMapped(
        RegExp(r'^(\s*)exit 1$', multiLine: true),
        (m) => '${m[1]}: # exit 1',
      ),
      'exit 1 survives only inside an uncalled function': (t) => t
          .replaceAllMapped(
            RegExp(r'^(\s*)exit 1$', multiLine: true),
            (m) => '${m[1]}:',
          )
          .replaceFirst(
            '          set -euo pipefail\n',
            '          set -euo pipefail\n'
                '          never_called() { exit 1; }\n',
          ),
      'exit 1 survives only inside if false': (t) => t
          .replaceAllMapped(
            RegExp(r'^(\s*)exit 1$', multiLine: true),
            (m) => '${m[1]}:',
          )
          .replaceFirst(
            '          set -euo pipefail\n',
            '          set -euo pipefail\n'
                '          if false; then exit 1; fi\n',
          ),
      'if: always() on the promote step': (t) => t.replaceFirst(
        '      - id: promote\n',
        '      - id: promote\n        if: always()\n',
      ),
      'continue-on-error as a quoted string': (t) => t.replaceFirst(
        '      - id: refuse\n',
        '      - id: refuse\n        continue-on-error: "true"\n',
      ),
      'a reusable-workflow job with no steps': (t) =>
          '$t\n  sneaky:\n    uses: ./.github/workflows/evil.yml\n'
          '    secrets: inherit\n',
      // There is no 'first exit 1 commented out' entry, and that is a
      // finding rather than an omission. The entry that used to be here
      // passed `r'$1: # exit 1'` to replaceFirst, which inserts it
      // LITERALLY: a `$1` landed at column 0, terminated the block scalar,
      // and the shape assertion threw on `expect(wf.problem, isNull)`. The
      // battery scored that as a catch, so the one entry that would have
      // found #171's shell-comment defeat reported a pass while it was live
      // (#172).
      //
      // Written correctly it does not defeat anything: the refusal rejects
      // production twice — once by name, once by falling through the `case`
      // to `*)` — so neutering the first `exit 1` leaves production refused.
      // The honest mutation is the one below, which neuters them all.
    };
    mutations.forEach((why, mutate) {
      final mutated = mutate(text);
      expect(mutated, isNot(text), reason: 'sanity: "$why" changed nothing');
      expect(
        Workflow.parse('play-promote.yml', mutated).problem,
        isNull,
        reason: 'sanity: "$why" produced YAML that does not parse',
      );
      expect(
        () => _assertPromoteShape(Workflow.parse('play-promote.yml', mutated)),
        throwsA(isA<TestFailure>()),
        reason: 'refusal-negative: "$why" was not caught',
      );
    });
  });

  group('a failed edit deletion is reported, not swallowed', () {
    // curl without --fail exits 0 for an HTTP error, so #161's warning —
    // which keyed off curl's exit status — could not fire. A DELETE answered
    // 500 left an edit pending on the Play account while the run printed
    // promoted=101 and exited 0, which is the outcome the warning exists to
    // prevent. Two of the three delete sites had no warning branch at all
    // (#178).
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('hs-promote'));
    tearDown(() => dir.deleteSync(recursive: true));

    /// A curl that opens an edit, then answers everything else 500 — so the
    /// script dies, the EXIT trap runs, and the cleanup DELETE is the call
    /// under test.
    void stubCurl() {
      final f = File('${dir.path}/curl')..writeAsStringSync(_curlStub);
      Process.runSync('chmod', ['+x', f.path]);
    }

    ({int code, String err}) run() {
      final r = Process.runSync(
        _script,
        [_package, 'internal', 'alpha'],
        workingDirectory: repoRoot.path,
        includeParentEnvironment: false,
        environment: {
          'PATH': '${dir.path}:/usr/bin:/bin',
          'PLAY_TOKEN': 'fake',
          'HS_PLAY_API': _unreachableApi,
        },
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      return (code: r.exitCode, err: r.stderr.toString());
    }

    test('a DELETE answered 500 warns that the edit is still pending', () {
      stubCurl();
      final r = run();
      expect(r.code, isNot(0), reason: 'the run itself must still fail');
      expect(
        r.err,
        contains('still pending'),
        reason:
            'a DELETE that failed must say so: the edit stays on the Play '
            'account and blocks the next promotion',
      );
    });

    test('every delete in the script goes through delete_edit', () {
      // Two of three sites had no warning branch, so the fix is only as good
      // as its application. A bare `curl ... -X DELETE` anywhere in the
      // script means one more silent failure.
      // Continuations joined FIRST. The real invocation wraps — `curl …\`
      // on one line, `-X DELETE …` on the next — and `[^\n]*` cannot cross
      // a newline, so the pattern matched ZERO strings and this assertion
      // passed unconditionally. I proved it blind by injecting a bare
      // multi-line DELETE, which it did not notice (#183).
      final text = File('${repoRoot.path}/$_script')
          .readAsStringSync()
          .replaceAll(RegExp(r'\\\n\s*'), ' ');
      final deletes = RegExp(r'curl[^\n]*-X DELETE')
          .allMatches(text)
          .map((m) => m.group(0)!)
          .toList();
      // The count, so a NEW delete site is noticed rather than silently
      // joining the ones already checked.
      expect(
        deletes,
        hasLength(1),
        reason:
            'delete-sites: expected exactly one curl -X DELETE, in '
            'delete_edit. Found ${deletes.length}: $deletes',
      );
      final bare = deletes.where((m) => !m.contains('--fail')).toList();
      expect(
        bare,
        isEmpty,
        reason: 'a DELETE without --fail cannot detect an HTTP error: $bare',
      );
    });
  });
}
