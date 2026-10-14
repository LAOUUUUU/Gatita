# LaTeXSwiftUI, patched for Gatita

A copy of [LaTeXSwiftUI](https://github.com/colinc86/LaTeXSwiftUI) 2.0.0 (MIT, see `LICENSE.md`), commit `cc677f66b9cc1751e09207621d62d1cda0200675`, with two fixes. Gatita uses this copy instead of the GitHub package. Each change is marked `Gatita patch` in the code.

1. **Numbers in formulas.** MathJaxSwift 3.5.0's default `digits` pattern is `^(?:[0-9]+(?:{,}[0-9]{3})*(?:.[0-9]*)?|.[0-9]+)`: the backslashes are gone, so `.` matches any character and the character after a number becomes part of it. `x_{n=1}`, `\lim_{x \to 0}`, and `\sum_{n=1}^{\infty}` failed with "Extra open brace or missing close brace", and `-2\pi i` drew as `2\` then `pi i`. `TeXInputProcessorOptions+Extensions.swift` now sets MathJax's own pattern, `^(?:[0-9]+(?:\{,\}[0-9]{3})*(?:\.[0-9]*)?|\.[0-9]+)`.
2. **Equation size on the Mac.** `Renderer.rasterizeSVG` makes `NSImage(cgImage:size:)` with the size in points, and `Image(image:scale:)` then divided that size by the display scale again, so a Mac equation drew at half size (and faint) the first time and at full size from the cache. `Image+Extensions.swift` no longer divides on the Mac.

## Upstream status (checked 2026-10-14)

Both bugs are already reported upstream, each with an open pull request that makes the same fix; the author's last commit to either repo was 2026-04-03.

- Numbers: [MathJaxSwift #45](https://github.com/colinc86/MathJaxSwift/issues/45) (root cause in its July comment), fix in [MathJaxSwift PR #48](https://github.com/colinc86/MathJaxSwift/pull/48). The same symptom is [LaTeXSwiftUI #79](https://github.com/colinc86/LaTeXSwiftUI/issues/79) and [#86](https://github.com/colinc86/LaTeXSwiftUI/issues/86).
- Mac size: [LaTeXSwiftUI #83](https://github.com/colinc86/LaTeXSwiftUI/issues/83), fix in [LaTeXSwiftUI PR #85](https://github.com/colinc86/LaTeXSwiftUI/pull/85).
- Not patched here: #83 also notes that the image cache key leaves out the display scale, so with two displays of different scales an equation can come from the cache at the other display's sharpness (its size is right).

When a MathJaxSwift release includes PR #48 and a LaTeXSwiftUI release includes PR #85, Gatita can go back to the GitHub package.

Not copied: the package's tests, assets, and README; its test target is removed from `Package.swift`.

To update: copy the new release's `Sources/`, `Package.swift`, and `LICENSE.md` over this folder, check whether both bugs are still there, and reapply what is still needed. If upstream fixes both, Gatita can go back to the GitHub package.
