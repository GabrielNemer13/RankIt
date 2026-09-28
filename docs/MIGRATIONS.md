# Schema migrations

Until this pass, every schema change meant wiping the local store (see git
history before this file existed). That's no longer acceptable once anyone
else has real data in their install, so `RankItApp.swift` now wires a real
`SchemaMigrationPlan`:

- `RankIt/Services/RankItSchema.swift` defines `SchemaV1` (a `VersionedSchema`
  listing the current `@Model` classes) and `RankItMigrationPlan` (currently
  empty `stages`, since there's only one version).
- `RankItApp.swift` builds its `ModelContainer` with
  `Schema(versionedSchema: SchemaV1.self)` and `migrationPlan:
  RankItMigrationPlan.self`.

This alone means SwiftData now tracks a real version identifier in the
store's metadata, instead of none at all.

## Why `SchemaV1` doesn't nest the model types

Apple's usual `VersionedSchema` pattern nests a copy of each `@Model` class
inside the enum (`SchemaV1.Movie`, `SchemaV2.Movie`, ...) with a top-level
`typealias Movie = SchemaV2.Movie` pointing at the latest version. That's
the right call when two schema versions need to represent *different
shapes* of the same model side by side — which is exactly what a rename, a
dropped field, or a relationship restructure needs.

It's overkill for this app's actual pattern so far: every schema change to
date (`Movie.voteAverage`, `Movie.cast`, `Movie.overview`) has been an
additive property with an inline default. SwiftData lightweight-migrates
those automatically — it always has, even before this pass added a formal
migration plan — and doing so has never required two distinct shapes of
`Movie` to exist at once. So `SchemaV1` just lists the existing top-level
classes directly. Zero call sites changed to add this.

**The tradeoff:** if a future change needs the nested pattern anyway — see
below — introducing it at that point *will* touch every file that
references the model being changed, however many that turns out to be at
the time. There was no way to avoid that cost happening eventually without
paying the disruption cost now, for a hypothetical. This pass chose to
defer it.

## Adding SchemaV2: the common case (additive, lightweight)

If the change is one of:

- a new property with an inline default (`var flag: Bool = false`), or
- a new *optional* property (`var note: String?`),
- ...and nothing existing is renamed, retyped incompatibly, or dropped,

then you likely don't need a new `VersionedSchema` at all. Just add the
property to the existing top-level class with an inline default, the same
way `Movie.voteAverage` and `Movie.cast` were added. SwiftData infers the
lightweight migration automatically. `RankItMigrationPlan.stages` stays
empty.

`RankItTests/MigrationPlanTests.swift`'s
`test_additiveOptionalField_migratesLightweight_withoutDataLoss` proves this
pattern end-to-end with a throwaway test-only schema pair (not RankIt's
real models), so you have a working reference if you want to copy its
shape into a real test for your own additive change.

## Adding SchemaV2: the pattern that needs nesting

If the change is a rename, a type change that isn't a safe widen, dropping
a non-optional field, splitting/merging models, or anything else
lightweight migration can't infer, you need a real custom migration stage
— and *that* needs two distinct shapes of the model to exist
simultaneously:

```swift
enum SchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }
    static var models: [any PersistentModel.Type] { [Movie.self, /* ... */] }

    @Model
    final class Movie {
        // the new shape
    }
}
```

At that point, every file that references the model directly needs to
either keep working against `SchemaV1.Movie` (frozen, for the migration
stage's `willMigrate`/`didMigrate` closures) or move to whatever the
"current" type alias resolves to. This is the point where you pay the
disruption cost described above. Do it deliberately, in its own pass, not
mixed into unrelated feature work.

```swift
enum RankItMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self, SchemaV2.self] }
    static var stages: [MigrationStage] {
        [.custom(
            fromVersion: SchemaV1.self,
            toVersion: SchemaV2.self,
            willMigrate: nil,
            didMigrate: { context in /* backfill, transform, etc. */ }
        )]
    }
}
```

## Rules of thumb

- Prefer additive, optional/defaulted fields over anything that needs a
  custom stage — it's strictly cheaper, both to write and to test.
- Never add a `.unique` constraint (CloudKit sync is planned; see the "No
  `.unique`" comments already on every model).
- Test every real migration the way `MigrationPlanTests.swift` does: write
  data through the *old* container, close it, reopen a *new* container at
  the *new* schema against the same store URL, and assert nothing was
  lost. An in-memory store can't prove this — it never persists across two
  separate `ModelContainer` instances.
- Before shipping a schema change, install the previous build, log in,
  create some data, then install the new build over it (not a fresh
  install) and confirm the data survives — the same manual check this pass
  used to verify `RankItMigrationPlan` itself.
