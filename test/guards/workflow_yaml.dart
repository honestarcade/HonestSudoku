// Structural reading of a GitHub Actions workflow.
//
// Three rounds of guards asserted structure with line scans and three rounds
// of bypasses followed (#131, #141, #154). A `contains()` cannot tell code
// from a comment; a regex over `- id:` lines cannot see a second job, an
// `if:`, or `continue-on-error`. So this parses.
//
// `package:yaml` is a **dev** dependency: it never ships, `flutter build` does
// not resolve dev_dependencies, and every built bundle is byte-scanned anyway.
// The convention in repo_files.dart — guards add no dependencies — was written
// against a *runtime* dependency, which invariant 3 governs and which a build
// could silently drop. A test-only package that went missing would fail to
// compile these guards, loudly, rather than let them pass.
import 'package:yaml/yaml.dart';

/// One `run:` script, with the line its value starts on.
class RunScript {
  const RunScript(this.body, this.line, this.jobName, this.stepId);

  /// The script text as the shell will receive it, aliases resolved.
  final String body;

  /// 1-based line in the source file where the value begins.
  final int line;
  final String jobName;
  final String? stepId;
}

/// One step of a job, read structurally rather than by its text.
class WorkflowStep {
  const WorkflowStep({
    required this.index,
    required this.line,
    this.id,
    this.name,
    this.ifExpression,
    this.uses,
    this.run,
    this.shell,
    this.continueOnError = false,
    this.with_ = const {},
  });

  final int index;
  final int line;
  final String? id;
  final String? name;

  /// The raw `if:` expression, or null when the step is unconditional. The
  /// distinction matters: `if: always()` on a step is what turns "nothing
  /// ships when an earlier step fails" into a step that ships anyway.
  final String? ifExpression;
  final String? uses;
  final String? run;
  final String? shell;
  final bool continueOnError;

  /// The step's `with:` inputs, flattened to strings — what an action is
  /// actually told to do (`track`, `status`, `retention-days`).
  final Map<String, String> with_;

  /// A step that always runs when reached: no `if:`, no `continue-on-error`.
  bool get isUnconditional => ifExpression == null && !continueOnError;
}

/// One job.
class WorkflowJob {
  const WorkflowJob({
    required this.name,
    required this.steps,
    this.line = 0,
    this.uses,
    this.needs = const [],
    this.ifExpression,
    this.secretsInherit = false,
    this.defaultShell,
    this.continueOnError = false,
    this.runsOn,
    this.environment,
    this.permissionsScalar,
  });

  final String name;
  final List<WorkflowStep> steps;

  /// 1-based line of the job's key, for naming it in a failure.
  final int line;

  /// The reusable workflow this job calls, for a `uses:` job.
  final String? uses;
  final List<String> needs;
  final String? ifExpression;
  final bool secretsInherit;

  /// `defaults.run.shell` for this job, if it sets one.
  final String? defaultShell;

  /// `continue-on-error:` on the JOB. GitHub treats such a job's failure as
  /// non-blocking for everything that `needs:` it, so a gate carrying this
  /// still lets its dependants run — the same hole an `if:` on the dependant
  /// opens, one level up, and invisible to any assertion about the dependant
  /// (#169).
  final bool continueOnError;

  final String? runsOn;

  /// `environment:`, as a name. A deployment environment can carry required
  /// reviewers and its own secrets, so adding or changing one changes who can
  /// release and with what.
  final String? environment;

  /// `permissions:` on the job, as a scalar. See [Workflow.permissionsScalar].
  final String? permissionsScalar;

  WorkflowStep? stepById(String id) {
    for (final step in steps) {
      if (step.id == id) return step;
    }
    return null;
  }

  int indexOfId(String id) => steps.indexWhere((s) => s.id == id);
}

/// A parsed workflow. [problem] is non-null when the file could not be read as
/// a workflow at all — which is a failure to report, never a quiet pass.
class Workflow {
  Workflow._(
    this.path,
    this.jobs,
    this.defaultShell,
    this.triggers,
    this.pushTags,
    this.pushBranches,
    this.runScripts,
    this.problem, {
    this.hasPermissions = false,
    this.permissionsScalar,
    this.hasConcurrency = false,
  });

  final String path;
  final List<WorkflowJob> jobs;

  /// The keys under `on:`, so a trigger change is visible.
  final List<String> triggers;

  /// `defaults.run.shell` at workflow level, and the same per job.
  ///
  /// A step's `shell:` was modelled and this was not, so changing the
  /// workflow-level `shell: bash` to `bash -x` — a two-character diff on a
  /// line that already exists — turned tracing on for every step in the job
  /// holding all five secrets, with the suite green (#168).
  final String? defaultShell;

  /// `on.push.tags` and `on.push.branches`. The key alone is not enough:
  /// swapping `tags: ['v*']` for `branches: [main]` leaves the trigger named
  /// `push` while turning every merge into a release (#154).
  final List<String> pushTags;
  final List<String> pushBranches;
  final List<RunScript> runScripts;
  final String? problem;

  /// A top-level `permissions:` key of any shape.
  final bool hasPermissions;

  /// `permissions:` when written as a scalar (`read-all`, `write-all`),
  /// rather than a map of scopes. Parsed rather than line-matched, so the
  /// quoted spelling `permissions: 'write-all'` is the same value as the
  /// unquoted one — the line scan caught only the unquoted form (#175).
  final String? permissionsScalar;

  final bool hasConcurrency;

  /// Every `uses:` in the file, job-level and step-level, with its line.
  /// A job's `uses:` was parsed and never consulted by the pin rule, and a
  /// step written as a flow mapping (`- {uses: x}`) was invisible to the
  /// line scan entirely (#171, #175).
  Iterable<({String uses, int line, String where})> get allUses sync* {
    for (final job in jobs) {
      final jobUses = job.uses;
      if (jobUses != null) {
        yield (uses: jobUses, line: job.line, where: 'job `${job.name}`');
      }
      for (final step in job.steps) {
        final stepUses = step.uses;
        if (stepUses != null) {
          yield (
            uses: stepUses,
            line: step.line,
            where: 'job `${job.name}` step ${step.id ?? step.index}',
          );
        }
      }
    }
  }

  WorkflowJob? job(String name) {
    for (final j in jobs) {
      if (j.name == name) return j;
    }
    return null;
  }

  static Workflow parse(String path, String text) {
    dynamic doc;
    try {
      doc = loadYaml(text);
    } on YamlException catch (e) {
      return Workflow._(
        path,
        const [],
        null,
        const [],
        const [],
        const [],
        const [],
        'unparseable: $e',
      );
    }
    if (doc is! YamlMap) {
      return Workflow._(
        path,
        const [],
        null,
        const [],
        const [],
        const [],
        const [],
        'not a mapping',
      );
    }

    final triggers = <String>[];
    final pushTags = <String>[];
    final pushBranches = <String>[];
    final onNode = _lookup(doc, 'on');
    if (onNode is YamlMap) {
      triggers.addAll(onNode.keys.map((k) => '$k'));
    } else if (onNode is YamlList) {
      triggers.addAll(onNode.map((k) => '$k'));
    } else if (onNode != null) {
      triggers.add('$onNode');
    }
    if (onNode is YamlMap) {
      final push = onNode.nodes['push']?.value;
      if (push is YamlMap) {
        for (final key in const ['tags', 'branches']) {
          final list = push.nodes[key]?.value;
          final into = key == 'tags' ? pushTags : pushBranches;
          if (list is YamlList) {
            into.addAll(list.map((v) => '$v'));
          } else if (list != null) {
            into.add('$list');
          }
        }
      }
    }

    final jobs = <WorkflowJob>[];
    final scripts = <RunScript>[];
    final jobsNode = _lookup(doc, 'jobs');
    if (jobsNode is YamlMap) {
      for (final entry in jobsNode.nodes.entries) {
        final jobName = '${entry.key}';
        final jobMap = entry.value;
        if (jobMap is! YamlMap) continue;

        final needs = <String>[];
        final needsNode = _lookup(jobMap, 'needs');
        if (needsNode is YamlList) {
          needs.addAll(needsNode.map((n) => '$n'));
        } else if (needsNode != null) {
          needs.add('$needsNode');
        }

        final steps = <WorkflowStep>[];
        final stepsNode = jobMap.nodes['steps'];
        if (stepsNode is YamlList) {
          for (var i = 0; i < stepsNode.nodes.length; i++) {
            final stepNode = stepsNode.nodes[i];
            if (stepNode is! YamlMap) continue;
            final runNode = stepNode.nodes['run'];
            final run = runNode?.value is String
                ? runNode!.value as String
                : null;
            steps.add(
              WorkflowStep(
                index: i,
                line: stepNode.span.start.line + 1,
                id: _stringOr(stepNode, 'id'),
                name: _stringOr(stepNode, 'name'),
                ifExpression: _rawOr(stepNode, 'if'),
                uses: _stringOr(stepNode, 'uses'),
                run: run,
                shell: _stringOr(stepNode, 'shell'),
                continueOnError: _isTruthy(
                  _lookup(stepNode, 'continue-on-error'),
                ),
                with_: _stringMap(stepNode, 'with'),
              ),
            );
            if (run != null) {
              scripts.add(
                RunScript(
                  run,
                  runNode!.span.start.line + 1,
                  jobName,
                  _stringOr(stepNode, 'id'),
                ),
              );
            }
          }
        }

        jobs.add(
          WorkflowJob(
            name: jobName,
            steps: steps,
            line: jobMap.span.start.line + 1,
            uses: _stringOr(jobMap, 'uses'),
            needs: needs,
            ifExpression: _rawOr(jobMap, 'if'),
            secretsInherit: '${_lookup(jobMap, 'secrets')}' == 'inherit',
            defaultShell: _defaultShell(jobMap),
            continueOnError: _isTruthy(_lookup(jobMap, 'continue-on-error')),
            runsOn: _stringOr(jobMap, 'runs-on'),
            environment: _environment(jobMap),
            permissionsScalar: _permissionsScalar(jobMap),
          ),
        );
      }
    }
    return Workflow._(
      path,
      jobs,
      _defaultShell(doc),
      triggers,
      pushTags,
      pushBranches,
      scripts,
      null,
      hasPermissions: _lookup(doc, 'permissions') != null,
      permissionsScalar: _permissionsScalar(doc),
      hasConcurrency: _lookup(doc, 'concurrency') != null,
    );
  }
}

/// GitHub honours `continue-on-error: "true"` — the quoted string — exactly
/// as it honours the bare boolean, and an `${{ }}` expression that evaluates
/// to true as well. Comparing to Dart's `true` matched only the unquoted YAML
/// boolean, so the quoted spelling parsed as false and the guard passed
/// (#171).
bool _isTruthy(dynamic value) {
  if (value is bool) return value;
  if (value is String) {
    final v = value.trim().toLowerCase();
    // An expression cannot be evaluated here, so it is treated as possibly
    // true: a step whose skipping depends on a runtime expression is not a
    // step this guard can vouch for.
    return v == 'true' || v.startsWith(r'${{');
  }
  return false;
}

dynamic _lookup(YamlMap map, String key) {
  // `on:` is YAML 1.1's boolean true, which is why a workflow's trigger key
  // parses as `true` rather than the string "on". Both spellings are checked
  // so this does not depend on which the parser chose.
  final direct = map.nodes[key];
  if (direct != null) return direct.value;
  if (key == 'on') {
    final asBool = map.nodes[true];
    if (asBool != null) return asBool.value;
  }
  return null;
}

/// `permissions:` when it is a scalar rather than a map of scopes.
String? _permissionsScalar(YamlMap map) {
  final value = _lookup(map, 'permissions');
  return value is String ? value : null;
}

/// `environment:` as a name, whether written as a bare string or as a map
/// with `name:`.
String? _environment(YamlMap map) {
  final value = _lookup(map, 'environment');
  if (value is String) return value;
  if (value is YamlMap) {
    final name = value.nodes['name']?.value;
    return name is String ? name : null;
  }
  return null;
}

String? _stringOr(YamlMap map, String key) {
  final value = _lookup(map, key);
  return value is String ? value : (value == null ? null : '$value');
}

/// `if:` as written. A present-but-falsey expression still counts as present.
String? _rawOr(YamlMap map, String key) {
  final node = map.nodes[key];
  if (node == null) return null;
  return '${node.value}';
}

Map<String, String> _stringMap(YamlMap map, String key) {
  final node = map.nodes[key];
  if (node is! YamlMap) return const {};
  return {for (final e in node.nodes.entries) '${e.key}': '${e.value.value}'};
}

/// `defaults: run: shell:` on a workflow or a job.
String? _defaultShell(YamlMap map) {
  final defaults = map.nodes['defaults']?.value;
  if (defaults is! YamlMap) return null;
  final run = defaults.nodes['run']?.value;
  if (run is! YamlMap) return null;
  final shell = run.nodes['shell']?.value;
  return shell is String ? shell : null;
}
