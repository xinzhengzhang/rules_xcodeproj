import XcodeProj

private extension PBXFileElement {
    var sortOrder: Int {
        switch self {
        case is PBXVariantGroup:
            // Localized containers should be treated as files
            return 0
        case is XCVersionGroup:
            // Code Data containers should be treated as files
            return 0
        case is PBXGroup:
            return -1
        default:
            if let reference = self as? PBXFileReference {
                // Folders should be treated as groups
                return reference.lastKnownFileType == "folder" ? -1 : 0
            } else {
                return 0
            }
        }
    }

    var namePathSortString: String {
        "\(name ?? path ?? "")\t\(name ?? "")\t\(path ?? "")"
    }
}

extension Sequence {
    static func sortByLocalizedStandard(
        _ keyPath: KeyPath<Element, String>
    ) -> (
        _ lhs: Element,
        _ rhs: Element
    ) -> Bool {
        return { lhs, rhs in
            let l = lhs[keyPath: keyPath]
            let r = rhs[keyPath: keyPath]
            return l.localizedStandardCompare(r) == .orderedAscending
        }
    }

    func sortedLocalizedStandard(
        _ keyPath: KeyPath<Element, String>
    ) -> [Element] {
        return self.sorted(by: Self.sortByLocalizedStandard(keyPath))
    }
}

extension Sequence where Element == String {
    func sortedLocalizedStandard() -> [Element] {
        return sortedLocalizedStandard(\.self)
    }
}

extension Sequence where Element: PBXFileElement {
    func sortedLocalizedStandard() -> [Element] {
        return sortedLocalizedStandard(\.namePathSortString)
    }
}

extension Sequence where Element == PBXBuildFile {
    func sortedLocalizedStandard() -> [Element] {
        return sortedLocalizedStandard(\.file!.namePathSortString)
    }
}

extension Array where Element: PBXFileElement {
    mutating func sortGroupedLocalizedStandard() {
        let fileSort = Self.sortByLocalizedStandard(\.namePathSortString)
        self.sort { lhs, rhs in
            let lhsSortOrder = lhs.sortOrder
            let rhsSortOrder = rhs.sortOrder
            if lhsSortOrder != rhsSortOrder {
                // Groups and folders before files
                return lhsSortOrder < rhsSortOrder
            } else {
                // Files alphabetically
                return fileSort(lhs, rhs)
            }
        }
        for element in self {
            if let group = element as? PBXGroup {
                group.children.sortGroupedLocalizedStandard()
            }
        }
    }
}

private struct PBXFileReferenceByTargetKey {
    let targetKey: ConsolidatedTarget.Key
    let file: PBXFileReference

    init(_ element: (key: ConsolidatedTarget.Key, value: PBXFileReference)) {
        targetKey = element.key
        file = element.value
    }

    var sortString: String {
        return "\(file.namePathSortString)\t\(targetKey)"
    }
}

extension Dictionary
where Key == ConsolidatedTarget.Key, Value: PBXFileReference {
    func sortedLocalizedStandard() -> [PBXFileReference] {
        let sort = [PBXFileReferenceByTargetKey]
            .sortByLocalizedStandard(\.sortString)
        return self
            .map(PBXFileReferenceByTargetKey.init)
            .sorted(by: sort)
            .map(\.file)
    }
}
