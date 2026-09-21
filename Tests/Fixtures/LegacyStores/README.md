# Legacy SwiftData store packages (#215)

Each subdirectory is a store package named after `LegacyStoreFixtureID`
(`PersonalStylistLocal.store` inside).

Regenerate with `LegacyStoreFixtures.generate(id:at:)`. Tests prefer a bundled copy when present;
otherwise they generate into a temp directory. Used by `SchemaMigrationTests`
and later by #220.
