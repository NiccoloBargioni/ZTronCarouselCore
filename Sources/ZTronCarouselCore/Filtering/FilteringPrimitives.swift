import Foundation

/// How multiple active filters combine when selecting the visible subset of medias.
///
/// - `and`: a media is visible iff it satisfies **every** active filter (intersection).
/// - `or`: a media is visible iff it satisfies **at least one** active filter (union).
///
/// When the strategy is `nil` (the default everywhere it appears), `.and` semantics are used
/// whenever two or more filters are active. With zero or one active filter the strategy is irrelevant.
public enum FilteringStrategy: Sendable, Equatable {
    case and
    case or
}

/// The default `Filter` type used when a filterable component is created without specifying one.
///
/// `EmptyFilter` is an *uninhabited* enum: no value of it can ever exist, therefore no filter can
/// ever be declared or activated. A `FilterableCarouselComponent<EmptyFilter>` is thus guaranteed,
/// at the type level, to behave exactly like a plain `CarouselComponent`, which is what preserves
/// backward compatibility.
public enum EmptyFilter: Hashable, Sendable, CaseIterable {
    public static var allCases: [EmptyFilter] { [] }
}
