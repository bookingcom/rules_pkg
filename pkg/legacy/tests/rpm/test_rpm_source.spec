Name: rules_pkg
Version: 0
Release: 1
Summary: Test data
URL: https://github.com/bazelbuild/rules_pkg
License: Apache License, v2.0

# the file name needs to match the basename of the source passed
# to the pkg_rpm call
Source0: rpm.bzl

# Do not try to use magic to determine file types
%define __spec_install_post %{nil}
# Do not die because we give it more input files than are in the files section
%define _unpackaged_files_terminate_build 0

%description
This is a package description

%prep

%build

%install
mkdir -p %{buildroot}/legacy
cp -r %{SOURCE0} %{buildroot}/legacy

%files
/legacy/rpm.bzl
