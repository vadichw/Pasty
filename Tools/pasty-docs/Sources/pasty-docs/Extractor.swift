import Foundation
import SwiftParser
import SwiftSyntax

/// Reads every Swift file under Sources/PastyCore and produces `Facts`: no guessing,
/// only what is literally in the syntax tree.
struct Extractor {
    let sourcesRoot: URL

    private struct ParsedFile {
        let path: String
        let module: String
        let tree: SourceFileSyntax
        let converter: SourceLocationConverter
    }

    /// A type declaration or extension, with the syntax needed for the second pass.
    private struct Decl {
        let typeName: String
        let file: ParsedFile
        let members: MemberBlockSyntax
        let wholeDecl: Syntax
    }

    func extract() throws -> Facts {
        let files = try parseFiles()
        var types: [String: TypeFacts] = [:]
        var decls: [Decl] = []

        // Pass 1: types, their members and stored properties.
        for file in files {
            let collector = DeclCollector(viewMode: .sourceAccurate)
            collector.walk(file.tree)
            for found in collector.found {
                let line = found.node.startLocation(converter: file.converter).line
                var type = types[found.name] ?? TypeFacts(
                    name: found.name, module: file.module, file: file.path, line: line,
                    role: .data, isPrivate: found.isPrivate
                )
                if !found.isExtension {
                    type.role = found.role
                    type.isClass = found.isClass
                }
                for member in found.memberBlock.members {
                    collectDeclaration(member.decl, into: &type, file: file)
                }
                types[found.name] = type
                decls.append(Decl(typeName: found.name, file: file, members: found.memberBlock, wholeDecl: found.node))
            }
        }
        // Namespace enums made only of constants are data, not components.
        for (name, type) in types where type.role == .component && type.members.isEmpty && !type.isClass {
            types[name]?.role = .data
        }

        let context = TypeIndex(types: types)

        // Pass 2: what each member body does.
        for decl in decls {
            guard var type = types[decl.typeName] else { continue }
            if type.role == .view {
                let visitor = BodyVisitor(context: context, typeName: type.name, locals: [:], converter: decl.file.converter)
                visitor.walk(decl.wholeDecl)
                type.viewEffects += visitor.effects
                type.viewUses.formUnion(visitor.uses)
            } else {
                for item in decl.members.members {
                    analyze(item.decl, in: &type, context: context, converter: decl.file.converter)
                }
                analyzeStoredInitializers(decl, in: &type, context: context)
            }
            types[decl.typeName] = type
        }

        // A private method stored as a callback runs on its own, like an `@objc` action.
        for (name, type) in types {
            let handlers = Set(type.members.flatMap(\.handlers))
            for index in type.members.indices where handlers.contains(type.members[index].key) {
                types[name]?.members[index].isDocumented = true
            }
        }

        var facts = Facts(types: types.values.sorted { $0.name < $1.name })
        facts.resolve()
        return facts
    }

    private func parseFiles() throws -> [ParsedFile] {
        let rootPath = sourcesRoot.resolvingSymlinksInPath().path + "/"
        let enumerator = FileManager.default.enumerator(at: sourcesRoot, includingPropertiesForKeys: nil)
        var files: [ParsedFile] = []
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let path = url.resolvingSymlinksInPath().path
            guard path.hasPrefix(rootPath) else { continue }
            let relative = String(path.dropFirst(rootPath.count))
            let module = relative.split(separator: "/").first.map(String.init) ?? ""
            let source = try String(contentsOf: url, encoding: .utf8)
            let tree = Parser.parse(source: source)
            files.append(ParsedFile(
                path: "Sources/PastyCore/" + relative, module: module, tree: tree,
                converter: SourceLocationConverter(fileName: relative, tree: tree)
            ))
        }
        return files.sorted { $0.path < $1.path }
    }

    // MARK: - Pass 1

    private func collectDeclaration(_ decl: DeclSyntax, into type: inout TypeFacts, file: ParsedFile) {
        let line = decl.startLocation(converter: file.converter).line
        if let fn = decl.as(FunctionDeclSyntax.self) {
            let params = fn.signature.parameterClause.parameters
            let labels = params.map { $0.firstName.text }
            add(Member(
                key: Self.key(fn.name.text, labels), name: fn.name.text, kind: .function,
                isStatic: fn.modifiers.hasStatic, line: line,
                isDocumented: Self.isDocumented(fn.modifiers, fn.attributes), labels: labels,
                optional: params.map { $0.defaultValue != nil },
                returnType: fn.signature.returnClause.flatMap { TypeIndex.clean($0.type.trimmedDescription) }
            ), to: &type)
        } else if let initDecl = decl.as(InitializerDeclSyntax.self) {
            let params = initDecl.signature.parameterClause.parameters
            let labels = params.map { $0.firstName.text }
            add(Member(
                key: Self.key("init", labels), name: "init", kind: .initializer, isStatic: false, line: line,
                isDocumented: Self.isDocumented(initDecl.modifiers, initDecl.attributes), labels: labels,
                optional: params.map { $0.defaultValue != nil }
            ), to: &type)
        } else if decl.is(DeinitializerDeclSyntax.self) {
            // Runs when the object is released — an entry point the system calls.
            add(Member(key: "deinit", name: "deinit", kind: .initializer, isStatic: false, line: line,
                       isDocumented: true, labels: []), to: &type)
        } else if let variable = decl.as(VariableDeclSyntax.self) {
            for binding in variable.bindings {
                guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else { continue }
                if Self.isComputed(binding) {
                    add(Member(
                        key: name, name: name, kind: .property, isStatic: variable.modifiers.hasStatic, line: line,
                        isDocumented: Self.isDocumented(variable.modifiers, variable.attributes), labels: [],
                        returnType: binding.typeAnnotation.flatMap { TypeIndex.clean($0.type.trimmedDescription) }
                    ), to: &type)
                } else {
                    if let typeName = Self.typeName(of: binding) { type.storedProperties[name] = typeName }
                    if !variable.modifiers.isPrivate { type.publicStoredProperties.insert(name) }
                }
            }
        }
    }

    /// Overloads with the same labels (e.g. `hash(_:)` for String and Data) share one entry.
    private func add(_ member: Member, to type: inout TypeFacts) {
        if let index = type.members.firstIndex(where: { $0.key == member.key }) {
            if member.isDocumented && !type.members[index].isDocumented {
                type.members[index] = member
            }
            return
        }
        type.members.append(member)
    }

    static func key(_ name: String, _ labels: [String]) -> String {
        name + "(" + labels.map { $0 + ":" }.joined() + ")"
    }

    private static func isDocumented(_ modifiers: DeclModifierListSyntax, _ attributes: AttributeListSyntax) -> Bool {
        if !modifiers.isPrivate { return true }
        if modifiers.contains(where: { $0.name.text == "override" }) { return true }
        return attributes.contains { $0.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "objc" }
    }

    private static func isComputed(_ binding: PatternBindingSyntax) -> Bool {
        guard let accessors = binding.accessorBlock else { return false }
        if case .accessors(let list) = accessors.accessors {
            // `willSet`/`didSet` observe a stored property.
            return !list.contains { ["willSet", "didSet"].contains($0.accessorSpecifier.text) }
        }
        return true
    }

    private static func typeName(of binding: PatternBindingSyntax) -> String? {
        if let annotated = binding.typeAnnotation?.type {
            return TypeIndex.clean(annotated.trimmedDescription)
        }
        if let call = binding.initializer?.value.as(FunctionCallExprSyntax.self),
           let callee = call.calledExpression.as(DeclReferenceExprSyntax.self) {
            return callee.baseName.text
        }
        return nil
    }

    // MARK: - Pass 2

    private func analyze(_ decl: DeclSyntax, in type: inout TypeFacts, context: TypeIndex, converter: SourceLocationConverter) {
        let key: String
        let body: Syntax?
        var locals: [String: String] = [:]

        if let fn = decl.as(FunctionDeclSyntax.self) {
            key = Self.key(fn.name.text, fn.signature.parameterClause.parameters.map { $0.firstName.text })
            body = fn.body.map(Syntax.init)
            locals = Self.parameters(fn.signature.parameterClause.parameters)
        } else if let initDecl = decl.as(InitializerDeclSyntax.self) {
            key = Self.key("init", initDecl.signature.parameterClause.parameters.map { $0.firstName.text })
            body = initDecl.body.map(Syntax.init)
            locals = Self.parameters(initDecl.signature.parameterClause.parameters)
        } else if let deinitDecl = decl.as(DeinitializerDeclSyntax.self) {
            key = "deinit"
            body = deinitDecl.body.map(Syntax.init)
        } else if let variable = decl.as(VariableDeclSyntax.self),
                  let binding = variable.bindings.first(where: Self.isComputed),
                  let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text {
            key = name
            body = binding.accessorBlock.map(Syntax.init)
        } else {
            return
        }
        guard let body, let index = type.members.firstIndex(where: { $0.key == key }) else { return }

        let visitor = BodyVisitor(context: context, typeName: type.name, locals: locals, converter: converter)
        visitor.walk(body)
        var member = type.members[index]
        member.directEffects += visitor.effects
        for (ref, offset) in visitor.localRefs where ref != key {
            if member.localRefOffsets[ref] == nil { member.localRefs.append(ref) }
            member.localRefOffsets[ref] = min(member.localRefOffsets[ref] ?? .max, offset)
        }
        member.uses = Array(Set(member.uses).union(visitor.uses)).sorted()
        member.handlers = Array(Set(member.handlers).union(visitor.handlerRefs)).sorted()
        type.members[index] = member
    }

    /// `private let preview = ImagePreview()` runs when the object is created, so its effects
    /// and uses belong to the initializers (or to the implicit `init()` if none is declared).
    private func analyzeStoredInitializers(_ decl: Decl, in type: inout TypeFacts, context: TypeIndex) {
        let visitor = BodyVisitor(context: context, typeName: type.name, locals: [:], converter: decl.file.converter)
        for item in decl.members.members {
            guard let variable = item.decl.as(VariableDeclSyntax.self), !variable.modifiers.hasStatic else { continue }
            for binding in variable.bindings where !Self.isComputed(binding) {
                if let value = binding.initializer?.value { visitor.walk(value) }
            }
        }
        guard !visitor.effects.isEmpty || !visitor.uses.isEmpty else { return }
        if !type.members.contains(where: { $0.kind == .initializer && $0.key != "deinit" }) {
            let line = decl.wholeDecl.startLocation(converter: decl.file.converter).line
            type.members.append(Member(key: "init()", name: "init", kind: .initializer, isStatic: false,
                                       line: line, isDocumented: true, labels: []))
        }
        for index in type.members.indices where type.members[index].kind == .initializer && type.members[index].key != "deinit" {
            type.members[index].directEffects += visitor.effects
            type.members[index].uses = Array(Set(type.members[index].uses).union(visitor.uses)).sorted()
            type.members[index].handlers = Array(Set(type.members[index].handlers).union(visitor.handlerRefs)).sorted()
            for (ref, offset) in visitor.localRefs where type.members[index].localRefOffsets[ref] == nil {
                type.members[index].localRefs.append(ref)
                type.members[index].localRefOffsets[ref] = offset
            }
        }
    }

    private static func parameters(_ list: FunctionParameterListSyntax) -> [String: String] {
        var result: [String: String] = [:]
        for param in list {
            let name = (param.secondName ?? param.firstName).text
            if let type = TypeIndex.clean(param.type.trimmedDescription) { result[name] = type }
        }
        return result
    }
}

// MARK: - Declarations

private final class DeclCollector: SyntaxVisitor {
    struct Found {
        let name: String
        let node: Syntax
        let memberBlock: MemberBlockSyntax
        let role: TypeFacts.Role
        let isPrivate: Bool
        let isExtension: Bool
        let isClass: Bool
    }

    var found: [Found] = []
    private var stack: [String] = []

    private func push(_ name: String, _ node: some SyntaxProtocol, _ block: MemberBlockSyntax,
                      role: TypeFacts.Role, isPrivate: Bool, isExtension: Bool = false, isClass: Bool = false) {
        let full = (stack + [name]).joined(separator: ".")
        found.append(Found(name: full, node: Syntax(node), memberBlock: block, role: role,
                           isPrivate: isPrivate, isExtension: isExtension, isClass: isClass))
        stack.append(name)
    }

    private static func inherits(_ clause: InheritanceClauseSyntax?, _ name: String) -> Bool {
        clause?.inheritedTypes.contains { $0.type.trimmedDescription == name } ?? false
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        push(node.name.text, node, node.memberBlock, role: .component, isPrivate: node.modifiers.isPrivate, isClass: true)
        return .visitChildren
    }
    override func visitPost(_ node: ClassDeclSyntax) { stack.removeLast() }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        push(node.name.text, node, node.memberBlock, role: .component, isPrivate: node.modifiers.isPrivate, isClass: true)
        return .visitChildren
    }
    override func visitPost(_ node: ActorDeclSyntax) { stack.removeLast() }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        let role: TypeFacts.Role = Self.inherits(node.inheritanceClause, "View") ? .view : .data
        push(node.name.text, node, node.memberBlock, role: role, isPrivate: node.modifiers.isPrivate)
        return .visitChildren
    }
    override func visitPost(_ node: StructDeclSyntax) { stack.removeLast() }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        let hasCases = node.memberBlock.members.contains { $0.decl.is(EnumCaseDeclSyntax.self) }
        push(node.name.text, node, node.memberBlock, role: hasCases ? .data : .component,
             isPrivate: node.modifiers.isPrivate)
        return .visitChildren
    }
    override func visitPost(_ node: EnumDeclSyntax) { stack.removeLast() }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        push(node.extendedType.trimmedDescription, node, node.memberBlock, role: .data,
             isPrivate: node.modifiers.isPrivate, isExtension: true)
        return .visitChildren
    }
    override func visitPost(_ node: ExtensionDeclSyntax) { stack.removeLast() }
}

extension DeclModifierListSyntax {
    /// `private(set)` only restricts writes; the declaration is still readable from outside.
    var isPrivate: Bool { contains { ["private", "fileprivate"].contains($0.name.text) && $0.detail == nil } }
    var hasStatic: Bool { contains { ["static", "class"].contains($0.name.text) } }
}

// MARK: - Type lookup

/// Answers "what type is this expression?" for the simple cases that matter here:
/// `self`, stored properties, parameters, locals and chains of them.
struct TypeIndex {
    let types: [String: TypeFacts]

    static func clean(_ raw: String) -> String? {
        var name = raw.replacingOccurrences(of: "@escaping", with: "").trimmingCharacters(in: .whitespaces)
        while name.hasSuffix("?") || name.hasSuffix("!") { name.removeLast() }
        guard !name.isEmpty, !name.contains(where: { "<[(-> ".contains($0) }) else { return nil }
        return name
    }

    func resolve(_ name: String, from scope: String) -> String? {
        // Nested types can be referred to by their short name inside their parent.
        var parts = scope.split(separator: ".").map(String.init)
        while !parts.isEmpty {
            let candidate = (parts + [name]).joined(separator: ".")
            if types[candidate] != nil { return candidate }
            parts.removeLast()
        }
        return types[name] != nil ? name : nil
    }

    func returnType(of type: String, name: String, from scope: String) -> String? {
        guard let raw = types[type]?.members.first(where: { $0.name == name && $0.returnType != nil })?.returnType else { return nil }
        return resolve(raw, from: scope) ?? resolve(raw, from: type)
    }

    func isComponent(_ name: String) -> Bool {
        guard let type = types[name] else { return false }
        return type.role == .component && !type.isPrivate
    }

    func memberKeys(_ type: String, name: String) -> [Member] {
        types[type]?.members.filter { $0.name == name } ?? []
    }

    /// Picks the overload whose labels match the call; falls back to all with that name.
    func match(_ type: String, name: String, labels: [String]?) -> [String] {
        let candidates = memberKeys(type, name: name)
        guard let labels else {
            return candidates.filter { $0.kind == .property || $0.labels.isEmpty }.map(\.key)
                .ifEmpty(candidates.map(\.key))
        }
        let fitting = candidates.filter { Self.accepts($0, labels) }
        return (fitting.isEmpty ? candidates : fitting).map(\.key)
    }

    /// Whether a call with these labels can bind to the member, skipping defaulted parameters.
    static let anyLabel = "*"

    static func accepts(_ member: Member, _ labels: [String]) -> Bool {
        var remaining = labels[...]
        for (index, label) in member.labels.enumerated() {
            if remaining.first == label || remaining.first == anyLabel {
                remaining = remaining.dropFirst()
            } else if !(member.optional.indices.contains(index) && member.optional[index]) {
                return false
            }
        }
        return remaining.isEmpty
    }
}

extension Array {
    func ifEmpty(_ other: [Element]) -> [Element] { isEmpty ? other : self }
}

// MARK: - Bodies

private final class BodyVisitor: SyntaxVisitor {
    let context: TypeIndex
    let typeName: String
    let converter: SourceLocationConverter
    var locals: [String: String]

    var effects: [EffectSite] = []
    var localRefs: [(String, Int)] = []
    /// Members of this type a stored closure will call later; they are entry points of their own.
    var handlerRefs: Set<String> = []
    var uses: Set<String> = []

    init(context: TypeIndex, typeName: String, locals: [String: String], converter: SourceLocationConverter) {
        self.context = context
        self.typeName = typeName
        self.locals = locals
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    // Locals: `let x = Foo()`, `let x: Foo`, `if let popup` (shorthand for a property).
    override func visit(_ node: PatternBindingSyntax) -> SyntaxVisitorContinueKind {
        if let name = node.pattern.as(IdentifierPatternSyntax.self)?.identifier.text {
            if let annotated = node.typeAnnotation?.type, let type = TypeIndex.clean(annotated.trimmedDescription) {
                locals[name] = context.resolve(type, from: typeName) ?? type
            } else if let value = node.initializer?.value, let type = typeOf(value) {
                locals[name] = type
            }
        }
        return .visitChildren
    }

    override func visit(_ node: OptionalBindingConditionSyntax) -> SyntaxVisitorContinueKind {
        if let name = node.pattern.as(IdentifierPatternSyntax.self)?.identifier.text {
            if let value = node.initializer?.value {
                if let type = typeOf(value) { locals[name] = type }
            } else if let type = context.types[typeName]?.storedProperties[name] {
                locals[name] = context.resolve(type, from: typeName) ?? type
            }
        }
        return .visitChildren
    }

    override func visit(_ node: AttributeSyntax) -> SyntaxVisitorContinueKind {
        let name = node.attributeName.trimmedDescription
        record(EffectRules.effects(kind: .attribute, name: name, labels: nil, receiver: nil), api: "@" + name, node: node)
        return .visitChildren
    }

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        let name = node.declName.baseName.text.replacingOccurrences(of: "$", with: "")
        let labels = callLabels(of: node)
        guard let base = node.base else { return .visitChildren } // `.foo` — an enum case or static constant
        let receiver = base.trimmedDescription

        if let baseType = typeOf(base) {
            if baseType == typeName {
                for key in context.match(typeName, name: name, labels: labels) { addLocalRef(key, node) }
            } else if context.isComponent(baseType) {
                recordUse(type: baseType, name: name, labels: labels)
            }
        }
        let display = labels.map { Extractor.key(name, $0.filter { $0 != TypeIndex.anyLabel }) } ?? name
        record(EffectRules.effects(kind: .member, name: name, labels: labels, receiver: receiver), api: display, node: node)
        return .visitChildren
    }

    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        // The `foo` in `x.foo` is handled by the member access.
        if let parent = node.parent?.as(MemberAccessExprSyntax.self), parent.declName.id == node.id { return .visitChildren }
        let name = node.baseName.text
        let labels = callLabels(of: node)

        if let labels {
            if let type = context.resolve(name, from: typeName), name.first?.isUppercase == true {
                if type != typeName, context.isComponent(type) { recordUse(type: type, name: "init", labels: labels) }
                record(EffectRules.effects(kind: .initializer, name: name, labels: labels, receiver: nil),
                       api: Extractor.key(name, labels), node: node)
                return .visitChildren
            }
            if !context.memberKeys(typeName, name: name).isEmpty, locals[name] == nil {
                for key in context.match(typeName, name: name, labels: labels) { addLocalRef(key, node) }
                return .visitChildren
            }
            // C functions are often capitalized (`AXIsProcessTrusted`), so try both kinds.
            var found = EffectRules.effects(kind: .function, name: name, labels: labels, receiver: nil)
            // A method inherited from a superclass, called on implicit `self` (`orderOut(nil)` in a panel).
            found += EffectRules.effects(kind: .member, name: name, labels: labels, receiver: nil)
            if name.first?.isUppercase == true {
                found += EffectRules.effects(kind: .initializer, name: name, labels: labels, receiver: nil)
            }
            record(found, api: Extractor.key(name, labels), node: node)
        } else if locals[name] == nil,
                  context.memberKeys(typeName, name: name).contains(where: { $0.kind == .property }) {
            addLocalRef(name, node)
        }
        return .visitChildren
    }

    // MARK: Helpers

    /// Closures passed to these run before the call returns; any other closure is stored
    /// and called later (a timer, a callback, an observer).
    static let immediateClosureCallees: Set<String> = [
        "map", "compactMap", "flatMap", "filter", "forEach", "first", "firstIndex", "last", "lastIndex",
        "contains", "allSatisfy", "sorted", "sort", "removeAll", "reduce", "min", "max", "drop", "prefix",
        "split", "withUnsafeBytes", "withUnsafeMutableBytes", "autoreleasepool", "assumeIsolated",
    ]

    private func addLocalRef(_ key: String, _ node: some SyntaxProtocol) {
        if insideStoredClosure(node) {
            handlerRefs.insert(key)
        } else {
            localRefs.append((key, offset(node)))
        }
    }

    private func insideStoredClosure(_ node: some SyntaxProtocol) -> Bool {
        var current = node.parent
        while let node = current {
            if node.is(FunctionDeclSyntax.self) || node.is(InitializerDeclSyntax.self) || node.is(AccessorBlockSyntax.self) {
                return false
            }
            if let closure = node.as(ClosureExprSyntax.self), !Self.runsImmediately(closure) { return true }
            current = node.parent
        }
        return false
    }

    private static func runsImmediately(_ closure: ClosureExprSyntax) -> Bool {
        var parent = closure.parent
        if parent?.is(LabeledExprSyntax.self) == true { parent = parent?.parent?.parent } // argument -> list -> call
        guard let call = parent?.as(FunctionCallExprSyntax.self) else { return false }
        if call.calledExpression.id == closure.id { return true } // `{ ... }()`
        let callee = call.calledExpression.as(MemberAccessExprSyntax.self)?.declName.baseName.text
            ?? call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text
        return callee.map(immediateClosureCallees.contains) ?? false
    }

    /// Argument labels if `node` is the callee of a call, else nil.
    private func callLabels(of node: some SyntaxProtocol) -> [String]? {
        guard let call = node.parent?.as(FunctionCallExprSyntax.self), call.calledExpression.id == node.id else { return nil }
        // A trailing closure can bind to any remaining parameter, whatever its label.
        return call.arguments.map { $0.label?.text ?? "_" } + (call.trailingClosure == nil ? [] : [TypeIndex.anyLabel])
    }

    private func typeOf(_ expr: ExprSyntax) -> String? {
        if let ref = expr.as(DeclReferenceExprSyntax.self) {
            let name = ref.baseName.text
            if name == "self" || name == "Self" { return typeName }
            if let local = locals[name] { return context.resolve(local, from: typeName) ?? local }
            if let stored = context.types[typeName]?.storedProperties[name] {
                return context.resolve(stored, from: typeName) ?? stored
            }
            if name.first?.isUppercase == true { return context.resolve(name, from: typeName) }
            return nil
        }
        if let chain = expr.as(OptionalChainingExprSyntax.self) { return typeOf(chain.expression) }
        if let unwrap = expr.as(ForceUnwrapExprSyntax.self) { return typeOf(unwrap.expression) }
        if let member = expr.as(MemberAccessExprSyntax.self), let base = member.base, let baseType = typeOf(base) {
            let name = member.declName.baseName.text
            if let stored = context.types[baseType]?.storedProperties[name] {
                return context.resolve(stored, from: baseType) ?? stored
            }
            return context.resolve(name, from: baseType).flatMap { context.types[$0] != nil ? $0 : nil }
        }
        if let call = expr.as(FunctionCallExprSyntax.self) {
            if let callee = call.calledExpression.as(DeclReferenceExprSyntax.self) {
                let name = callee.baseName.text
                if name.first?.isUppercase == true { return context.resolve(name, from: typeName) }
                return context.returnType(of: typeName, name: name, from: typeName) // `activePopup().toggle()`
            }
            if let member = call.calledExpression.as(MemberAccessExprSyntax.self), let base = member.base,
               let baseType = typeOf(base) {
                return context.returnType(of: baseType, name: member.declName.baseName.text, from: baseType)
            }
        }
        if let member = expr.as(MemberAccessExprSyntax.self), let base = member.base, let baseType = typeOf(base) {
            return context.returnType(of: baseType, name: member.declName.baseName.text, from: baseType)
        }
        return nil
    }

    private func recordUse(type: String, name: String, labels: [String]?) {
        if name == "init" {
            let keys = context.match(type, name: "init", labels: labels ?? [])
            if keys.isEmpty {
                uses.insert(type + "." + Extractor.key("init", (labels ?? []).filter { $0 != TypeIndex.anyLabel }))
            } else {
                keys.forEach { uses.insert(type + "." + $0) }
            }
            return
        }
        let keys = context.match(type, name: name, labels: labels)
        if !keys.isEmpty {
            keys.forEach { uses.insert(type + "." + $0) }
        } else if context.types[type]?.publicStoredProperties.contains(name) == true {
            uses.insert(type + "." + name)
        }
    }

    private func record(_ found: [Effect], api: String, node: some SyntaxProtocol) {
        guard !found.isEmpty else { return }
        let line = node.startLocation(converter: converter).line
        let handling = errorHandling(of: node)
        for effect in found {
            effects.append(EffectSite(effect: effect, api: api, line: line, errorHandling: handling, offset: offset(node)))
        }
    }

    private func offset(_ node: some SyntaxProtocol) -> Int { node.positionAfterSkippingLeadingTrivia.utf8Offset }

    private func errorHandling(of node: some SyntaxProtocol) -> ErrorHandling {
        var current: Syntax? = Syntax(node)
        var tried: TryExprSyntax?
        while let node = current {
            if tried == nil, let tryExpr = node.as(TryExprSyntax.self) {
                if tryExpr.questionOrExclamationMark?.text == "?" { return .ignored }
                tried = tryExpr
            }
            if tried != nil, let doStmt = node.as(DoStmtSyntax.self), !doStmt.catchClauses.isEmpty { return .caught }
            if node.is(ClosureExprSyntax.self) || node.is(FunctionDeclSyntax.self) || node.is(AccessorBlockSyntax.self) {
                break
            }
            if tried == nil, node.is(CodeBlockItemSyntax.self) { break }
            current = node.parent
        }
        return tried == nil ? .none : .thrown
    }
}
