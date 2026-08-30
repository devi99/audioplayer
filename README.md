# audioplayer

A cross-platform audio player designed for Linux, Windows, and Android.

The app is structured around a Flutter UI layer and a shared music-library API client. It can:

- connect to a `musiclibrary.api` endpoint and load decoded audio streams
- browse a library by tag and artist/album metadata
- filter a queue using rating and tag selection
- scroll through track lists and queue matching tracks for playback

## Repository layout

- `lib/` – Flutter UI and screen models
- `src/` – reusable TypeScript queue and API logic used to validate the core behavior
- `tests/` – Node-based tests for the library and queue logic

## Validation

Run the shared logic tests with:

```bash
npm install
npm test
```

This project is intentionally shaped around a Flutter interface while keeping the playlist and filtering logic easy to validate and reuse across desktop and mobile targets.
