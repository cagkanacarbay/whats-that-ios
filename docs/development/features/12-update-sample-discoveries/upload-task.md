# Upload Task: Replace Sample Discoveries (22 entries)

Migration file: `supabase/migrations/20260220102531_replace_sample_discoveries_v2.sql`

---

## Step 1: Run the migration

Run against both **dev** (`cywshvmspnvimucwqarc`) and **prod** (`vipghlhvnrdheoydynty`).

---

## Step 2: Upload images

Upload each image to the `discovery_images` bucket at path `samples/{n}.jpg`.

Old samples (1-7) will be overwritten. Positions 8-22 are net new uploads.

| Upload to | Source DB | Source ID | Title | Source image |
|-----------|-----------|-----------|-------|-------------|
| `samples/1.jpg` | dev | 265 | The Last Senate | `discoveries_dev/265-the-last-senate/image.jpg` |
| `samples/2.jpg` | dev | 322 | House of the Black Heads | `discoveries_dev/322-house-of-the-black-heads/image.jpg` |
| `samples/3.jpg` | dev | 177 | Inferno in the Palace | `discoveries_dev/177-inferno-in-the-palace/image.jpg` |
| `samples/4.jpg` | dev | 296 | The Empress's Pink Stone | `discoveries_dev/296-the-empresss-pink-stone/image.jpg` |
| `samples/5.jpg` | dev | 174 | The Doge's Giant Ego | `discoveries_dev/174-the-doge-s-giant-ego/image.jpg` |
| `samples/6.jpg` | dev | 219 | Accidental Sticky Notes | `discoveries_dev/219-accidental-sticky-notes/image.jpg` |
| `samples/7.jpg` | prod | 1618 | Feast in the House of Levi | `discoveries_prod/1618-feast-in-the-house-of-levi/image.jpg` |
| `samples/8.jpg` | dev | 316 | Ghetto Heroes Monument | `discoveries_dev/316-ghetto-heroes-monument/image.jpg` |
| `samples/9.jpg` | dev | 183 | The Winged Hussars | `discoveries_dev/183-the-winged-hussars/image.jpg` |
| `samples/10.jpg` | dev | 134 | The Merchant's Moral Map | `discoveries_dev/134-the-merchant-s-moral-map/image.jpg` |
| `samples/11.jpg` | dev | 309 | The Arm of a Saint | `discoveries_dev/309-the-arm-of-a-saint/image.jpg` |
| `samples/12.jpg` | dev | 229 | Trakai's Diverse Streets | `discoveries_dev/229-trakais-diverse-streets/image.jpg` |
| `samples/13.jpg` | prod | 1771 | Sobieski at Vienna | `discoveries_prod/1771-sobieski-at-vienna/image.jpg` |
| `samples/14.jpg` | dev | 40 | Polyxena Sarcophagus | `discoveries_dev/040-polyxena-sarcophagus/image.jpg` |
| `samples/15.jpg` | dev | 237 | Palace of Culture | `discoveries_dev/237-palace-of-culture/image.jpg` |
| `samples/16.jpg` | dev | 125 | The Price of Fire | `discoveries_dev/125-the-price-of-fire/image.jpg` |
| `samples/17.jpg` | dev | 57 | A Map to the Afterlife | `discoveries_dev/057-a-map-to-the-afterlife/image.jpg` |
| `samples/18.jpg` | dev | 261 | Ornate Wheellock | `discoveries_dev/261-ornate-wheellock/image.jpg` |
| `samples/19.jpg` | dev | 307 | The Wood Inlays of Frari | `discoveries_dev/307-the-wood-inlays-of-frari/image.jpg` |
| `samples/20.jpg` | dev | 173 | The Rebel Monk Methodius | `discoveries_dev/173-the-rebel-monk-methodius/image.jpg` |
| `samples/21.jpg` | dev | 298 | Rundāle Palace | `discoveries_dev/298-rundle-palace/image.jpg` |
| `samples/22.jpg` | dev | 199 | Stoves of Rundāle | `discoveries_dev/199-stoves-of-rund-le/image.jpg` |

---

## Step 3: Upload voiceovers

Upload each voiceover to the `voiceovers` bucket at path `samples/{n}.mp3`.

### Already have voiceovers (10) — download from source DB and re-upload to samples/

| Upload to | Source DB | Source ID | Voiceover ID | Title |
|-----------|-----------|-----------|-------------|-------|
| `samples/2.mp3` | dev | 322 | 182 | House of the Black Heads |
| `samples/7.mp3` | prod | 1618 | 165 | Feast in the House of Levi |
| `samples/8.mp3` | dev | 316 | 188 | Ghetto Heroes Monument |
| `samples/10.mp3` | dev | 134 | 22 | The Merchant's Moral Map |
| `samples/11.mp3` | dev | 309 | 195 | The Arm of a Saint |
| `samples/13.mp3` | prod | 1771 | 291 | Sobieski at Vienna |
| `samples/14.mp3` | dev | 40 | 9 | Polyxena Sarcophagus |
| `samples/16.mp3` | dev | 125 | 11 | The Price of Fire |
| `samples/19.mp3` | dev | 307 | 198 | The Wood Inlays of Frari |
| `samples/20.mp3` | dev | 173 | 214 | The Rebel Monk Methodius |

### Need to generate voiceovers (12)

| Upload to | Source DB | Source ID | Title |
|-----------|-----------|-----------|-------|
| `samples/1.mp3` | dev | 265 | The Last Senate |
| `samples/3.mp3` | dev | 177 | Inferno in the Palace |
| `samples/4.mp3` | dev | 296 | The Empress's Pink Stone |
| `samples/5.mp3` | dev | 174 | The Doge's Giant Ego |
| `samples/6.mp3` | dev | 219 | Accidental Sticky Notes |
| `samples/9.mp3` | dev | 183 | The Winged Hussars |
| `samples/12.mp3` | dev | 229 | Trakai's Diverse Streets |
| `samples/15.mp3` | dev | 237 | Palace of Culture |
| `samples/17.mp3` | dev | 57 | A Map to the Afterlife |
| `samples/18.mp3` | dev | 261 | Ornate Wheellock |
| `samples/21.mp3` | dev | 298 | Rundāle Palace |
| `samples/22.mp3` | dev | 199 | Stoves of Rundāle |

---

## Step 4: Verify

- [ ] Open the app as a logged-out user
- [ ] Confirm all 22 tiles load with correct images and titles
- [ ] Tap a few discoveries and confirm descriptions render correctly
- [ ] Play audio on at least 2-3 discoveries to verify voiceovers work
- [ ] Verify grid order matches the layout (The Last Senate top-left, Stoves of Rundāle bottom-right)

---

## Step 5: Clean up old storage (optional)

The old samples used the same `samples/` folder with positions 1-7. Positions 1-7 are now overwritten with new content. No orphaned files to clean up unless there were extra assets beyond the 7 originals.

---

## Grid Layout Reference

```
Row 1:  [The Last Senate]              [House of the Black Heads]
Row 2:  [Inferno in the Palace]        [The Empress's Pink Stone]
Row 3:  [The Doge's Giant Ego]         [Accidental Sticky Notes]
Row 4:  [Feast in the House of Levi]   [Ghetto Heroes Monument]
Row 5:  [The Winged Hussars]            [The Merchant's Moral Map]
Row 6:  [The Arm of a Saint]           [Trakai's Diverse Streets]
Row 7:  [Sobieski at Vienna]           [Polyxena Sarcophagus]
Row 8:  [Palace of Culture]            [The Price of Fire]
Row 9:  [A Map to the Afterlife]       [Ornate Wheellock]
Row 10: [The Wood Inlays of Frari]     [The Rebel Monk Methodius]
Row 11: [Rundāle Palace]               [Stoves of Rundāle]
```
