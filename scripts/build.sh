#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/.." && pwd)"
cd "$project_dir"

source "${script_dir}/config.sh"

host_arch="$(uname -m)"
target_arch="${ARCH:-$host_arch}"
universal=false
if [[ "${UNIVERSAL:-false}" == "true" || "${UNIVERSAL:-0}" == "1" ]]; then
    universal=true
fi
build_mode="${BUILD_MODE:-release}"
if [[ "${DEBUG:-false}" == "true" || "${DEBUG:-0}" == "1" ]]; then
    build_mode="debug"
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
    --universal)
        universal=true
        shift
        ;;
    --no-universal)
        universal=false
        shift
        ;;
    --arch)
        target_arch="$2"
        shift 2
        ;;
    --debug)
        build_mode="debug"
        shift
        ;;
    --release)
        build_mode="release"
        shift
        ;;
    *)
        printf '%s\n' "Warning: Unknown option '$1'" >&2
        shift
        ;;
    esac
done

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/${APP_NAME,,}"
mkdir -p "$cache_dir"

sdk_file="${cache_dir}/sdk_path.tmp"
xcrun --show-sdk-path >"$sdk_file" 2>/dev/null
if [[ ! -s "$sdk_file" ]]; then
    rm -f "$sdk_file"
    printf '%s\n' "Error: Failed to obtain SDK path from xcrun" >&2
    exit 1
fi
IFS= read -r sdk_path <"$sdk_file"
rm -f "$sdk_file"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf '%s\n' "Error: VERSION file must contain a version like 1.2.3 (found '${VERSION}')" >&2
    exit 1
fi

# Every build increments BUILD_NUMBER; the file is the single source of truth.
if [[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
    build_number=$((10#$BUILD_NUMBER + 1))
else
    build_number=1
fi
printf '%s\n' "$build_number" >"$build_num_file"
export BUILD_NUMBER="$build_number"

build_dir="build"
app_name="${APP_NAME}"
display_name="${APP_DISPLAY_NAME:-$APP_NAME}"
bundle_id="${BUNDLE_ID}"
app_dir="${build_dir}/${display_name}.app"
contents_dir="${app_dir}/Contents"
macos_dir="${contents_dir}/MacOS"
resources_dir="${contents_dir}/Resources"

rm -rf "${app_dir:?}"
mkdir -p "$macos_dir" "$resources_dir"

if [[ -d "Resources" ]]; then
    cp -R Resources/. "${resources_dir}/"
    rm -f "${resources_dir:?}"/*.svg "${resources_dir:?}/.DS_Store"
fi

if [[ -f "VERSION" ]]; then
    cp "VERSION" "${resources_dir}/VERSION"
fi
printf '%s\n' "$build_number" >"${resources_dir}/BUILD_NUMBER"

collect() {
    find "$1" -type f -name "*.swift" | sort
}
shared_sources=()
while IFS= read -r file; do shared_sources+=("$file"); done < <(collect Sources/Shared)
sources=()
while IFS= read -r file; do sources+=("$file"); done < <(collect Sources/App)
ql_sources=()
while IFS= read -r file; do ql_sources+=("$file"); done < <(collect Sources/QuickLook)

ql_name="MarkdownQuickLook"
ql_bundle_id="${bundle_id}.QuickLook"
appex_dir="${contents_dir}/PlugIns/${ql_name}.appex"
app_bin="${macos_dir}/${app_name}"
ql_bin="${appex_dir}/Contents/MacOS/${ql_name}"
mkdir -p "${appex_dir}/Contents/MacOS"

if [[ "$build_mode" == "debug" ]]; then
    opt_flags=(-Onone)
else
    opt_flags=(-O -whole-module-optimization)
fi

app_flags=(-module-name "$app_name" "${opt_flags[@]}" -Xlinker -dead_strip
    "${shared_sources[@]}" "${sources[@]}")
# Quick Look preview extension (Finder → Space on a Markdown file).
ql_flags=(-module-name "$ql_name" "${opt_flags[@]}" -parse-as-library -application-extension
    -Xlinker -e -Xlinker _NSExtensionMain -Xlinker -dead_strip -framework QuickLookUI
    "${shared_sources[@]}" "${ql_sources[@]}")

if [[ "$universal" == true ]]; then
    printf '%s\n' "Compiling ${app_name} v${VERSION} (Build ${BUILD_NUMBER}) and ${ql_name}.appex (universal: x86_64 + arm64)..."
    swiftc -sdk "$sdk_path" -target "x86_64-apple-macos${MIN_MACOS_VERSION}" "${app_flags[@]}" -o "${app_bin}.x86_64" &
    app_x86_pid=$!
    swiftc -sdk "$sdk_path" -target "x86_64-apple-macos${MIN_MACOS_VERSION}" "${ql_flags[@]}" -o "${ql_bin}.x86_64" &
    ql_x86_pid=$!
    swiftc -sdk "$sdk_path" -target "arm64-apple-macos${MIN_MACOS_VERSION}" "${app_flags[@]}" -o "${app_bin}.arm64" &
    app_arm_pid=$!
    swiftc -sdk "$sdk_path" -target "arm64-apple-macos${MIN_MACOS_VERSION}" "${ql_flags[@]}" -o "${ql_bin}.arm64" &
    ql_arm_pid=$!

    wait "$app_x86_pid"
    wait "$ql_x86_pid"
    wait "$app_arm_pid"
    wait "$ql_arm_pid"

    printf '%s\n' "Creating universal binaries (x86_64 + arm64)..."
    lipo -create "${app_bin}.x86_64" "${app_bin}.arm64" -output "$app_bin"
    lipo -create "${ql_bin}.x86_64" "${ql_bin}.arm64" -output "$ql_bin"
    rm -f "${app_bin:?}.x86_64" "${app_bin:?}.arm64" "${ql_bin:?}.x86_64" "${ql_bin:?}.arm64"
else
    printf '%s\n' "Compiling ${app_name} v${VERSION} (Build ${BUILD_NUMBER}) and ${ql_name}.appex (${target_arch})..."
    swiftc -sdk "$sdk_path" -target "${target_arch}-apple-macos${MIN_MACOS_VERSION}" "${app_flags[@]}" -o "$app_bin" &
    app_pid=$!
    swiftc -sdk "$sdk_path" -target "${target_arch}-apple-macos${MIN_MACOS_VERSION}" "${ql_flags[@]}" -o "$ql_bin" &
    ql_pid=$!
    wait "$app_pid"
    wait "$ql_pid"
fi

printf '%s\n' "Generating ${app_name} Info.plist..."
cat <<EOF >"${contents_dir}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${app_name}</string>
    <key>CFBundleIdentifier</key>
    <string>${bundle_id}</string>
    <key>CFBundleName</key>
    <string>${display_name}</string>
    <key>CFBundleDisplayName</key>
    <string>${display_name}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon.icns</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>${MIN_MACOS_VERSION}</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>LSUIElement</key>
    <${LS_UI_ELEMENT}/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>${COPYRIGHT}</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Markdown Document</string>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>CFBundleTypeIconSystemGenerated</key>
            <integer>1</integer>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>md</string>
                <string>markdown</string>
                <string>mdown</string>
                <string>mkd</string>
                <string>mkdn</string>
                <string>mdwn</string>
                <string>mdtext</string>
            </array>
            <key>LSHandlerRank</key>
            <string>Default</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>net.daringfireball.markdown</string>
            </array>
            <key>NSDocumentClass</key>
            <string>MarkdownDocument</string>
        </dict>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Plain Text Document</string>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.plain-text</string>
            </array>
            <key>NSDocumentClass</key>
            <string>MarkdownDocument</string>
        </dict>
    </array>
    <key>UTImportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key>
            <string>net.daringfireball.markdown</string>
            <key>UTTypeDescription</key>
            <string>Markdown Document</string>
            <key>UTTypeConformsTo</key>
            <array>
                <string>public.plain-text</string>
            </array>
            <key>UTTypeReferenceURL</key>
            <string>https://daringfireball.net/projects/markdown/</string>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array>
                    <string>md</string>
                    <string>markdown</string>
                    <string>mdown</string>
                    <string>mkd</string>
                    <string>mkdn</string>
                    <string>mdwn</string>
                    <string>mdtext</string>
                </array>
                <key>public.mime-type</key>
                <array>
                    <string>text/markdown</string>
                    <string>text/x-markdown</string>
                </array>
            </dict>
        </dict>
    </array>
</dict>
</plist>
EOF

printf '%s\n' "Generating ${ql_name}.appex Info.plist..."
cat <<EOF >"${appex_dir}/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>${display_name} Quick Look</string>
    <key>CFBundleExecutable</key>
    <string>${ql_name}</string>
    <key>CFBundleIdentifier</key>
    <string>${ql_bundle_id}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${ql_name}</string>
    <key>CFBundlePackageType</key>
    <string>XPC!</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>MacOSX</string>
    </array>
    <key>LSMinimumSystemVersion</key>
    <string>${MIN_MACOS_VERSION}</string>
    <key>NSHumanReadableCopyright</key>
    <string>${COPYRIGHT}</string>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionAttributes</key>
        <dict>
            <key>QLIsDataBasedPreview</key>
            <true/>
            <key>QLSupportedContentTypes</key>
            <array>
                <string>net.daringfireball.markdown</string>
            </array>
            <key>QLSupportsSearchableItems</key>
            <false/>
        </dict>
        <key>NSExtensionPointIdentifier</key>
        <string>com.apple.quicklook.preview</string>
        <key>NSExtensionPrincipalClass</key>
        <string>PreviewProvider</string>
    </dict>
</dict>
</plist>
EOF

ql_entitlements="${cache_dir}/quicklook.entitlements"
cat <<EOF >"$ql_entitlements"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-only</key>
    <true/>
</dict>
</plist>
EOF

# macOS remembers granted permissions (TCC) against the app's designated requirement.
# Ad-hoc signing defaults to a per-build cdhash requirement, which loses permissions on
# every rebuild, so pin the requirement to the bundle ID instead. No keychain is used.
designated_requirement="designated => identifier \"${bundle_id}\""

# App extensions must be sandboxed: sign the extension first with its entitlements, then the
# app without --deep (which would re-sign the extension and drop its entitlements).
printf '%s\n' "Signing ${ql_name}.appex (ad-hoc, sandboxed)..."
codesign --force --sign - --entitlements "$ql_entitlements" \
    --requirements "=designated => identifier \"${ql_bundle_id}\"" "$appex_dir"

printf '%s\n' "Signing ${app_name} bundle (ad-hoc, ${designated_requirement})..."
codesign --force --sign - --requirements "=${designated_requirement}" "$app_dir"

signed_requirement="$(codesign -d -r- "$app_dir" 2>&1 | grep '^designated => ' || true)"
if [[ "$signed_requirement" != "$designated_requirement" ]]; then
    printf '%s\n' "Error: Unexpected designated requirement '${signed_requirement}'; permissions would not persist." >&2
    exit 1
fi
codesign --verify --strict "$app_dir"

printf '%s\n' "Refreshing macOS LaunchServices and Quick Look caches..."
touch "$app_dir"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f -R "$app_dir" >/dev/null 2>&1 || true
pluginkit -a "$appex_dir" >/dev/null 2>&1 || true
qlmanage -r >/dev/null 2>&1 || true
qlmanage -r cache >/dev/null 2>&1 || true

printf '%s\n' "✅ Build complete:"
printf '%s\n' "   - ${app_dir}"
