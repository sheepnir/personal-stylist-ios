# Garment photo reference contract (#215)

## Representation

| Field | Role |
|---|---|
| `GarmentEntity.imagePath` | Stable UI/DTO key used by `StubGarment` and `UserGarmentPhotoStore`. Values are `user-photo:{uuid}` (→ `Documents/GarmentPhotos/{uuid}.jpg`) or bundled fixture relative paths. |
| `pending-photo:{uuid}` | D-73 in-flight camera capture only (PendingCapture `masterURI`). Same on-disk file as `user-photo:{uuid}`. Commit promotes the URI to `user-photo:`; abandon/clear/reset delete the file. |
| `GarmentImageEntity.originalURI` | Relational photo row; for the **primary** image this string **mirrors** `imagePath` exactly. |
| `GarmentImageEntity.processedURI` | Optional derived/processed file ref (capture pipeline). |

## After migration

- Existing `Documents/GarmentPhotos` files remain reachable via the unchanged `imagePath` string.
- →V2 `didMigrate` runs `GarmentPhotoReferenceReconciliation`: if `imagePath` is set and no primary `GarmentImageEntity` exists, one is inserted with `originalURI = imagePath`.
- Capture work (#191) extends `GarmentImageEntity`; do not remove `imagePath` until all readers use the relational row.

## Schema versions

See `Persistence/SwiftData/SchemaVersions.swift`.
