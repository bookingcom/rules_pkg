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
"""Internal utilities for rules_pkg."""

load("//pkg:providers.bzl", "PackageVariablesInfo")

def setup_output_files(ctx, package_file_name = None, default_output_file = None):
    """Provide output file metadata for common packaging rules

    By default, this will instruct rules to write directly to the File specified
    by the `default_output_file` argument or `ctx.outputs.out` otherwise.

    If `package_file_name` is given, or is available in `ctx`, we will write to
    that name instead, do substitution via `ctx.attr.package_variables`, and the
    default output (either by `default_output_file` or `ctx.outputs.out`) will
    be a symlink to it.

    Callers should:
       - write to `output_file`
       - add `outputs` to their returned `DefaultInfo(files)` provider
       - Possibly add a distinguishing element to OutputGroups

    Args:
      ctx: rule context
      package_file_name: computed value for package_file_name
      default_output_file: File identifying the rule's default output, otherwise `ctx.outputs.out` will be used instead.

    Returns:
      outputs: list(output handles)
      output_file: file handle to write to
      output_name: name of output file

    """
    default_output = default_output_file or ctx.outputs.out

    outputs = [default_output]
    if not package_file_name:
        package_file_name = ctx.attr.package_file_name
    if package_file_name:
        output_name = substitute_package_variables(ctx, package_file_name)
        output_file = ctx.actions.declare_file(output_name)
        outputs.append(output_file)
        ctx.actions.symlink(
            output = default_output,
            target_file = output_file,
        )
    else:
        output_file = default_output
        output_name = output_file.basename
    return outputs, output_file, output_name

def substitute_package_variables(ctx, attribute_value):
    """Substitute package_variables in the attribute with the given name.

    Args:
      ctx: context
      attribute_value: the name of the attribute to perform package_variables substitution for

    Returns:
      expanded_attribute_value: new value of the attribute after package_variables substitution
    """
    if not attribute_value:
        return attribute_value

    if type(attribute_value) != "string":
        fail("attempt to substitute package_variables in the attribute value %s which is not a string" % attribute_value)
    vars = dict(ctx.var)
    if ctx.attr.package_variables:
        package_variables = ctx.attr.package_variables[PackageVariablesInfo]
        vars.update(package_variables.values)

    # Map $(var) to {x} and then use format for substitution.
    # This is brittle and I hate it. We should have template substitution
    # in the Starlark runtime.
    return attribute_value.replace("$(", "{").replace(")", "}").format(**vars)
