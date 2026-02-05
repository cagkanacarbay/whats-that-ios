# Sample Assets for Pre-Onboarding

Upload these to Supabase Storage before running the migration.

## ID Mapping

| Sample ID | Original ID | Title | Source |
|-----------|-------------|-------|--------|
| 1 | 126 | Klimt's Golden Muse | Dev |
| 2 | 1565 | Venice's Winged Brand | Prod |
| 3 | 1570 | A Nation's Golden Anchor | Prod |
| 4 | 1618 | Feast in the House of Levi | Prod |
| 5 | 1640 | Venice's Golden Ascent | Prod |
| 6 | 1681 | The General of Vítkov | Prod |
| 7 | 1771 | Sobieski at Vienna | Prod |

## Storage Destinations

### Images
Upload `images/*.jpg` to: `discovery_images/samples/`

```
discovery_images/samples/1.jpg
discovery_images/samples/2.jpg
...
discovery_images/samples/7.jpg
```

### Voiceovers
Upload `voiceovers/*.mp3` to: `voiceovers/samples/`

```
voiceovers/samples/1.mp3
voiceovers/samples/2.mp3
...
voiceovers/samples/7.mp3
```

## Checklist

- [ ] Upload images to `discovery_images/samples/`
- [ ] Upload voiceovers to `voiceovers/samples/`
- [ ] Verify public read access on storage buckets
- [ ] Run database migration
