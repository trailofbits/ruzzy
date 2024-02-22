# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Automated tests in CI for real fuzzing runs ([#10](https://github.com/trailofbits/ruzzy/issues/10))

### Changed

- `Ruzzy.c_trace_branch` to `Ruzzy.trace` to simplify interface
- Support for `clang` back to `14.0.6`, and system `clang`, e.g. from `apt` ([#12](https://github.com/trailofbits/ruzzy/pull/12))

## [0.6.0] - 2024-02-13

### Added

- Support for fuzzing pure Ruby code ([#7](https://github.com/trailofbits/ruzzy/issues/7))
- Support for UBSAN ([#5](https://github.com/trailofbits/ruzzy/issues/5))

### Changed

- Relaxed gem Ruby version requirement to >= 3.0.0
- Manual concatenation of `Ruzzy.ext_path` to `Ruzzy::ASAN_PATH` and `Ruzzy::UBSAN_PATH`

## [0.5.0] - 2024-02-02

### Added

- Initial Ruzzy implementation
- Support for fuzzing Ruby C extensions
