/*
 * FLauncher
 * Copyright (C) 2021  Étienne Fesser
 * Copyright (C) 2026  Yoram van de Velde
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import 'dart:math';

import 'package:flutter/material.dart';

/// This traversal policy manage the up and down direction to be totally
/// predictable.
/// Going up or down will always go to the next or previous row. All other
/// traversal policy try to be smart, and in some cases can skip rows when
/// going up or down.
class RowByRowTraversalPolicy extends FocusTraversalPolicy with DirectionalFocusTraversalPolicyMixin {
  @override
  Iterable<FocusNode> sortDescendants(Iterable<FocusNode> descendants, FocusNode currentNode) => descendants;

  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    List<FocusNode>? nodes = currentNode.nearestScope?.traversalDescendants.toList();
    if (nodes == null) {
      return super.inDirection(currentNode, direction);
    }

    NodeSearcher searcher = NodeSearcher(direction);
    List<CandidateNode> candidates = searcher.findCandidates(nodes, currentNode);
    if (candidates.isEmpty && direction == TraversalDirection.right) {
      // Reached the end of the row. This usually means "stay put" (e.g. the last item of a
      // long row that already reaches the edge of the screen has nothing further right at all)
      // -- except the header's settings icon, which sits above-and-to-the-right of the
      // *topmost* app row specifically (there's no equivalent shortcut on the left, so this
      // only applies to "right"), and should stay reachable from there. Look for something
      // that is both above AND still to the right, rather than either falling through to
      // Flutter's own built-in directional search (whose "nearest in that general direction"
      // heuristics changed between Flutter versions, and silently started jumping down a row
      // instead of up to the header) or a plain "nearest above" search (which would incorrectly
      // jump to the row above for every other row too, not just the topmost one, since that's
      // what "stays on the same row" tests for explicitly).
      candidates = searcher.findCandidatesAboveOnSameSide(nodes, currentNode);
    }
    if (candidates.isEmpty) {
      return super.inDirection(currentNode, direction);
    }
    FocusNode nextNode = searcher.findBestFocusNode(candidates, currentNode);
    nextNode.requestFocus();
    return true;
  }
}

class NodeSearcher {
  final TraversalDirection directionToSearch;

  NodeSearcher(this.directionToSearch);

  /// should be called first
  List<CandidateNode> findCandidates(List<FocusNode> nodes, FocusNode from) {
    List<FocusNode> copy = List.from(nodes, growable: true);

    switch (directionToSearch) {
      case TraversalDirection.up:
        copy.removeWhere((element) => element.isBelowOrEquals(from));
        break;
      case TraversalDirection.down:
        copy.removeWhere((element) => element.isAboveOrEquals(from));
        break;
      case TraversalDirection.right:
        copy.removeWhere((element) => element.isLeftToOrEquals(from) || !element.isOnTheSameRow(from));
        break;
      case TraversalDirection.left:
        copy.removeWhere((element) => element.isRightToOrEquals(from) || !element.isOnTheSameRow(from));
        break;
    }
    return toCandidateNodes(copy);
  }

  /// Used as a fallback when [findCandidates] finds nothing further right along the row: looks
  /// for a node that is both above `from` and still to the right of it, e.g. the header's
  /// settings icon reachable from the end of the topmost app row.
  List<CandidateNode> findCandidatesAboveOnSameSide(List<FocusNode> nodes, FocusNode from) {
    final copy = List<FocusNode>.from(nodes, growable: true);
    copy.removeWhere((element) => element.isBelowOrEquals(from) || element.isLeftToOrEquals(from));
    // With 3+ rows, "above and to the right" can also match app cards in a row that's merely
    // closer above (not just the header) -- keep only the top-most matches so the header wins
    // over any such row, matching the "topmost row only" intent instead of picking whichever
    // candidate happens to have the smallest x.
    if (copy.isNotEmpty) {
      final minDy = copy.map((node) => node.rect.center.dy.round()).reduce(min);
      copy.removeWhere((node) => node.rect.center.dy.round() != minDy);
    }
    return toCandidateNodes(copy);
  }

  FocusNode findBestFocusNode(List<CandidateNode> nodes, FocusNode from) {
    List<FocusNode> candidates = toFocusNodes(nodes);

    return candidates.reduce((bestNode, challenger) {
      if (directionToSearch == TraversalDirection.down && challenger.isAbove(bestNode)) {
        return challenger;
      } else if (directionToSearch == TraversalDirection.up && challenger.isBelow(bestNode)) {
        return challenger;
      } else if (directionToSearch == TraversalDirection.left && challenger.isRightTo(bestNode)) {
        return challenger;
      } else if (directionToSearch == TraversalDirection.right && challenger.isLeftTo(bestNode)) {
        return challenger;
      }
      // compute the element which is the closest horizontally
      if (challenger.isOnTheSameRow(bestNode) && challenger.distance(from) < bestNode.distance(from)) {
        return challenger;
      }
      return bestNode;
    });
  }
}

/// An internal object to use the [NodeSearcher] class as expected
class CandidateNode {
  final FocusNode node;

  CandidateNode(this.node);
}

/// Some conversion utilities used internally
List<CandidateNode> toCandidateNodes(List<FocusNode> nodes) => nodes.map((e) => CandidateNode(e)).toList();

List<FocusNode> toFocusNodes(List<CandidateNode> nodes) => nodes.map((e) => e.node).toList();

/// A few extension methods to the [FocusNode] to be able to compare their
/// respective position easily.
extension Geometry on FocusNode {
  bool isBelow(FocusNode other) {
    return rect.center.dy.round() > other.rect.center.dy.round();
  }

  bool isBelowOrEquals(FocusNode other) {
    return rect.center.dy.round() >= other.rect.center.dy.round();
  }

  bool isRightTo(FocusNode other) {
    return rect.center.dx.round() > other.rect.center.dx.round();
  }

  bool isRightToOrEquals(FocusNode other) {
    return rect.center.dx.round() >= other.rect.center.dx.round();
  }

  bool isLeftTo(FocusNode other) {
    return rect.center.dx.round() < other.rect.center.dx.round();
  }

  bool isLeftToOrEquals(FocusNode other) {
    return rect.center.dx.round() <= other.rect.center.dx.round();
  }

  bool isAbove(FocusNode other) {
    return rect.center.dy.round() < other.rect.center.dy.round();
  }

  bool isAboveOrEquals(FocusNode other) {
    return rect.center.dy.round() <= other.rect.center.dy.round();
  }

  bool isOnTheSameRow(FocusNode other) {
    return rect.center.dy.round() == other.rect.center.dy.round();
  }

  double distance(FocusNode other) {
    return sqrt(pow(rect.center.dx.round() - other.rect.center.dx.round(), 2) +
        pow(rect.center.dy.round() - other.rect.center.dy.round(), 2));
  }
}
