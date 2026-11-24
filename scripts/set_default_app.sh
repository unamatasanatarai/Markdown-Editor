#!/usr/bin/env bash
# Makes Markdown Editor the default app (and document icon) for every Markdown file type.
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/config.sh"

swift - "$BUNDLE_ID" <<'SWIFT'
import CoreServices
import UniformTypeIdentifiers

let bundleID = CommandLine.arguments[1] as CFString
var types = Set(["net.daringfireball.markdown"])
for ext in ["md", "markdown", "mdown", "mkd", "mkdn", "mdwn", "mdtext"] {
    if let t = UTType(filenameExtension: ext), !t.identifier.hasPrefix("dyn.") { types.insert(t.identifier) }
}
var failed = false
for t in types.sorted() {
    let status = LSSetDefaultRoleHandlerForContentType(t as CFString, .all, bundleID)
    print(status == noErr ? "✔ \(t) → \(bundleID)" : "✘ \(t): error \(status)")
    if status != noErr { failed = true }
}
exit(failed ? 1 : 0)
SWIFT

# Refresh Finder's icon caches and Quick Look registration.
app_bundle="build/${APP_DISPLAY_NAME:-$APP_NAME}.app"
appex_path="${app_bundle}/Contents/PlugIns/MarkdownQuickLook.appex"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f -R "$app_bundle" >/dev/null 2>&1 || true
if [[ -d "$appex_path" ]]; then
    pluginkit -a "$appex_path" >/dev/null 2>&1 || true
    pluginkit -e use -i "${BUNDLE_ID}.QuickLook" >/dev/null 2>&1 || true
fi
qlmanage -r >/dev/null 2>&1 || true
qlmanage -r cache >/dev/null 2>&1 || true
killall Finder >/dev/null 2>&1 || true
killall Dock >/dev/null 2>&1 || true
