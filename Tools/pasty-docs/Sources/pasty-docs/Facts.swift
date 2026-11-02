import Foundation

/// How an effect's failure is handled at the place it happens.
enum ErrorHandling: String, Codable {
    /// `try?` — the error is swallowed.
    case ignored
    /// Inside `do { } catch { }`.
    case caught
    /// `try` that propagates to the caller.
    case thrown
    /// The API doesn't throw.
    case none
}

struct EffectSite: Codable {
    let effect: Effect
    /// The API that caused it, e.g. `write(to:)`.
    let api: String
    let line: Int
    let errorHandling: ErrorHandling
    /// Source offset, used to check the documented order of effects.
    let offset: Int
}

/// A function, initializer or computed property of a type.
struct Member: Codable {
    enum Kind: String, Codable { case function, initializer, property }

    /// `add(kind:text:)`, `init(store:)`, or `isVisible` — the key used in README headings.
    let key: String
    let name: String
    let kind: Kind
    let isStatic: Bool
    let line: Int
    /// Documentation is required: not private, or private but called by the system
    /// (`@objc`, `override`).
    var isDocumented: Bool
    /// Labels of the parameters, `_` for unlabeled ones.
    let labels: [String]
    /// Which parameters have a default value and may be left out of a call.
    var optional: [Bool] = []
    /// Declared type of a function's result or a property, when it is a plain type name.
    var returnType: String? = nil

    var directEffects: [EffectSite] = []
    /// Members of the same type this one calls or reads (their effects count as its own).
    var localRefs: [String] = []
    /// `Type.member` of other components this one calls or reads.
    var uses: [String] = []
    /// Members of the same type it hands over as callbacks (timers, observers, closures).
    var handlers: [String] = []
    /// Where each local ref is called from, for ordering.
    var localRefOffsets: [String: Int] = [:]

    // Resolved by `Facts.resolve()`: own effects plus those of the private helpers it calls.
    var effects: [Effect] = []
    var allUses: [String] = []
    /// Callbacks stored by it or by the private helpers it calls.
    var allHandlers: [String] = []
    /// Effects whose failures are swallowed or caught, which the README must explain under `Errors:`.
    var handledErrors: [Effect] = []
    /// Earliest source offset of each effect, counting a helper's effects at its call site.
    var firstOffset: [Effect: Int] = [:]
}

struct TypeFacts: Codable {
    enum Role: String, Codable {
        /// Classes and namespace enums with behaviour — what modules are made of.
        case component
        /// SwiftUI views: documented as a whole, not member by member.
        case view
        /// Value types and constants.
        case data
    }

    let name: String
    let module: String
    let file: String
    let line: Int
    var role: Role
    let isPrivate: Bool
    var isClass = false
    /// Stored property name -> type name (when it can be told from the declaration).
    var storedProperties: [String: String] = [:]
    /// Non-private stored properties, which other types may read.
    var publicStoredProperties: Set<String> = []
    var members: [Member] = []
    /// For views: effects and uses of the whole declaration.
    var viewEffects: [EffectSite] = []
    var viewUses: Set<String> = []

    var isDocumented: Bool {
        guard !isPrivate else { return false }
        return role != .data || members.contains(where: \.isDocumented)
    }

    var documentedMembers: [Member] {
        role == .view ? [] : members.filter(\.isDocumented)
    }
}

struct Facts: Codable {
    var types: [TypeFacts]

    func type(named name: String) -> TypeFacts? { types.first { $0.name == name } }

    /// Modules each module depends on, with the `Type.member` uses behind each edge.
    var moduleGraph: [String: [String: Set<String>]] {
        var graph: [String: [String: Set<String>]] = [:]
        for type in types where !type.isPrivate {
            let uses = type.role == .view ? type.viewUses : Set(type.members.flatMap(\.uses))
            graph[type.module, default: [:]] = graph[type.module, default: [:]]
            for use in uses {
                let target = String(use.split(separator: ".").dropLast().joined(separator: "."))
                guard let other = self.type(named: target), other.module != type.module else { continue }
                graph[type.module, default: [:]][other.module, default: []].insert(use)
            }
        }
        return graph
    }

    /// Folds the effects of same-type helpers into their callers.
    mutating func resolve() {
        for t in types.indices {
            let members = types[t].members
            var memo: [String: Member] = [:]
            func resolved(_ key: String, visiting: Set<String>) -> Member? {
                if let done = memo[key] { return done }
                guard var member = members.first(where: { $0.key == key }), !visiting.contains(key) else { return nil }
                var effects = Set(member.directEffects.map(\.effect))
                var uses = Set(member.uses)
                var handlers = Set(member.handlers)
                var handled = Set(member.directEffects.filter { $0.errorHandling == .ignored || $0.errorHandling == .caught }.map(\.effect))
                var first: [Effect: Int] = [:]
                for site in member.directEffects { first[site.effect] = min(first[site.effect] ?? .max, site.offset) }
                for ref in member.localRefs where ref != key {
                    guard let callee = resolved(ref, visiting: visiting.union([key])) else { continue }
                    effects.formUnion(callee.effects)
                    uses.formUnion(callee.allUses)
                    handlers.formUnion(callee.allHandlers)
                    handled.formUnion(callee.handledErrors)
                    let at = member.localRefOffsets[ref] ?? .max
                    for effect in callee.effects { first[effect] = min(first[effect] ?? .max, at) }
                }
                member.effects = effects.sorted()
                member.allUses = uses.sorted()
                member.allHandlers = handlers.sorted()
                member.handledErrors = handled.sorted()
                member.firstOffset = first
                memo[key] = member
                return member
            }
            types[t].members = members.map { resolved($0.key, visiting: []) ?? $0 }
        }
    }
}
