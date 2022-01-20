# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic
Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.3] - 2022-01-20
## Added

- `Versioned.insert!/2`, `Versioned.update!/2` and `Versioned.delete!/2` for
  better mimicking `Ecto.Repo`.

## [0.3.2] - 2021-12-09
## Changed

- Fix for `add_versioned_column/4`.
- Better clarity and bugfixes around the fact that there should be no foreign
  key constraints in the versions tables. If you are using this library in
  production, you should be aware that your versions tables may have foreign key
  constraints where they were not intended. If you have any foreign keys in your
  versions tables, use something like the following for each in a new `change/0`
  migration function to get back on track.

```
execute(
  "ALTER TABLE cars_versions DROP CONSTRAINT cars_versions_garage_id_fkey;",
  "ALTER TABLE cars_versions ADD CONSTRAINT cars_versions_garage_id_fkey FOREIGN KEY (garage_id) REFERENCES garages(id);"
)
```

## [0.3.1] - 2021-12-08
## Added

- `Versioned.Migration.rename_versioned_table`

## Changed

- Fixed `Versioned.Migration.remove_versioned_column`.

## [0.3.0] - 2021-11-29
## Added

- `Versioned.get_by/2`
- `Versioned.one/2`
- `Versioned.Multi` now exposes operations for `Ecto.Multi` transactions.
- `Ecto.Schema.version` macro for writing code to the auto-generated
  ".Version" module.

## Changed

- `Versioned.get/2` is now a direct proxy for your `MyApp.Repo.get/2`.

## [0.2.1] - 2021-09-04
## Added

- `Versioned.add_version_id/1` fills the `:version_id` of a versioned struct.
- `:version_fields` option for `versioned_object/3` macro.
- `Versioned.Migration.modify_versioned_column/4`.
- `Versioned.Migration.rename_versioned_column/3`.
- `Versioned.Migration.remove_versioned_column/2`.

## [0.2.0] - 2021-07-26
### Added
- Base schema now has `has_many :versions`
- Version schema swapped its simple `:entity_id` field for a `belongs_to` which
  achieves the same, plus adding the `:entity` field and the ability to query
  with the assoc.
- Added `Versioned.Absinthe.versioned_object/2` absinthe helper which creates
  the base object and the versioned one at the same time.
- Added `Versioned.get_last/3` which fetches the last version record in a
  history.

### Changed

- `Versioned.with_versions` became `Versioned.with_version_id`. I originally
  named the function incorrectly ;)

## [0.1.0] - 2021-07-15
### Added
- Initial release
