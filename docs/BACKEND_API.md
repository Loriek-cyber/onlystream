# OnlyStream Backend API Specification (`v1.0.0`)

This document describes the complete HTTP and Android companion contract required to implement a custom backend service compatible with **OnlyStream** (such as `easystreamapi` or any alternative server written in Rust, Go, Python, Node.js, etc.).

## General Conventions

- **Base URL**: Configurable in OnlyStream Settings (default `http://127.0.0.1:5555` on Android local mode, `http://localhost:5555` on desktop).
- **Content-Type**: JSON (`application/json`) for all API endpoints except `/stream/hls/...` (`application/vnd.apple.mpegurl`) and `/stream/torrent/...` (`video/*` with RFC 9110 `Range` support).
- **CORS**: Permissive (`Access-Control-Allow-Origin: *`) recommended for web/desktop clients.
- **Trailing Slashes**: Routes should normalize/ignore trailing slashes.
- **Unified Catalog IDs**: Movies, TV shows, and Anime all share a single ID space (`kind`: `"movie"` | `"tv"`, tagged with `is_anime: boolean` — e.g. TMDB IDs). Do **not** expose separate ID spaces for anime.
- **Languages**: Clients send `lang=it` or `lang=en`.
- **Errors**: Return appropriate HTTP `4xx`/`5xx` status with JSON body:
  ```json
  { "error": "Human-readable error message" }
  ```

---

## 1. Health & Runtime Provider URLs

### `GET /health`
Used by OnlyStream to verify server connectivity and measure latency.

**Response `200 OK`:**
```json
{
  "status": "ok",
  "service": "my-stream-backend",
  "version": "1.0.0"
}
```

### `GET /config/sources`
Returns the active upstream provider base URLs and their startup/environment defaults.

**Response `200 OK`:**
```json
{
  "sources": {
    "vixsrc_url": "https://vixsrc.to",
    "animeunity_url": "https://animeunity.cx",
    "animeworld_url": "https://www.animeworld.ac",
    "corsaro_url": "https://icv.stremio-italia.eu",
    "torrentio_url": "https://torrentio.strem.fun"
  },
  "defaults": {
    "vixsrc_url": "https://vixsrc.to",
    "animeunity_url": "https://animeunity.cx",
    "animeworld_url": "https://www.animeworld.ac",
    "corsaro_url": "https://icv.stremio-italia.eu",
    "torrentio_url": "https://torrentio.strem.fun"
  }
}
```

### `PUT /config/sources`
Updates one or more upstream provider base URLs at runtime, clears affected provider caches, and persists overrides (e.g. `data_dir/sources.json`). Passing an empty string `""` for a field resets that field to its default. Non-`http://`/`https://` URLs return `400 Bad Request`.

**Request Body (partial):**
```json
{
  "vixsrc_url": "https://vixsrc.custom.example",
  "animeunity_url": "https://animeunity.so"
}
```
**Response `200 OK`:** same shape as `GET /config/sources`.

### `DELETE /config/sources`
Resets all provider base URLs back to defaults/environment values.

**Response `200 OK`:** same shape as `GET /config/sources`.

---

## 2. Discovery & Unified Search

### `GET /search`
Query parameters:
- `q` (required): search text, numeric catalog ID, or IMDb ID (`tt...`).
- `type` (optional): `all` | `movie` | `tv` | `anime` (default `all`).
- `lang` (optional): `it` | `en` (default `it`).

**Response `200 OK`:** `MediaSummary[]`
```json
[
  {
    "id": 1396,
    "kind": "tv",
    "is_anime": false,
    "title": "Breaking Bad",
    "original_title": "Breaking Bad",
    "overview": "Un professore di chimica...",
    "year": "2008",
    "rating": 8.9,
    "poster": "https://image.tmdb.org/t/p/w500/...",
    "backdrop": "https://image.tmdb.org/t/p/w1280/..."
  }
]
```

### `GET /discover`
Query parameters:
- `category` (required): `trending` | `movies` | `tv` | `anime`.
- `genre` (optional): genre slug or ID.
- `lang` (optional): `it` | `en`.
- `page` (optional): positive integer (default `1`).

**Response `200 OK`:** `MediaSummary[]`

### `GET /genres`
**Response `200 OK`:**
```json
[
  { "slug": "action", "label": "Azione" },
  { "slug": "animation", "label": "Animazione" }
]
```

---

## 3. Media Metadata

### `GET /media/{kind}/{id}`
Path parameters:
- `kind`: `movie` | `tv`
- `id`: integer media ID

Query parameters:
- `lang` (optional): `it` | `en`

**Response `200 OK`:** `MediaDetail`
```json
{
  "id": 1396,
  "kind": "tv",
  "is_anime": false,
  "title": "Breaking Bad",
  "original_title": "Breaking Bad",
  "overview": "...",
  "year": "2008",
  "rating": 8.9,
  "status": "Ended",
  "runtime": 47,
  "genres": ["Dramma", "Crime"],
  "poster": "https://...",
  "backdrop": "https://...",
  "seasons": [
    {
      "season_number": 1,
      "name": "Stagione 1",
      "episode_count": 7,
      "air_date": "2008-01-20",
      "poster": "https://..."
    }
  ],
  "library": null
}
```
> If the item is already tracked in the backend's library, include its `LibraryItemView` object in `"library"`.

### `GET /media/tv/{id}/season/{season}`
Query parameters:
- `lang` (optional): `it` | `en`

**Response `200 OK`:** `SeasonDetail`
```json
{
  "season_number": 1,
  "name": "Stagione 1",
  "episodes": [
    {
      "episode_number": 1,
      "name": "Questione di chimica",
      "overview": "...",
      "air_date": "2008-01-20",
      "runtime": 58,
      "still": "https://image.tmdb.org/t/p/w500/...",
      "watched": false
    }
  ]
}
```

---

## 4. Stream Resolution & Playback

### `GET /stream/resolve/{kind}/{id}`
Single endpoint called by OnlyStream before starting playback or switching language/quality/source.

Query parameters:
- `season` (default `1`, used for `tv`)
- `episode` (default `1`, used for `tv`)
- `lang`: `it` | `en`
- `quality`: `auto` | `2160p` | `1080p` | `720p`
- `source`: `auto` | `hls` | `torrent`

**Response `200 OK`:** `ResolvedStream`
```json
{
  "id": 1396,
  "kind": "tv",
  "is_anime": false,
  "title": "Breaking Bad",
  "season": 1,
  "episode": 1,
  "recommended_mode": "hls",
  "recommended_url": "/stream/hls/tv/1396?season=1&episode=1&lang=it&quality=1080p",
  "recommended_info_hash": null,
  "hls": {
    "source": "vixsrc",
    "playlist_url": "https://cdn.example/master.m3u8",
    "referer": "https://provider.example/",
    "audio": [
      { "language": "ita", "name": "Italiano", "url": "https://..." }
    ],
    "subtitles": [
      { "language": "ita", "name": "Italiano", "url": "https://..." }
    ],
    "video": [
      { "quality": "1080p", "resolution": "1920x1080", "bandwidth": 4500000, "url": "https://..." }
    ]
  },
  "torrents": [
    {
      "title": "Breaking.Bad.S01E01.1080p.ITA.ENG.mkv",
      "filename": "Breaking.Bad.S01E01.1080p.ITA.ENG.mkv",
      "info_hash": "6a12ce77043c07604314f30fa62f2b17ea8d4ab9",
      "magnet": "magnet:?xt=urn:btih:6a12ce77043c07604314f30fa62f2b17ea8d4ab9",
      "quality": "1080p",
      "seeders": 120,
      "size_bytes": 2147483648,
      "file_idx": 0,
      "languages": ["ita", "eng"],
      "source_indexer": "Torrentio",
      "cached": false,
      "stream_url": "/stream/torrent/6a12ce77043c07604314f30fa62f2b17ea8d4ab9?file_idx=0&season=1&episode=1"
    }
  ],
  "next_episode": {
    "season": 1,
    "episode": 2,
    "name": "Senza ritorno",
    "still": "https://...",
    "air_date": "2008-01-27"
  }
}
```

**Important Notes:**
- `recommended_url` and `torrents[].stream_url` may be **server-relative paths** (`/stream/...`) — OnlyStream automatically resolves them against the configured server `baseUrl` so LAN and localhost work seamlessly.
- If `hls.referer` is present, OnlyStream forwards it as an HTTP `Referer` header to `media_kit`.
- When `recommended_mode` is `"torrent"`, populate `recommended_info_hash` with the 40-char hex info-hash so OnlyStream can stop it immediately on exit.

### `GET /stream/hls/{kind}/{id}`
Returns an `application/vnd.apple.mpegurl` M3U8 playlist (optionally filtered to `quality`). Accepts `season`, `episode`, `lang`, `quality`.

### `GET /stream/torrent/{info_hash}`
Streams the selected video file over HTTP with **RFC 9110 `Range: bytes=start-end`** (`206 Partial Content`, `Accept-Ranges: bytes`, `Content-Range`, `Content-Length`).
Query parameters: `file_idx`, `season`, `episode`, `magnet` (optional).
Recommended response header: `x-torrent-infohash: <40-hex>`.

---

## 5. Torrent Lifecycle Management

OnlyStream calls these endpoints whenever the user closes the player, switches episode/source, or backgrounds the app so P2P downloads **do not keep running**.

- `GET /torrents` -> `200 OK`: array of active torrent statuses.
- `GET /torrents/{info_hash}` -> `200 OK`: status for one torrent.
- `DELETE /torrents/{info_hash}` -> `200 OK` (must be **idempotent**): immediately stop the torrent, cancel any background tasks, and delete temporary data.
  ```json
  { "status": "stopped", "info_hash": "6a12ce77043c07604314f30fa62f2b17ea8d4ab9" }
  ```
- `DELETE /torrents` -> `200 OK`: stop and delete all active torrents.

> Backends should also implement an idle reaper (e.g., stop & remove torrents with 0 active HTTP streams after ~8–10 seconds) and disable `fastresume` so crashed sessions never resume downloading on restart.

---

## 6. Library, Watch Progress & Tracked Series

### `LibraryItemView` Schema
```json
{
  "id": 1396,
  "kind": "tv",
  "is_anime": false,
  "title": "Breaking Bad",
  "poster": "https://...",
  "backdrop": "https://...",
  "year": "2008",
  "status": "watching",
  "current_season": 1,
  "current_episode": 2,
  "position_secs": 340,
  "duration_secs": 2800,
  "watched_episodes": ["S01E01"],
  "preferred_lang": "it",
  "updated_at": "2026-11-23T15:00:00Z",
  "next_episode": {
    "season": 1,
    "episode": 2,
    "name": "Senza ritorno",
    "still": "https://...",
    "air_date": "2008-01-27"
  },
  "has_new_episodes": false,
  "new_episodes_count": 0,
  "latest_aired_season": 5,
  "latest_aired_episode": 16
}
```
- `status`: `"watching"` | `"saved"` | `"completed"`
- `watched_episodes`: array of episode keys formatted as `"S01E01"` (zero-padded).

### `GET /library?lang=it|en`
Returns all tracked items grouped for the UI:
```json
{
  "continue_watching": [ /* LibraryItemView */ ],
  "saved": [ /* LibraryItemView */ ],
  "completed": [ /* LibraryItemView */ ],
  "items": [ /* LibraryItemView */ ]
}
```

### `GET /library/updates?lang=it|en`
Returns `LibraryItemView[]` for tracked TV series where `has_new_episodes == true`.

### `PUT /library/{kind}/{id}`
Add or update a tracked item.

**Request Body:**
```json
{
  "is_anime": false,
  "title": "Breaking Bad",
  "poster": "https://...",
  "backdrop": "https://...",
  "year": "2008",
  "status": "saved",
  "current_season": 1,
  "current_episode": 1,
  "preferred_lang": "it"
}
```
**Response `200 OK`:** `LibraryItemView`

### `DELETE /library/{kind}/{id}`
**Response `200 OK`:** `{ "deleted": true }`

### `POST /library/{kind}/{id}/progress?lang=it|en`
Called periodically during playback and on pause/close.

**Request Body:**
```json
{
  "is_anime": false,
  "title": "Breaking Bad",
  "poster": "https://...",
  "backdrop": "https://...",
  "year": "2008",
  "season": 1,
  "episode": 1,
  "position_secs": 1200,
  "duration_secs": 2800,
  "preferred_lang": "it"
}
```
**Recommended Backend Behavior:**
- If `duration_secs > 0` and `position_secs / duration_secs >= 0.92`:
  - For TV: add `"SxxEyy"` to `watched_episodes`, reset `position_secs = 0`, and advance `current_season`/`current_episode` to the next episode (or set `status = "completed"` if at the final episode).
  - For Movie: set `status = "completed"` and `position_secs = 0`.
- **Response `200 OK`:** updated `LibraryItemView`.

### `POST /library/{kind}/{id}/watched?lang=it|en`
Manually mark an episode watched or unwatched.

**Request Body:**
```json
{
  "season": 1,
  "episode": 1,
  "watched": true,
  "is_anime": false,
  "title": "Breaking Bad",
  "poster": "https://...",
  "backdrop": "https://...",
  "year": "2008"
}
```
**Response `200 OK`:** updated `LibraryItemView`.

---

## 7. Optional Android Companion Server Contract

If you also package your backend as a standalone Android companion APK (running locally on `http://127.0.0.1:5555`), OnlyStream integrates with it automatically when the companion app uses:

- **Package ID**: `com.loriek.easystreamserver`
- **Local HTTP endpoint**: `http://127.0.0.1:5555`
- **Exported BroadcastReceiver Actions**:
  - `com.loriek.easystreamserver.ACTION_START` — starts the foreground server service
  - `com.loriek.easystreamserver.ACTION_STOP` — stops the foreground server service
- **Android 10+ (API 29+) W^X Compliance**: if bundling a native executable (Rust/Go), name it `lib<name>.so` inside `jniLibs/<abi>/`, set `android:extractNativeLibs="true"` in `AndroidManifest.xml`, and launch it from `applicationInfo.nativeLibraryDir`.
