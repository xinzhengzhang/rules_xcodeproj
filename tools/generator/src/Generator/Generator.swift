import PathKit
import XcodeProj

/// A class that generates and writes to disk an Xcode project.
///
/// The `Generator` class is stateless. It can be used to generate multiple
/// projects. The `generate()` method is passed all the inputs needed to
/// generate a project.
class Generator {
    static let defaultEnvironment = Environment(
        createProject: Generator.createProject,
        processTargetMerges: Generator.processTargetMerges,
        consolidateTargets: Generator.consolidateTargets,
        createFilesAndGroups: Generator.createFilesAndGroups,
        createProducts: Generator.createProducts,
        populateMainGroup: populateMainGroup,
        disambiguateTargets: Generator.disambiguateTargets,
        addBazelDependenciesTarget: Generator.addBazelDependenciesTarget,
        addTargets: Generator.addTargets,
        setTargetConfigurations: Generator.setTargetConfigurations,
        setTargetDependencies: Generator.setTargetDependencies,
        createXCSchemes: Generator.createXCSchemes,
        createXCSharedData: Generator.createXCSharedData,
        createXcodeProj: Generator.createXcodeProj,
        writeXcodeProj: Generator.writeXcodeProj
    )

    let environment: Environment
    let logger: Logger

    init(
        environment: Environment = Generator.defaultEnvironment,
        logger: Logger
    ) {
        self.logger = logger
        self.environment = environment
    }

    /// Generates an Xcode project for a given `Project`.
    func generate(
        buildMode: BuildMode,
        project: Project,
        xccurrentversions: [XCCurrentVersion],
        projectRootDirectory: Path,
        internalDirectoryName: String,
        bazelIntegrationDirectory: Path,
        workspaceOutputPath: Path,
        outputPath: Path
    ) throws {
        let filePathResolver = FilePathResolver(
            internalDirectoryName: internalDirectoryName,
            workspaceOutputPath: workspaceOutputPath
        )

        let pbxProj = environment.createProject(
            buildMode,
            project,
            projectRootDirectory,
            filePathResolver
        )
        guard let pbxProject = pbxProj.rootObject else {
            throw PreconditionError(message: """
`rootObject` not set on `pbxProj`
""")
        }
        let mainGroup: PBXGroup = pbxProject.mainGroup

        var targets = project.targets
        try environment.processTargetMerges(&targets, project.targetMerges)

        for (src, destinations) in project.invalidTargetMerges {
            guard let srcTarget = targets[src] else {
                throw PreconditionError(
                    message: """
Source target "\(src)" not found in `targets`
""")
            }
            for destination in destinations {
                guard let destTarget = targets[destination] else {
                    throw PreconditionError(message: """
Destination target "\(destination)" not found in `targets`
""")
                }
                logger.logWarning("""
Was unable to merge "\(srcTarget.label) \
(\(srcTarget.configuration))" into \
"\(destTarget.label) \
(\(destTarget.configuration))"
""")
            }
        }

        let consolidatedTargets = try environment.consolidateTargets(
            targets,
            logger
        )

        let (files, rootElements) = try environment.createFilesAndGroups(
            pbxProj,
            buildMode,
            targets,
            project.extraFiles,
            xccurrentversions,
            filePathResolver,
            logger
        )
        let (products, productsGroup) = environment.createProducts(
            pbxProj,
            consolidatedTargets
        )
        environment.populateMainGroup(
            mainGroup,
            pbxProj,
            rootElements,
            productsGroup
        )

        let disambiguatedTargets = environment.disambiguateTargets(
            consolidatedTargets
        )
        let bazelDependencies = try environment.addBazelDependenciesTarget(
            pbxProj,
            buildMode,
            files,
            filePathResolver,
            project.label,
            project.configuration,
            consolidatedTargets
        )
        let pbxTargets = try environment.addTargets(
            pbxProj,
            disambiguatedTargets,
            buildMode,
            products,
            files,
            filePathResolver,
            bazelDependencies
        )
        try environment.setTargetConfigurations(
            pbxProj,
            disambiguatedTargets,
            buildMode,
            pbxTargets,
            filePathResolver
        )
        try environment.setTargetDependencies(
            disambiguatedTargets,
            pbxTargets
        )

        let schemes = try environment.createXCSchemes(
            buildMode,
            filePathResolver,
            pbxTargets
        )
        let sharedData = environment.createXCSharedData(schemes)

        let xcodeProj = environment.createXcodeProj(pbxProj, sharedData)
        try environment.writeXcodeProj(
            xcodeProj,
            buildMode,
            files,
            internalDirectoryName,
            bazelIntegrationDirectory,
            outputPath
        )
    }
}

/// When a potential merge wasn't valid, then the ids of the targets involved
/// are returned in this `struct`.
struct InvalidMerge: Equatable {
    let source: TargetID
    let destinations: Set<TargetID>
}
