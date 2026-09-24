#!/bin/sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(dirname -- "$SCRIPT_DIR")"
VERSION_FILE="$PROJECT_DIR/VERSION"

fail() {
  printf '%s\n' "test-version-consistency: $*" >&2
  exit 1
}

[ -f "$VERSION_FILE" ] || fail 'root VERSION file is missing'
[ "$(wc -l <"$VERSION_FILE")" -eq 1 ] \
  || fail 'VERSION must contain exactly one newline-terminated line'

IFS= read -r version <"$VERSION_FILE"

printf '%s\n' "$version" \
  | grep -Eq '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$' \
  || fail 'VERSION must contain a stable MAJOR.MINOR.PATCH version'

expected_release=''

for package_makefile in \
  "$PROJECT_DIR/wi-fi-qr/Makefile" \
  "$PROJECT_DIR/luci-app-wi-fi-qr/Makefile"
do
  package_version="$(sed -n 's/^PKG_VERSION:=//p' "$package_makefile")"
  package_release="$(sed -n 's/^PKG_RELEASE:=//p' "$package_makefile")"

  [ "$package_version" = "$version" ] \
    || fail "${package_makefile#$PROJECT_DIR/} has PKG_VERSION=$package_version, expected $version"

  case "$package_release" in
    ''|*[!0-9]*)
      fail "${package_makefile#$PROJECT_DIR/} has an invalid PKG_RELEASE"
      ;;
  esac

  if [ -z "$expected_release" ]; then
    expected_release="$package_release"
  elif [ "$package_release" != "$expected_release" ]; then
    fail 'package Makefiles have different PKG_RELEASE values'
  fi
done

printf '%s\n' "test-version-consistency: ok ($version-r$expected_release)"
