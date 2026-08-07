# Are.na Screensaver Roadmap

# MVP

## V1 implementation slices

- [x] Slice 1: Expand the API model, add presentation controls, show attribution, and finish preview behavior.
- [x] Slice 2: Add pagination, balanced channel rotation, ordering, orientation filters, repeat prevention, and refresh.
- [x] Slice 3: Preload and decode images before they are needed, and skip broken images without interrupting playback.
- [x] Slice 4: Replace the implicit URL cache with a persistent content index, managed disk cache, cache controls, and retry handling.
- [ ] Slice 5: Harden sleep, wake, network changes, long sessions, and multiple-display behavior.
- [ ] Source release: Confirm that a clean checkout builds and installs with one command, then publish the GitHub instructions.

## 1. Presentation polish

- [x] Add an adjustable crossfade duration.
- [x] Display the channel name and creator attribution. (only when "show titles" preference is selected)
- [x] Add reduced-motion support. (Stack uses cuts; Crossfade uses a short opacity transition.)

## 2. Content rotation

- [x] Preload the next image.
- [x] Request blocks after the first 50 items.
- [x] Prevent recent images from repeating.
- [x] Mix multiple channels evenly.
- [x] Add newest, oldest, channel-order, and random sort modes.
- [x] Filter landscape, portrait, and square images.
- [x] Refresh channels periodically without a restart.

## 3. Reliability and performance

- [x] Add a persistent offline content index.
- [x] Add a cache-size setting.
- [x] Add a clear-cache button.
- [x] Display an error for each failed channel.
- [x] Add retry and rate-limit handling.
- [x] Skip broken images without a visible delay.
- [x] Decode large images away from the main thread.
- [x] Limit memory use during long sessions.
- [ ] Test sleep, wake, network changes, and multiple displays.








# FUTURE ROADMAP

## Creative experiments

- [ ] Add collage and grid layouts.
- [ ] Create diptychs from two channels.
- [ ] Display text blocks as occasional interludes.
- [ ] Display videos and animated images.
- [ ] Add slow spatial-canvas layouts.
- [ ] Select image transitions from dominant colors.
- [ ] Add channel schedules for different times of day.
- [ ] Use channel connections to create generative journeys.


## Polished Distribution

- [ ] Better name? Interesting alternatives include: Channel Drift, Block Party, Idle Blocks, Are.na After Dark, Channel Surfing
- [ ] Add a screen-saver icon and catalog thumbnail.
- [ ] Sign releases with a Developer ID certificate.
- [ ] Notarize releases with Apple.
- [ ] Create an installer package or disk image.
- [ ] Add uninstall instructions.
- [ ] Publish versioned releases.
- [ ] Test compatibility with macOS 13 through macOS 26.
- [ ] Add a companion app for installation and updates.



## ?? Multiple displays

- [ ] Display a different image on each display.
- [ ] Display one synchronized image on all displays.
- [ ] Span one image across multiple displays.
- [ ] Add fit and fill settings for each display.
- [ ] Prevent duplicate downloads between displays.


## ?? Private channels

- [ ] Add Are.na OAuth with PKCE.
- [ ] Use read-only access by default.
- [ ] Store access tokens in Keychain.
- [ ] Add sign-in and sign-out controls.
- [ ] Display private-channel status.
- [ ] Handle revoked access tokens.


## ?? Preview and development tools

- [ ] Add pause, previous, and next controls.
- [ ] Simulate portrait and ultrawide displays.
- [ ] Display network and offline status.
- [ ] Add a current-block metadata inspector.
- [ ] Improve code and settings reload behavior.
- [ ] Capture screenshots from the preview app.
- [ ] Add a debug-log viewer.
