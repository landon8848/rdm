// Single source of truth for the build/version string.
// Bumping this is the documented force-update lever: the service worker
// derives its cache name from it, so a new value invalidates the old
// app-shell cache on the next load. Shown in the UI footer for testers.
export const APP_VERSION = '0.2.0+5';
