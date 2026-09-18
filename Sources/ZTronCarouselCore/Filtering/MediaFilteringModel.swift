import Foundation
import os

/// A pure model that owns the *original* list of medias and computes the *visible* subset out of a set of
/// declared, activatable filters. It never touches UIKit, so it can be unit-tested in isolation.
///
/// Terminology used throughout:
/// - **original space**: indices into `allMedias`, the untouched dataset handed to the component.
/// - **visible space**: indices into the filtered subset that the carousel actually displays.
///
/// Semantics:
/// - A filter is an opaque `Filter` value (typically an `enum` defined by the client) associated to an
///   *effect*, i.e. a predicate `(any VisualMediaDescriptor) -> Bool` declared via ``declareEffect(_:_:)``.
/// - Activating a filter whose effect was never declared is tolerated: the filter behaves as a
///   pass-through (matches everything) and a warning is logged in DEBUG builds. No assert is raised.
/// - With multiple active filters, `strategy` decides the combination; `nil` defaults to `.and`.
/// - An empty result is a legal state (`Outcome.isEmpty == true`); consumers are expected to display
///   a placeholder rather than trap.
@MainActor public final class MediaFilteringModel<Filter: Hashable> {
    private static var logger: os.Logger {
        .init(subsystem: "ZTronCarouselCore", category: "MediaFilteringModel")
    }

    /// The preserved, unfiltered dataset (original space).
    public private(set) var allMedias: [any VisualMediaDescriptor]

    /// How multiple active filters combine. `nil` behaves as `.and`. Assign freely; the owner of this
    /// model is responsible for re-applying the outcome after a change.
    public var strategy: FilteringStrategy?

    public private(set) var activeFilters: Set<Filter> = []
    private var effects: [Filter: (any VisualMediaDescriptor) -> Bool] = [:]

    public init(medias: [any VisualMediaDescriptor], strategy: FilteringStrategy? = nil) {
        self.allMedias = medias
        self.strategy = strategy
    }

    // MARK: - Mutations

    /// Replaces the original dataset, preserving declared effects and active filters.
    public func replaceAllMedias(_ medias: [any VisualMediaDescriptor]) {
        self.allMedias = medias
    }

    /// Associates `effect` to `filter`, overwriting any previously declared effect for the same filter.
    public func declareEffect(_ filter: Filter, _ effect: @escaping (any VisualMediaDescriptor) -> Bool) {
        self.effects[filter] = effect
    }

    /// - Returns: `true` if the set of active filters changed as a consequence of this call.
    @discardableResult public func activate(_ filter: Filter) -> Bool {
        #if DEBUG
        if self.effects[filter] == nil {
            Self.logger.warning("Activated a filter with no declared effect. It will behave as a pass-through. Declare its effect via declareEffect(_:_:).")
        }
        #endif
        return self.activeFilters.insert(filter).inserted
    }

    /// - Returns: `true` if the set of active filters changed as a consequence of this call.
    @discardableResult public func deactivate(_ filter: Filter) -> Bool {
        return self.activeFilters.remove(filter) != nil
    }

    public func deactivateAllFilters() {
        self.activeFilters.removeAll()
    }

    // MARK: - Queries

    public var isFiltering: Bool {
        return !self.activeFilters.isEmpty
    }

    /// Evaluates the active filters (combined according to `strategy`) against a single media.
    /// With no active filters every media is included.
    public func isIncluded(_ media: any VisualMediaDescriptor) -> Bool {
        guard !self.activeFilters.isEmpty else { return true }

        let evaluate: (Filter) -> Bool = { filter in
            guard let effect = self.effects[filter] else { return true } // undeclared → pass-through
            return effect(media)
        }

        switch self.strategy ?? .and {
        case .and:
            return self.activeFilters.allSatisfy(evaluate)
        case .or:
            return self.activeFilters.contains(where: evaluate)
        }
    }

    /// The original-space indices of the medias that satisfy the currently active filters.
    public func includedOriginalIndices() -> [Int] {
        return self.allMedias.enumerated().compactMap { i, media in
            self.isIncluded(media) ? i : nil
        }
    }

    // MARK: - Outcome

    /// The full result of applying the current filters, ready to be presented by a carousel.
    public struct Outcome {
        /// The filtered subset, in original order.
        public let visibleMedias: [any VisualMediaDescriptor]
        /// `visibleToOriginal[v]` is the original-space index of the media at visible index `v`.
        public let visibleToOriginal: [Int]
        /// The visible-space index the carousel should present. `0` when `isEmpty`.
        public let presentVisibleIndex: Int
        /// The original-space index the presentation is anchored to (either the anchor itself when it
        /// survived filtering, or the nearest surviving media, or the requested anchor when empty).
        public let anchorOriginalIndex: Int
        /// `true` when the anchor media did not survive filtering and the presentation had to move
        /// to a different media. Useful to decide whether to animate the transition.
        public let movedAway: Bool

        public var isEmpty: Bool { visibleMedias.isEmpty }
    }

    /// Computes the outcome of the currently active filters, anchored at `originalIndex`
    /// (typically: the original-space index of the media the user is currently looking at).
    ///
    /// If the anchor survives filtering, the outcome presents it. Otherwise the outcome presents the
    /// *closest* surviving media, where distance is `abs(candidate - anchor)` in original space and
    /// ties are resolved forward (toward higher indices).
    public func outcome(anchoredAt originalIndex: Int) -> Outcome {
        let included = self.includedOriginalIndices()
        let clampedAnchor = self.allMedias.isEmpty ? 0 : min(max(0, originalIndex), self.allMedias.count - 1)

        guard !included.isEmpty else {
            return Outcome(
                visibleMedias: [],
                visibleToOriginal: [],
                presentVisibleIndex: 0,
                anchorOriginalIndex: clampedAnchor,
                movedAway: false
            )
        }

        let nearestOriginal: Int
        if included.contains(clampedAnchor) {
            nearestOriginal = clampedAnchor
        } else {
            // Closest by absolute distance; on a tie, prefer the forward (higher-index) candidate.
            nearestOriginal = included.min { lhs, rhs in
                let dl = abs(lhs - clampedAnchor)
                let dr = abs(rhs - clampedAnchor)
                if dl != dr { return dl < dr }
                return lhs > rhs
            }!
        }

        let visibleIndex = included.firstIndex(of: nearestOriginal)!

        return Outcome(
            visibleMedias: included.map { self.allMedias[$0] },
            visibleToOriginal: included,
            presentVisibleIndex: visibleIndex,
            anchorOriginalIndex: nearestOriginal,
            movedAway: nearestOriginal != clampedAnchor
        )
    }
}
