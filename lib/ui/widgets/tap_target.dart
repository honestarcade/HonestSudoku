// A 48-dp tap target around a smaller painted control (#56).
//
// The design scales the whole frame to the phone, so on a short phone a pad
// key can paint 39 px tall. Growing the layout would move the design; this
// keeps layout and painting and grows only what a finger and a screen reader
// see: the hit area and the semantics rect become at least [kMinTapTarget]
// on each side, centred on the painted box. Where neighbours' areas overlap,
// the one hit-tested first (painted last) wins, so a tap in a gap goes to one
// control, deterministically.
//
// A tap outside the parent's own box never reaches this, because the parent
// rejects it first; containers of edge controls leave room (board_screen.dart
// outsets the pad, tools and top bar).

import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// The smallest tap target, Android's 48 dp.
const double kMinTapTarget = 48;

/// Grows [child]'s hit area and semantics rect to at least [kMinTapTarget]
/// square without changing its layout or paint. The semantics node is this
/// widget's: a [Semantics] below it should not be a container.
class TapTarget extends SingleChildRenderObjectWidget {
  /// Wraps [child].
  const TapTarget({required Widget super.child, super.key});

  @override
  RenderTapTarget createRenderObject(BuildContext context) => RenderTapTarget();
}

/// The render object behind [TapTarget].
class RenderTapTarget extends RenderProxyBox {
  /// The grown rect, in this box's coordinates.
  Rect get target {
    final s = size;
    return Rect.fromCenter(
      center: s.center(Offset.zero),
      width: math.max(s.width, kMinTapTarget),
      height: math.max(s.height, kMinTapTarget),
    );
  }

  @override
  Rect get semanticBounds => target;

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config.isSemanticBoundary = true;
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!target.contains(position)) return false;
    // A hit in the grown margin lands on the nearest point of the child.
    final inside = Offset(
      position.dx.clamp(0, math.max(0, size.width - .01)),
      position.dy.clamp(0, math.max(0, size.height - .01)),
    );
    if (hitTestChildren(result, position: inside) || hitTestSelf(inside)) {
      result.add(BoxHitTestEntry(this, position));
      return true;
    }
    return false;
  }
}

/// Makes its [TapTarget]s' grown margins hittable. Intermediate layout boxes
/// (a key's row, the pad's column) reject a hit outside their own size before
/// it reaches the target, so the group sends a hit that lands in a margin, and
/// in no target's painted box, to the target whose grown rect holds it; the
/// last painted wins.
///
/// A margin never reaches through something in front: the hit is forwarded
/// only when every pointer listener the ordinary hit test finds is an
/// ancestor of the target (a scroll view around it, not a scrim over it), and
/// targets are found through the semantics traversal, which skips routes and
/// subtrees that are not on screen.
class TapTargetGroup extends SingleChildRenderObjectWidget {
  /// Wraps [child].
  const TapTargetGroup({required Widget super.child, super.key});

  @override
  RenderTapTargetGroup createRenderObject(BuildContext context) =>
      RenderTapTargetGroup();
}

/// The render object behind [TapTargetGroup].
class RenderTapTargetGroup extends RenderProxyBox {
  List<RenderTapTarget> _targets() {
    final out = <RenderTapTarget>[];
    void visit(RenderObject o) {
      if (o is RenderTapTarget) out.add(o);
      o.visitChildrenForSemantics(visit);
    }

    final c = child;
    if (c != null) visit(c);
    return out;
  }

  static bool _isAncestor(RenderObject maybe, RenderObject of) {
    for (RenderObject? p = of.parent; p != null; p = p.parent) {
      if (identical(p, maybe)) return true;
    }
    return false;
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) return false;
    final targets = _targets().reversed.where((t) => t.attached).toList();
    Offset local(RenderTapTarget t) => MatrixUtils.transformPoint(
      Matrix4.tryInvert(t.getTransformTo(this)) ?? Matrix4.identity(),
      position,
    );
    if (targets.any((t) => (Offset.zero & t.size).contains(local(t)))) {
      return super.hitTest(result, position: position);
    }
    final before = result.path.length;
    final hit = super.hitTest(result, position: position);
    final listeners = [
      for (final e in result.path.skip(before))
        if (e.target is RenderPointerListener) e.target as RenderObject,
    ];
    for (final t in targets) {
      if (!t.target.contains(local(t))) continue;
      if (!listeners.every((l) => _isAncestor(l, t))) break;
      final forwarded = result.addWithPaintTransform(
        transform: t.getTransformTo(this),
        position: position,
        hitTest: (result, transformed) =>
            t.hitTest(result, position: transformed),
      );
      return forwarded || hit;
    }
    return hit;
  }
}
