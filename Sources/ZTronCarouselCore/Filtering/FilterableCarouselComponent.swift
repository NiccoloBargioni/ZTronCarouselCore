import UIKit

/// A `CarouselComponent` that can restrict the displayed medias to the subset satisfying a set of
/// client-defined filters, while preserving the original dataset.
///
/// ```swift
/// enum MyFilter: Hashable { case onlyImages, hasOutline }
///
/// let carousel = FilterableCarouselComponent<MyFilter>(
///     medias: medias,
///     filteringStrategy: .and          // optional, defaults to nil (== .and when 2+ filters are active)
/// )
/// .declareEffect(.onlyImages) { $0.type == .image }
/// .declareEffect(.hasOutline) { ($0 as? MyDescriptor)?.hasOutline ?? false }
/// .activateFilter(.onlyImages)
/// .activateFilter(.hasOutline)
/// .disableFilter(.hasOutline)
/// ```
///
/// Behavior:
/// - The original medias are preserved; filters only affect what is presented.
/// - When the currently displayed media does not satisfy the new set of filters, the component skips,
///   with animation, to the closest media (by absolute difference of original position) that does.
/// - When *no* media satisfies the filters, no assert is raised: the component displays a placeholder
///   page (customizable via ``emptyResultsPlaceholderFactory`` or by overriding
///   ``CarouselComponent/makeEmptyPlaceholderPage()``).
/// - `replaceAllMedias(with:present:animated:)` keeps working: the new dataset is ingested as the new
///   *original* medias and the active filters are re-applied to it. The `present` index is interpreted
///   in **original space**, so upstream code (DB loaders, search) does not need to know about filtering.
/// - `FilterableCarouselComponent` created without an explicit `Filter` type falls back to
///   ``EmptyFilter`` and behaves exactly like a plain `CarouselComponent`.
@MainActor open class FilterableCarouselComponent<Filter: Hashable>: CarouselComponent {

    /// The filtering engine. Exposed read-only so cooperating objects (e.g. a gallery-level filtering
    /// coordinator) can evaluate the same predicates against arbitrary medias.
    public let filteringModel: MediaFilteringModel<Filter>

    /// `visibleToOriginal[v]` is the original-space index of the media currently displayed at visible
    /// index `v`. Identity mapping when no filter is active.
    public private(set) var visibleToOriginal: [Int]

    /// The last meaningful original-space focus. Used to restore a sensible position when filters are
    /// relaxed after an empty result, and as a fallback anchor.
    private var anchorOriginalIndex: Int = 0

    /// When non-nil, used to build the page displayed when no media satisfies the active filters.
    /// Falls back to `makeEmptyPlaceholderPage()` (i.e. the default carousel placeholder) when nil.
    public var emptyResultsPlaceholderFactory: (() -> any CountedUIViewController)? = nil

    /// Invoked every time the set of visible medias changes because of filtering.
    /// The parameter is the outcome that was just presented.
    public var onFilteringOutcomeChanged: ((MediaFilteringModel<Filter>.Outcome) -> Void)? = nil

    // MARK: - Init

    public init(
        with pageFactory: MediaFactory = BasicMediaFactory(),
        medias: [any VisualMediaDescriptor],
        filteringStrategy: FilteringStrategy? = nil,
        onPageChanged: ((String, Int) -> Void)? = nil
    ) {
        self.filteringModel = MediaFilteringModel<Filter>(medias: medias, strategy: filteringStrategy)
        self.visibleToOriginal = Array(medias.indices)
        super.init(with: pageFactory, medias: medias, onPageChanged: onPageChanged)
    }

    public required init?(coder: NSCoder) {
        return nil
    }

    // MARK: - Fluent filtering interface

    /// Declares (or replaces) the effect associated to `filter`. If `filter` is currently active, the
    /// visible medias are recomputed immediately.
    @discardableResult
    public final func declareEffect(_ filter: Filter, _ effect: @escaping (any VisualMediaDescriptor) -> Bool) -> Self {
        self.filteringModel.declareEffect(filter, effect)

        if self.filteringModel.activeFilters.contains(filter) {
            self.reapplyFilters()
        }

        return self
    }

    /// Activates `filter`. The visible medias become the subset of the original medias satisfying all
    /// (or any, depending on the strategy) active filters.
    @discardableResult
    public final func activateFilter(_ filter: Filter) -> Self {
        guard self.filteringModel.activate(filter) else { return self }
        self.reapplyFilters()
        return self
    }

    /// Deactivates `filter`. The visible medias become the subset affected by the remaining active
    /// filters, combined according to the strategy (when applicable).
    @discardableResult
    public final func disableFilter(_ filter: Filter) -> Self {
        guard self.filteringModel.deactivate(filter) else { return self }
        self.reapplyFilters()
        return self
    }

    /// Deactivates every active filter, restoring the full original dataset.
    @discardableResult
    public final func disableAllFilters() -> Self {
        guard self.filteringModel.isFiltering else { return self }
        self.filteringModel.deactivateAllFilters()
        self.reapplyFilters()
        return self
    }

    /// How multiple active filters combine. Assigning a new value re-applies the filters.
    public final var filteringStrategy: FilteringStrategy? {
        get { self.filteringModel.strategy }
        set {
            guard newValue != self.filteringModel.strategy else { return }
            self.filteringModel.strategy = newValue
            if self.filteringModel.isFiltering {
                self.reapplyFilters()
            }
        }
    }

    public final var activeFilters: Set<Filter> {
        return self.filteringModel.activeFilters
    }

    /// The preserved original dataset.
    public final var originalMedias: [any VisualMediaDescriptor] {
        return self.filteringModel.allMedias
    }

    // MARK: - Integration with CarouselComponent

    /// Intercepts every dataset replacement (`replaceAllMedias`): the incoming medias become the new
    /// original dataset, and the active filters are applied before presentation. `requestedIndex` is
    /// interpreted in original space.
    override open func resolveMediasForPresentation(
        _ medias: [any VisualMediaDescriptor],
        requestedIndex: Int
    ) -> (medias: [any VisualMediaDescriptor], index: Int) {
        self.filteringModel.replaceAllMedias(medias)

        let outcome = self.filteringModel.outcome(anchoredAt: requestedIndex)
        self.visibleToOriginal = outcome.visibleToOriginal
        self.anchorOriginalIndex = outcome.anchorOriginalIndex
        self.onFilteringOutcomeChanged?(outcome)

        return (outcome.visibleMedias, outcome.presentVisibleIndex)
    }

    override open func makeEmptyPlaceholderPage() -> any CountedUIViewController {
        if let factory = self.emptyResultsPlaceholderFactory {
            return factory()
        }

        return super.makeEmptyPlaceholderPage()
    }

    /// Recomputes the visible subset from the preserved original medias and presents the result.
    ///
    /// - The anchor is the original-space index of the media currently on screen (or the last known
    ///   anchor when the carousel is currently displaying the empty-result placeholder).
    /// - If the anchor survives, the presentation stays on it (indices are remapped silently, without
    ///   animation). Otherwise the carousel skips **with animation** to the closest surviving media.
    /// - If nothing survives, the empty-result placeholder is displayed.
    public final func reapplyFilters(animated: Bool = true) {
        let currentOriginal: Int
        if self.visibleToOriginal.indices.contains(self.currentPage) {
            currentOriginal = self.visibleToOriginal[self.currentPage]
        } else {
            currentOriginal = self.anchorOriginalIndex
        }

        let outcome = self.filteringModel.outcome(anchoredAt: currentOriginal)
        self.visibleToOriginal = outcome.visibleToOriginal
        self.anchorOriginalIndex = outcome.anchorOriginalIndex

        self.presentResolvedMedias(
            outcome.visibleMedias,
            present: outcome.presentVisibleIndex,
            animated: animated && outcome.movedAway
        )

        self.onFilteringOutcomeChanged?(outcome)
    }
}

// MARK: - Backward-compatible, filterless construction

public extension FilterableCarouselComponent where Filter == EmptyFilter {
    /// Creates a filterless component, indistinguishable in behavior from a plain `CarouselComponent`.
    /// Lets `FilterableCarouselComponent(medias:)` compile without spelling any `Filter` type,
    /// inferring ``EmptyFilter``.
    convenience init(
        with pageFactory: MediaFactory = BasicMediaFactory(),
        medias: [any VisualMediaDescriptor],
        onPageChanged: ((String, Int) -> Void)? = nil
    ) {
        self.init(with: pageFactory, medias: medias, filteringStrategy: nil, onPageChanged: onPageChanged)
    }
}
