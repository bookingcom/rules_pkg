# Copyright 2021 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
"""Rules for manipulation of various packaging."""

load("//pkg:path.bzl", "compute_data_path", "dest_path")
load(
    "//pkg:providers.bzl",
    "PackageArtifactInfo",
    "PackageVariablesInfo",
)
load("//pkg/private:util.bzl", "setup_output_files")
load(
    "//pkg/private:pkg_files.bzl",
    "add_single_file",
    "add_tree_artifact",
    "process_src",
    "write_manifest",
)

_stamp_condition = str(Label("//pkg/private:private_stamp_detect"))

def _pkg_zip_impl(ctx):
    outputs, output_file, output_name = setup_output_files(ctx)

    args = ctx.actions.args()
    args.add("-o", output_file.path)
    args.add("-d", ctx.attr.package_dir)
    args.add("-t", ctx.attr.timestamp)
    args.add("-m", ctx.attr.mode)
    inputs = []
    if ctx.attr.stamp == 1 or (ctx.attr.stamp == -1 and
                               ctx.attr.private_stamp_detect):
        args.add("--stamp_from", ctx.version_file.path)
        inputs.append(ctx.version_file)

    data_path = compute_data_path(ctx, ctx.attr.strip_prefix)
    data_path_without_prefix = compute_data_path(ctx, ".")

    content_map = {}  # content handled in the manifest

    # TODO(aiuto): Refactor this loop out of pkg_tar and pkg_zip into a helper
    # that both can use.
    for src in ctx.attr.srcs:
        # Gather the files for every srcs entry here, even if it is not from
        # a pkg_* rule.
        if DefaultInfo in src:
            inputs.extend(src[DefaultInfo].files.to_list())
        if not process_src(
            content_map,
            src,
            src.label,
            default_mode = None,
            default_user = None,
            default_group = None,
        ):
            # Add in the files of srcs which are not pkg_* types
            for f in src.files.to_list():
                d_path = dest_path(f, data_path, data_path_without_prefix)
                if f.is_directory:
                    # Tree artifacts need a name, but the name is never really
                    # the important part. The likely behavior people want is
                    # just the content, so we strip the directory name.
                    dest = "/".join(d_path.split("/")[0:-1])
                    add_tree_artifact(content_map, dest, f, src.label)
                else:
                    add_single_file(content_map, d_path, f, src.label)

    manifest_file = ctx.actions.declare_file(ctx.label.name + ".manifest")
    inputs.append(manifest_file)
    write_manifest(ctx, manifest_file, content_map)
    args.add("--manifest", manifest_file.path)
    args.set_param_file_format("multiline")
    args.use_param_file("@%s")

    ctx.actions.run(
        mnemonic = "PackageZip",
        inputs = ctx.files.srcs + inputs,
        executable = ctx.executable._build_zip,
        arguments = [args],
        outputs = [output_file],
        env = {
            "LANG": "en_US.UTF-8",
            "LC_CTYPE": "UTF-8",
            "PYTHONIOENCODING": "UTF-8",
            "PYTHONUTF8": "1",
        },
        use_default_shell_env = True,
    )
    return [
        DefaultInfo(
            files = depset([output_file]),
            runfiles = ctx.runfiles(files = outputs),
        ),
        PackageArtifactInfo(
            label = ctx.label.name,
            file = output_file,
            file_name = output_name,
        ),
    ]

pkg_zip_impl = rule(
    implementation = _pkg_zip_impl,
    # @unsorted-dict-items
    attrs = {
        "srcs": attr.label_list(
            doc = """List of files that should be included in the archive.""",
            allow_files = True,
        ),
        "mode": attr.string(
            doc = """The default mode for all files in the archive.""",
            default = "0555",
        ),
        "package_dir": attr.string(
            doc = """The prefix to add to all all paths in the archive.""",
            default = "/",
        ),
        "strip_prefix": attr.string(),
        "timestamp": attr.int(
            doc = """Time stamp to place on all files in the archive, expressed
as seconds since the Unix Epoch, as per RFC 3339.  The default is January 01,
1980, 00:00 UTC.

Due to limitations in the format of zip files, values before
Jan 1, 1980 will be rounded up and the precision in the zip file is
limited to a granularity of 2 seconds.""",
            default = 315532800,
        ),

        # Common attributes
        "out": attr.output(mandatory = True),
        "package_file_name": attr.string(doc = "See Common Attributes"),
        "package_variables": attr.label(
            doc = "See Common Attributes",
            providers = [PackageVariablesInfo],
        ),
        "stamp": attr.int(
            doc = """Enable file time stamping.  Possible values:
<li>stamp = 1: Use the time of the build as the modification time of each file in the archive.
<li>stamp = 0: Use an "epoch" time for the modification time of each file. This gives good build result caching.
<li>stamp = -1: Control the chosen modification time using the --[no]stamp flag.
""",
            default = 0,
        ),

        # Is --stamp set on the command line?
        # TODO(https://github.com/bazelbuild/rules_pkg/issues/340): Remove this.
        "private_stamp_detect": attr.bool(default = False),

        # Implicit dependencies.
        "_build_zip": attr.label(
            default = Label("//pkg/private/zip:build_zip"),
            cfg = "exec",
            executable = True,
            allow_files = True,
        ),
    },
    provides = [PackageArtifactInfo],
)

def pkg_zip(name, **kwargs):
    """Creates a .zip file. See pkg_zip_impl."""
    extension = kwargs.pop("extension", None)
    if extension:
        # buildifier: disable=print
        print("'extension' is deprecated. Use 'package_file_name' or 'out' to name the output.")
    else:
        extension = "zip"
    archive_name = kwargs.pop("archive_name", None)
    if archive_name:
        if kwargs.get("package_file_name"):
            fail("You may not set both 'archive_name' and 'package_file_name'.")

        # buildifier: disable=print
        print("archive_name is deprecated. Use package_file_name instead.")
        kwargs["package_file_name"] = archive_name + "." + extension
    else:
        archive_name = name
    pkg_zip_impl(
        name = name,
        out = archive_name + "." + extension,
        private_stamp_detect = select({
            _stamp_condition: True,
            "//conditions:default": False,
        }),
        **kwargs
    )
