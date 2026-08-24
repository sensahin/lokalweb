# Contributing to Lokalweb

Thanks for helping improve Lokalweb. Keep changes focused, preserve existing
site and database data, and never make service controls target globally managed
Homebrew or MAMP processes.

## Development setup

Requirements:

- macOS 14 or newer
- Xcode
- [Homebrew](https://brew.sh/)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

Generate the Xcode project and run the test suite:

```sh
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Lokalweb.xcodeproj \
  -scheme Lokalweb \
  -configuration Debug \
  -derivedDataPath .build/DerivedData \
  test CODE_SIGNING_ALLOWED=NO
```

Tests that require nginx, PHP or MariaDB skip when those runtimes are not
installed. When installed, integration tests use isolated temporary data and
high ports and must stop every process they start.

## Pull requests

- Describe the user problem and why the change solves it.
- Add or update tests for behavior changes.
- Run the complete test command above.
- Keep generated `Lokalweb.xcodeproj` changes in sync with `project.yml`.
- Do not commit `.build`, `DerivedData`, credentials, certificates, databases,
  site files or runtime logs.

By contributing, you agree that your contribution is licensed under the MIT
License used by this repository.
