# Changelog

## [1.10.0-beta.6](https://github.com/whatiskadudoing/koe/compare/v1.9.0-beta.6...v1.10.0-beta.6) (2026-01-09)


### Features

* add auto-switch preference and disable non-ready models ([48d0664](https://github.com/whatiskadudoing/koe/commit/48d0664ac296733d5f2f555e515014ea166b71af))
* add automatic retry logic for background model downloads ([964f2a3](https://github.com/whatiskadudoing/koe/commit/964f2a3588fdfef39f5f95048ea09082233956d1))


### Bug Fixes

* improve Best mode status text in explanation screen ([52e00aa](https://github.com/whatiskadudoing/koe/commit/52e00aac4e83ec19d31522d9b5991dc0d0674f86))

## [1.9.0-beta.6](https://github.com/whatiskadudoing/koe/compare/v1.8.0-beta.6...v1.9.0-beta.6) (2026-01-09)


### Features

* background model system and improved onboarding ([a36a93a](https://github.com/whatiskadudoing/koe/commit/a36a93ae55d2823ddb9ac1e041ae1a3efdaaa582))

## [1.7.0](https://github.com/whatiskadudoing/koe/compare/v1.6.0...v1.7.0) (2026-01-09)


### Features

* add model precompilation to installer for instant app startup ([265b63b](https://github.com/whatiskadudoing/koe/commit/265b63b78935a603d26897a586ad655a4e300005))

## [1.6.0](https://github.com/whatiskadudoing/koe/compare/v1.5.0...v1.6.0) (2026-01-09)


### Features

* AI text refinement with pipeline data tracking ([#37](https://github.com/whatiskadudoing/koe/issues/37)) ([10aaa7b](https://github.com/whatiskadudoing/koe/commit/10aaa7bf5ed2404a84f99af9589ab4aa0b758f2c))


### Bug Fixes

* add llama.xcframework with Git LFS ([1b03684](https://github.com/whatiskadudoing/koe/commit/1b0368417ef33f9f718880ddf2f86a3006848a04))
* add missing .gitmodules and format installer ([d79ca70](https://github.com/whatiskadudoing/koe/commit/d79ca709c9cc4c2fa140740314f1e59e88a42d11))
* CI build issues ([286c80a](https://github.com/whatiskadudoing/koe/commit/286c80a07cc0d24cacf01656fb97c44c02c44813))
* remove WhisperMetal dependency ([b3ed81e](https://github.com/whatiskadudoing/koe/commit/b3ed81eae8fe5d5484169d19d6bbc843aa53efa7))

## [1.5.0](https://github.com/whatiskadudoing/koe/compare/v1.4.11...v1.5.0) (2026-01-08)


### Features

* add development workflow automation ([#34](https://github.com/whatiskadudoing/koe/issues/34)) ([c565f98](https://github.com/whatiskadudoing/koe/commit/c565f98780eb7321028890c0e6cf118ada11d517))
* Meeting Recording & Mode Coordination System ([#36](https://github.com/whatiskadudoing/koe/issues/36)) ([5b9c6f6](https://github.com/whatiskadudoing/koe/commit/5b9c6f6af099600b4d6ab64d1b22e8c3f933a422))

## [1.4.11](https://github.com/whatiskadudoing/koe/compare/v1.4.10...v1.4.11) (2026-01-07)


### Bug Fixes

* add stable designated requirement for TCC recognition ([fd28786](https://github.com/whatiskadudoing/koe/commit/fd2878668e5cdd5503d53110f06baa62ea3f4ff6))

## [1.4.10](https://github.com/whatiskadudoing/koe/compare/v1.4.9...v1.4.10) (2026-01-07)


### Bug Fixes

* add TCC reset and accessibility usage description ([3915c43](https://github.com/whatiskadudoing/koe/commit/3915c4304433636faac08b9d4c02b1125556450d))

## [1.4.9](https://github.com/whatiskadudoing/koe/compare/v1.4.8...v1.4.9) (2026-01-07)


### Bug Fixes

* use CGEvents for all text typing instead of clipboard ([95bb246](https://github.com/whatiskadudoing/koe/commit/95bb24650082171a5757e8235b9aafe0a9f9b9e8))

## [1.4.8](https://github.com/whatiskadudoing/koe/compare/v1.4.7...v1.4.8) (2026-01-07)


### Bug Fixes

* add entitlements and auto-relaunch for accessibility permission ([193f791](https://github.com/whatiskadudoing/koe/commit/193f79153a16b209c096128a1e51f9e233d638fd))

## [1.4.7](https://github.com/whatiskadudoing/koe/compare/v1.4.6...v1.4.7) (2026-01-07)


### Bug Fixes

* sign app bundle with correct bundle identifier ([254faf5](https://github.com/whatiskadudoing/koe/commit/254faf53acce6a92eb22f1eedbdb639303c59be4)), closes [#15](https://github.com/whatiskadudoing/koe/issues/15)

## [1.4.6](https://github.com/whatiskadudoing/koe/compare/v1.4.5...v1.4.6) (2026-01-07)


### Bug Fixes

* refresh permissions when app gains focus ([609a3a6](https://github.com/whatiskadudoing/koe/commit/609a3a64930c0b6fcf57e6894e7a4c56d529466d))
* revert to original simple clipboard paste approach ([60d559e](https://github.com/whatiskadudoing/koe/commit/60d559ec6d2c997d94d67c1e0c6efe7807b33cf8))

## [1.4.5](https://github.com/whatiskadudoing/koe/compare/v1.4.4...v1.4.5) (2026-01-07)


### Bug Fixes

* improve clipboard paste timing for large text ([0871dfb](https://github.com/whatiskadudoing/koe/commit/0871dfba833c6d323eabb8bd39c32e241f3fcce6))

## [1.4.4](https://github.com/whatiskadudoing/koe/compare/v1.4.3...v1.4.4) (2026-01-07)


### Bug Fixes

* handle large transcripts with chunked clipboard paste ([#16](https://github.com/whatiskadudoing/koe/issues/16)) ([ac6044f](https://github.com/whatiskadudoing/koe/commit/ac6044fa7e161b1084b7c19258a59e516b2d903f)), closes [#15](https://github.com/whatiskadudoing/koe/issues/15)

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
