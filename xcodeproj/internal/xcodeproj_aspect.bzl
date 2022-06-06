"""Implementation of the `xcodeproj_aspect` aspect."""

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load(
    ":default_input_file_attributes_aspect.bzl",
    "default_input_file_attributes_aspect",
)
load(":providers.bzl", "XcodeProjInfo")
load(":xcodeprojinfo.bzl", "create_xcodeprojinfo")

# Utility

def _should_ignore_attr(attr):
    return (
        # We don't want to include implicit dependencies
        attr.startswith("_") or
        # These are actually Starklark methods, so ignore them
        attr in ("to_json", "to_proto")
    )

def _transitive_infos(*, ctx):
    transitive_infos = []
    for attr in dir(ctx.rule.attr):
        if _should_ignore_attr(attr):
            continue

        dep = getattr(ctx.rule.attr, attr)
        if type(dep) == "list":
            for dep in dep:
                if type(dep) == "Target" and XcodeProjInfo in dep:
                    transitive_infos.append((attr, dep[XcodeProjInfo]))
        elif type(dep) == "Target" and XcodeProjInfo in dep:
            transitive_infos.append((attr, dep[XcodeProjInfo]))

    return transitive_infos

# Aspect

def _xcodeproj_aspect_impl(target, ctx):
    # Don't create an `XcodeProjInfo` if the target already created one
    if XcodeProjInfo in target:
        return []

    return [
        create_xcodeprojinfo(
            ctx = ctx,
            target = target,
            transitive_infos = _transitive_infos(ctx = ctx),
        ),
    ]

xcodeproj_aspect = aspect(
    implementation = _xcodeproj_aspect_impl,
    attr_aspects = ["*"],
    attrs = {
        "_archived_bundles_allowed": attr.label(
            default = Label("//xcodeproj/internal:archived_bundles_allowed"),
            providers = [BuildSettingInfo],
        ),
        "_build_mode": attr.label(
            default = Label("//xcodeproj/internal:build_mode"),
            providers = [BuildSettingInfo],
        ),
        "_cc_toolchain": attr.label(default = Label(
            "@bazel_tools//tools/cpp:current_cc_toolchain",
        )),
        "_xcode_config": attr.label(
            default = configuration_field(
                name = "xcode_config_label",
                fragment = "apple",
            ),
        ),
    },
    fragments = ["apple", "cpp"],
    requires = [default_input_file_attributes_aspect],
)
