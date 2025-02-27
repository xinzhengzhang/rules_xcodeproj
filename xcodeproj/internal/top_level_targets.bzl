""" Functions for processing top level targets """

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("@bazel_skylib//lib:paths.bzl", "paths")
load("@build_bazel_rules_swift//swift:swift.bzl", "SwiftInfo")
load(":build_settings.bzl", "get_targeted_device_family")
load(":collections.bzl", "set_if_true")
load(":configuration.bzl", "get_configuration")
load(":files.bzl", "file_path", "join_paths_ignoring_empty")
load(":info_plists.bzl", "info_plists")
load(":input_files.bzl", "input_files")
load(":linker_input_files.bzl", "linker_input_files")
load(":opts.bzl", "process_opts")
load(":output_files.bzl", "output_files")
load(":platform.bzl", "platform_info")
load(":providers.bzl", "InputFileAttributesInfo", "XcodeProjInfo")
load(":processed_target.bzl", "processed_target", "xcode_target")
load(":product.bzl", "process_product")
load(":provisioning_profiles.bzl", "provisioning_profiles")
load(":search_paths.bzl", "process_search_paths")
load(":target_id.bzl", "get_id")
load(
    ":target_properties.bzl",
    "process_defines",
    "process_dependencies",
    "process_modulemaps",
    "process_sdk_links",
    "process_swiftmodules",
    "should_bundle_resources",
    "should_include_outputs",
)

def get_tree_artifact_enabled(*, ctx, bundle_info):
    """Returns whether tree artifacts are enabled.

    Args:
        ctx: The context
        bundle_info: An instance of `BundleInfo`

    Returns:
        A boolean representing if tree artifacts are enabled
    """
    if not bundle_info:
        return False

    tree_artifact_enabled = (
        ctx.var.get("apple.experimental.tree_artifact_outputs", "")
            .lower() in
        ("true", "yes", "1")
    )

    if not ctx.attr._archived_bundles_allowed[BuildSettingInfo].value:
        if not tree_artifact_enabled:
            fail("""\
Not using `--define=apple.experimental.tree_artifact_outputs=1` is slow. If \
you can't set that flag, you can set `archived_bundles_allowed = True` on the \
`xcodeproj` rule to have it unarchive bundles when installing them.
""")

    return tree_artifact_enabled

def process_top_level_properties(
        *,
        target_name,
        target_files,
        bundle_info,
        tree_artifact_enabled,
        build_settings):
    """Processes properties for a top level target.

    Args:
        target_name: Name of the target.
        target_files: The `files` attribute of the target.
        bundle_info: The `AppleBundleInfo` provider for the target.
        tree_artifact_enabled: A `bool` controlling if tree artifacts are
            enabled.
        build_settings: A mutable `dict` of build settings.

    Returns:
        A `struct` of information about the top level target.
    """
    if bundle_info:
        product_name = bundle_info.bundle_name
        product_type = bundle_info.product_type
        minimum_deployment_version = bundle_info.minimum_deployment_os_version

        if tree_artifact_enabled:
            bundle_file_path = file_path(bundle_info.archive)
        else:
            bundle_extension = bundle_info.bundle_extension
            bundle = "{}{}".format(bundle_info.bundle_name, bundle_extension)
            if bundle_extension == ".app":
                bundle_path = paths.join(
                    bundle_info.archive_root,
                    "Payload",
                    bundle,
                )
            else:
                bundle_path = paths.join(bundle_info.archive_root, bundle)
            bundle_file_path = file_path(
                bundle_info.archive,
                bundle_path,
            )

        build_settings["PRODUCT_BUNDLE_IDENTIFIER"] = bundle_info.bundle_id
    else:
        product_name = target_name
        minimum_deployment_version = None

        xctest = None
        for file in target_files:
            if ".xctest/" in file.path:
                xctest = file
                break
        if xctest:
            # This is something like `swift_test`: it creates an xctest bundle
            product_type = "com.apple.product-type.bundle.unit-test"

            # "some/test.xctest/binary" -> "some/test.xctest"
            xctest_path = xctest.path
            bundle_file_path = file_path(
                xctest,
                path = xctest_path[:-(len(xctest_path.split(".xctest/")[1]) + 1)],
            )
        else:
            product_type = "com.apple.product-type.tool"
            bundle_file_path = None

    build_settings["PRODUCT_MODULE_NAME"] = "_{}_Stub".format(product_name)

    return struct(
        bundle_file_path = bundle_file_path,
        minimum_deployment_os_version = minimum_deployment_version,
        product_name = product_name,
        product_type = product_type,
    )

def _process_test_host(test_host):
    if test_host:
        return test_host[XcodeProjInfo]
    return None

def process_top_level_target(*, ctx, target, bundle_info, transitive_infos):
    """Gathers information about a top-level target.

    Args:
        ctx: The aspect context.
        target: The `Target` to process.
        bundle_info: The `AppleBundleInfo` provider for `target`, or `None`.
        transitive_infos: A `list` of `depset`s of `XcodeProjInfo`s from the
            transitive dependencies of `target`.

    Returns:
        The value returned from `processed_target`.
    """
    attrs_info = target[InputFileAttributesInfo]

    configuration = get_configuration(ctx)
    label = target.label
    id = get_id(label = label, configuration = configuration)
    dependencies = process_dependencies(
        attrs_info = attrs_info,
        transitive_infos = transitive_infos,
    )
    test_host = getattr(ctx.rule.attr, "test_host", None)
    test_host_target_info = _process_test_host(test_host)

    deps = getattr(ctx.rule.attr, "deps", [])
    avoid_deps = [test_host] if test_host else []

    additional_files = []
    build_settings = {}
    is_bundle = bundle_info != None
    is_swift = SwiftInfo in target
    swift_info = target[SwiftInfo] if is_swift else None

    modulemaps = process_modulemaps(swift_info = swift_info)
    additional_files.extend(modulemaps.files)

    info_plist = None
    info_plist_file = info_plists.get_file(target)
    if info_plist_file:
        info_plist = file_path(info_plist_file)
        additional_files.append(info_plist_file)

    provisioning_profiles.process_attr(
        ctx = ctx,
        attrs_info = attrs_info,
        build_settings = build_settings,
    )

    bundle_resources = should_bundle_resources(ctx = ctx)

    # The common case is to have a `bundle_info`, so this check prevents
    # expanding the `depset` unless needed. Yes, this uses knowledge of what
    # `process_top_level_properties` and `output_files.collect` does internally.
    target_files = [] if bundle_info else target.files.to_list()

    tree_artifact_enabled = get_tree_artifact_enabled(
        ctx = ctx,
        bundle_info = bundle_info,
    )
    props = process_top_level_properties(
        target_name = ctx.rule.attr.name,
        target_files = target_files,
        bundle_info = bundle_info,
        tree_artifact_enabled = tree_artifact_enabled,
        build_settings = build_settings,
    )
    platform = platform_info.collect(
        ctx = ctx,
        minimum_deployment_os_version = props.minimum_deployment_os_version,
    )

    inputs = input_files.collect(
        ctx = ctx,
        target = target,
        platform = platform,
        is_bundle = is_bundle,
        bundle_resources = bundle_resources,
        attrs_info = attrs_info,
        additional_files = additional_files,
        transitive_infos = transitive_infos,
        avoid_deps = avoid_deps,
    )
    outputs = output_files.collect(
        target_files = target_files,
        bundle_info = bundle_info,
        default_info = target[DefaultInfo],
        swift_info = swift_info,
        id = id,
        transitive_infos = transitive_infos,
        should_produce_dto = should_include_outputs(ctx = ctx),
    )

    package_bin_dir = join_paths_ignoring_empty(
        ctx.bin_dir.path,
        label.workspace_root,
        label.package,
    )
    opts_search_paths = process_opts(
        ctx = ctx,
        target = target,
        package_bin_dir = package_bin_dir,
        build_settings = build_settings,
    )

    if (test_host_target_info and
        props.product_type == "com.apple.product-type.bundle.unit-test"):
        avoid_linker_inputs = test_host_target_info.linker_inputs
    else:
        avoid_linker_inputs = None

    linker_inputs = linker_input_files.collect_for_top_level(
        deps = deps,
        avoid_linker_inputs = avoid_linker_inputs,
    )
    xcode_library_targets = linker_inputs.xcode_library_targets

    if len(xcode_library_targets) == 1 and not inputs.srcs:
        mergeable_target = xcode_library_targets[0]
        mergeable_label = mergeable_target.label
        potential_target_merges = [struct(
            src = struct(
                id = mergeable_target.id,
                product_path = mergeable_target.product_path,
            ),
            dest = id,
        )]
    elif bundle_info and len(xcode_library_targets) > 1:
        fail("""\
The xcodeproj rule requires {} rules to have a single library dep. {} has {}.\
""".format(ctx.rule.kind, label, len(xcode_library_targets)))
    else:
        potential_target_merges = None
        mergeable_label = None

    static_libraries = linker_input_files.get_static_libraries(linker_inputs)
    required_links = [
        library
        for library in static_libraries
        if mergeable_label and library.owner != mergeable_label
    ]

    build_settings["OTHER_LDFLAGS"] = ["-ObjC"] + build_settings.get(
        "OTHER_LDFLAGS",
        [],
    )

    set_if_true(
        build_settings,
        "TARGETED_DEVICE_FAMILY",
        get_targeted_device_family(getattr(ctx.rule.attr, "families", [])),
    )

    product = process_product(
        target = target,
        product_name = props.product_name,
        product_type = props.product_type,
        bundle_file_path = props.bundle_file_path,
        linker_inputs = linker_inputs,
        build_settings = build_settings,
    )

    cc_info = target[CcInfo] if CcInfo in target else None
    objc = target[apple_common.Objc] if apple_common.Objc in target else None
    process_defines(
        cc_info = cc_info,
        build_settings = build_settings,
    )
    process_sdk_links(
        objc = objc,
        build_settings = build_settings,
    )
    search_paths = process_search_paths(
        cc_info = cc_info,
        objc = objc,
        opts_search_paths = opts_search_paths,
    )

    return processed_target(
        attrs_info = attrs_info,
        dependencies = dependencies,
        inputs = inputs,
        linker_inputs = linker_inputs,
        outputs = outputs,
        potential_target_merges = potential_target_merges,
        required_links = required_links,
        search_paths = search_paths,
        target = struct(
            id = id,
            label = label,
            is_bundle = is_bundle,
            product_path = product.path,
        ),
        xcode_target = xcode_target(
            id = id,
            name = ctx.rule.attr.name,
            label = label,
            configuration = configuration,
            package_bin_dir = package_bin_dir,
            platform = platform,
            product = product,
            is_swift = is_swift,
            test_host = (
                test_host_target_info.target.id if test_host_target_info else None
            ),
            build_settings = build_settings,
            search_paths = search_paths,
            modulemaps = modulemaps,
            swiftmodules = process_swiftmodules(swift_info = swift_info),
            inputs = inputs,
            linker_inputs = linker_inputs,
            info_plist = info_plist,
            dependencies = dependencies,
            outputs = outputs,
        ),
    )
