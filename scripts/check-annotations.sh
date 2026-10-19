#!/bin/zsh
set -eu
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/klar-annotations.XXXXXX")"
trap 'rm -rf "$check_dir"' EXIT
cd "$project_dir"
xcrun swiftc -swift-version 5 -target arm64-apple-macos14 \
    -emit-library -emit-module -module-name KlarCore \
    Sources/KlarCore/Domain/CoachResponse.swift Sources/KlarCore/Learning/RuleRegistry.swift \
    -emit-module-path "$check_dir/KlarCore.swiftmodule" -o "$check_dir/libKlarCore.dylib"
cat Sources/KlarApp/AnnotatedPromptView.swift Tests/NativeChecks/AnnotationCheck.swift.fragment > "$check_dir/AnnotationCheck.swift"
xcrun swiftc -parse-as-library -swift-version 5 -target arm64-apple-macos14 \
    -I "$check_dir" -L "$check_dir" -lKlarCore -Xlinker -rpath -Xlinker "$check_dir" \
    Sources/KlarApp/DesignSystem.swift Sources/KlarApp/AnnotationMotion.swift Sources/KlarApp/AnnotationLensShape.swift \
    Sources/KlarApp/AnnotationLensCanvas.swift Sources/KlarApp/AnnotationAnchorGlow.swift Sources/KlarApp/AnnotationPresentation.swift \
    "$check_dir/AnnotationCheck.swift" -o "$check_dir/check"
"$check_dir/check"
