# My Music Player Project Context

## Overview
My Music Player is a premium, high-performance music player built with Flutter, designed specifically for Subsonic-compatible servers (Navidrome, Airsonic, etc.). The app focuses on a sleek, iOS-inspired aesthetic with smooth animations and deep integration with the Subsonic API.

## Core Architecture
*   **State Management**: `flutter_riverpod` with code generation (`riverpod_generator`).
    *   `PlayerProvider`: Manages playback state, queue, and playback controls.
    *   `LibraryProvider`: Handles data fetching for home, albums, and playlists.
    *   `SearchProvider`: Manages search state and debounced API calls.
*   **Navigation**: `go_router` for declarative routing.
*   **Persistence**: `shared_preferences` for storing server credentials and user settings.

## Services
### SubsonicService (`lib/services/subsonic_service.dart`)
Acts as the API client for the Subsonic server.
*   **Authentication**: Uses MD5-based token authentication (`password + salt`).
*   **Key Methods**:
    *   `ping()`: Connectivity check.
    *   `getStreamUrl(songId)`: Audio source URL.
    *   `getCoverArtUrl(id)`: Artwork URL.
    *   `getRandomSongs()`, `getRecentlyPlayedAlbums()`, `getAlbum(id)`.
    *   `star()`, `unstar()`, `scrobble()`: User interactions.
    *   `search(query)`: Unified search for songs, albums, and artists.

### AudioHandler (`lib/services/audio_handler.dart`)
Wraps `just_audio` and handles background playback integration.
*   Uses `ConcatenatingAudioSource` for seamless queue transitions.
*   Integrates with `just_audio_background` for system media controls.
*   **Smart Shuffle**: Includes Standard, Balanced (by Composer/Genre), and Weighted algorithms.

## Design System (`lib/core/theme.dart`)
*   **Aesthetics**: Deep black backgrounds (`#000000`), Apple-style surface levels, and vibrant accent colors (Electric Blue, Gold).
*   **Typography**: Uses `Inter` for main UI and `Space Grotesk` for technical/metadata elements (via Google Fonts).
*   **Custom Components**:
    *   `CupertinoClickable`: A wrapper providing iOS-style scale-down animations on tap.
    *   `MiniPlayer`: Persistent playback control bar.
    *   `ProgressBar`: Custom seek bar using `audio_video_progress_bar`.

## Data Models
*   `Song`: Represents a track with metadata (title, artist, album, genre, composer) and duration.
*   `Album`: Represents a collection of tracks with cover art.
*   `Playlist`: Represents user-created collections.

## Key Screens
*   `HomeScreen`: Featured and recently played content.
*   `NowPlayingScreen`: Detailed playback view with artwork and controls.
*   `LibraryScreen`: Access to playlists, starred items, and albums.
*   `SearchScreen`: Global search with real-time results.
