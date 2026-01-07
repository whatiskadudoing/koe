# Changelog

## [1.4.3](https://github.com/whatiskadudoing/koe/compare/v1.4.2...v1.4.3) (2026-01-07)


### Bug Fixes

* correct distributed notification observer for accessibility permission detection ([634bddd](https://github.com/whatiskadudoing/koe/commit/634bddd61147677fd23f16e6f554c639fd5f5355))

## [1.4.2](https://github.com/whatiskadudoing/koe/compare/v1.4.1...v1.4.2) (2026-01-07)


### Bug Fixes

* use distributed notification to detect accessibility permission changes ([4585611](https://github.com/whatiskadudoing/koe/commit/458561142d78e8fa7e1b1709e2c3ee5beb58ae5c))

## [1.4.1](https://github.com/whatiskadudoing/koe/compare/v1.4.0...v1.4.1) (2026-01-07)


### Bug Fixes

* remove extra accessibility dialog, just open System Settings ([105987a](https://github.com/whatiskadudoing/koe/commit/105987ad8ab2ae8d09fff652f0641692e2785a22))

## [1.4.0](https://github.com/whatiskadudoing/koe/compare/v1.3.5...v1.4.0) (2026-01-07)


### Features

* implement multi-stage app initialization with permissions and loading states ([17e06ec](https://github.com/whatiskadudoing/koe/commit/17e06ecdbc82ea8aa87ce652cc6df762d22b9cb9))


### Bug Fixes

* add retry logic and 'Try Again' button for macOS TCC permission caching issue ([ca6c0ee](https://github.com/whatiskadudoing/koe/commit/ca6c0ee8e747d8fa85e63fa0d74988220756d550))
* open System Settings directly for accessibility permission ([33adb96](https://github.com/whatiskadudoing/koe/commit/33adb96ecbcb95ef9ecc40a90f802b45d47b895d))
* prevent permission popups before user action, fix animations ([e79ad3e](https://github.com/whatiskadudoing/koe/commit/e79ad3ea2fcefad25da049fd22f184a25423a9b9))
* reconnect stdin to terminal for interactive installer ([9eb2bb2](https://github.com/whatiskadudoing/koe/commit/9eb2bb2e3ccbee8a88743ec9636cf5de289f3d7d))
* request permissions instead of only checking them ([c513969](https://github.com/whatiskadudoing/koe/commit/c51396932f011243cc32cae7df74a38d78d3bfd3))
* use exec to properly connect stdin for interactive installer ([281cd4f](https://github.com/whatiskadudoing/koe/commit/281cd4ff5df7d4a173bd69d3a9f44c42806a7c90))
* use process substitution for interactive installer with proper stdin ([a482b3c](https://github.com/whatiskadudoing/koe/commit/a482b3c342d7043e95ec7b0e798439b989917a05))

## [1.3.5](https://github.com/whatiskadudoing/koe/compare/v1.3.4...v1.3.5) (2026-01-07)


### Bug Fixes

* correct paths in workflows to WhisperApp/WhisperApp ([4f313b6](https://github.com/whatiskadudoing/koe/commit/4f313b6aef94ed01eee4b61de4c538c61ebd4257))
