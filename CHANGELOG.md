# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0]
### Added
- Base schema now has `has_many :versions`
- Version schema swapped its simple `:entity_id` field for a `belongs_to` which achieves the same, plus adding the `:entity` field and the ability to query with the assoc.
- Added `Versioned.Absinthe.versioned_object` absinthe helper which creates the base object and the versioned one at the same time.
- Added `Versioned.get_last` which fetches the last version record in a history.

### Changed

- `Versioned.with_versions` became `Versioned.with_version_id`. I originally named the function incorrectly ;)

## [0.1.0] - 2021-07-15
### Added
- Initial release
