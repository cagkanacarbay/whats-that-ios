---
description: How to build the iOS app from terminal
---

# Building WhatsThatIOS

When building from the terminal, always use a separate DerivedData path to avoid conflicts with Xcode GUI:

```bash
cd /Users/cagkanacarbay/Projects/whats-that/whats-that-ios/native

# Build
xcodebuild -workspace WhatsThatIOS.xcworkspace \
  -scheme "WhatsThatIOS" \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -derivedDataPath /tmp/WhatsThatBuild \
  build

# Run tests
xcodebuild -workspace WhatsThatIOS.xcworkspace \
  -scheme "WhatsThatIOS" \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -derivedDataPath /tmp/WhatsThatBuild \
  test
```

The `-derivedDataPath /tmp/WhatsThatBuild` flag tells xcodebuild to use a separate folder, preventing "build.db" conflicts with Xcode.

Note: First build after adding this flag will be slower (full rebuild), but subsequent builds and your Xcode GUI will no longer conflict.
