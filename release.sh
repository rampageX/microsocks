#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $0 vVERSION [--publish]" >&2
    exit 2
}

(( $# == 1 || $# == 2 )) || usage
tag=$1
[[ $tag =~ ^v[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9]+)*$ ]] || usage
mode=${2:-}
[[ -z $mode || $mode == --publish ]] || usage

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
repo=${RELEASE_REPO:-rampageX/microsocks}
zig=${ZIG:-zig}
[[ $("$zig" version) == 0.15.2 ]] || {
    echo "Zig 0.15.2 is required." >&2
    exit 1
}

if [[ $mode == --publish ]]; then
    git diff --quiet HEAD
    [[ -z $(git ls-files --others --exclude-standard) ]] || {
        echo "Commit or remove untracked files before publishing." >&2
        exit 1
    }
    commit=$(git rev-parse HEAD)
    remote_tag=$(gh api --method GET "repos/$repo/git/matching-refs/tags/$tag" \
        --jq ".[] | select(.ref == \"refs/tags/$tag\") | .ref")
    if [[ -n $remote_tag ]]; then
        [[ $(gh api --method GET "repos/$repo/commits/$tag" --jq .sha) == "$commit" ]] || {
            echo "Remote tag $tag points to a different commit." >&2
            exit 1
        }
    else
        gh api --method GET "repos/$repo/commits/$commit" --jq .sha >/dev/null
    fi
fi

work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work"/{stage,assets} dist
sources=(sockssrv.c server.c sblist.c sblist_delete.c)
common=(-std=c11 -Os -s -static)
cp COPYING "$work/stage/"

build_linux() {
    local arch=$1 target=$2 machine=$3
    shift 3
    local output="$work/stage/microsocks"
    "$zig" cc -target "$target" "${common[@]}" "$@" -o "$output" "${sources[@]}" -pthread
    local header program_headers dynamic
    header=$(LC_ALL=C readelf -h "$output")
    program_headers=$(LC_ALL=C readelf -l "$output")
    dynamic=$(LC_ALL=C readelf -d "$output")
    [[ $header == *"Machine:"*"$machine"* && $program_headers != *INTERP* && $dynamic != *NEEDED* ]]
    if [[ $arch == armv7-sf ]]; then
        [[ $header == *"soft-float ABI"* ]]
        LC_ALL=C readelf -A "$output" | grep -E 'Tag_CPU_arch: v7$'
    fi
    if [[ $arch == x86_64 && $(uname -m) == x86_64 && $(uname -s) == Linux ]]; then
        python3 scripts/smoke.py "$output"
    fi
    tar -C "$work/stage" -czf "$work/assets/microsocks-$tag-linux-$arch.tar.gz" microsocks COPYING
}

build_linux armv7-sf arm-linux.2.6.36-musleabi ARM -mcpu=generic+v7a+soft_float
build_linux aarch64 aarch64-linux-musl AArch64
build_linux x86_64 x86_64-linux-musl 'Advanced Micro Devices X86-64'

windows="$work/stage/microsocks.exe"
"$zig" cc -target x86_64-windows-gnu "${common[@]}" -o "$windows" "${sources[@]}" -lws2_32
pe_headers=$(LC_ALL=C objdump -f "$windows")
[[ $pe_headers == *pei-x86-64* ]]
imports=$(LC_ALL=C objdump -p "$windows" | awk '/DLL Name:/ { print tolower($3) }')
[[ -n $imports ]]
while IFS= read -r dll; do
    case "$dll" in
        kernel32.dll|ws2_32.dll|ucrtbase.dll|api-ms-win-crt-*.dll) ;;
        *) echo "Unexpected Windows DLL import: $dll" >&2; exit 1 ;;
    esac
done <<< "$imports"
windows_zip="microsocks-$tag-windows-x64.zip"
(cd "$work/stage" && zip -q "$work/assets/$windows_zip" microsocks.exe COPYING)

assets=("$work/assets/"*)
for asset in "${assets[@]}"; do
    cp -- "$asset" "dist/${asset##*/}"
    echo "dist/${asset##*/}"
done

if [[ $mode == --publish ]]; then
    gh release create "$tag" "${assets[@]}" --repo "$repo" --target "$commit" \
        --title "MicroSocks $tag" --generate-notes
fi
