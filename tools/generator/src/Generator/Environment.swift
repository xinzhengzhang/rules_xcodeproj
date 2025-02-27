import PathKit
import XcodeProj

/// Provides `Generator`'s dependencies.
///
/// The main purpose of `Environment` is to enable dependency injection,
/// allowing for different implementations to be used in tests.
struct Environment {
    let createProject: (
        _ buildMode: BuildMode,
        _ project: Project,
        _ projectRootDirectory: Path,
        _ filePathResolver: FilePathResolver
    ) -> PBXProj

    let processTargetMerges: (
        _ targets: inout [TargetID: Target],
        _ targetMerges: [TargetID: Set<TargetID>]
    ) throws -> Void

    let consolidateTargets: (
        _ targets: [TargetID: Target],
        _ logger: Logger
    ) throws -> ConsolidatedTargets

    let createFilesAndGroups: (
        _ pbxProj: PBXProj,
        _ buildMode: BuildMode,
        _ targets: [TargetID: Target],
        _ extraFiles: Set<FilePath>,
        _ xccurrentversions: [XCCurrentVersion],
        _ filePathResolver: FilePathResolver,
        _ logger: Logger
    ) throws -> (
        files: [FilePath: File],
        rootElements: [PBXFileElement]
    )

    let createProducts: (
        _ pbxProj: PBXProj,
        _ consolidatedTargets: ConsolidatedTargets
    ) -> (Products, PBXGroup)

    let populateMainGroup: (
        _ mainGroup: PBXGroup,
        _ pbxProj: PBXProj,
        _ rootElements: [PBXFileElement],
        _ productsGroup: PBXGroup
    ) -> Void

    let disambiguateTargets: (
        _ consolidatedTargets: ConsolidatedTargets
    ) -> DisambiguatedTargets

    let addBazelDependenciesTarget: (
        _ pbxProj: PBXProj,
        _ buildMode: BuildMode,
        _ files: [FilePath: File],
        _ filePathResolver: FilePathResolver,
        _ xcodeprojBazelLabel: String,
        _ xcodeprojConfiguration: String,
        _ consolidatedTargets: ConsolidatedTargets
    ) throws -> PBXAggregateTarget?

    let addTargets: (
        _ pbxProj: PBXProj,
        _ disambiguatedTargets: DisambiguatedTargets,
        _ buildMode: BuildMode,
        _ products: Products,
        _ files: [FilePath: File],
        _ filePathResolver: FilePathResolver,
        _ bazelDependenciesTarget: PBXAggregateTarget?
    ) throws -> [ConsolidatedTarget.Key: PBXTarget]

    let setTargetConfigurations: (
        _ pbxProj: PBXProj,
        _ disambiguatedTargets: DisambiguatedTargets,
        _ buildMode: BuildMode,
        _ pbxTargets: [ConsolidatedTarget.Key: PBXTarget],
        _ filePathResolver: FilePathResolver
    ) throws -> Void

    let setTargetDependencies: (
        _ disambiguatedTargets: DisambiguatedTargets,
        _ pbxTargets: [ConsolidatedTarget.Key: PBXTarget]
    ) throws -> Void

    let createXCSchemes: (
        _ buildMode: BuildMode,
        _ filePathResolver: FilePathResolver,
        _ pbxTargets: [ConsolidatedTarget.Key: PBXTarget]
    ) throws -> [XCScheme]

    let createXCSharedData: (_ schemes: [XCScheme]) -> XCSharedData

    let createXcodeProj: (
        _ pbxProj: PBXProj,
        _ sharedData: XCSharedData?
    ) -> XcodeProj

    let writeXcodeProj: (
        _ xcodeProj: XcodeProj,
        _ buildMode: BuildMode,
        _ files: [FilePath: File],
        _ internalDirectoryName: String,
        _ bazelIntegrationDirectory: Path,
        _ outputPath: Path
    ) throws -> Void
}
