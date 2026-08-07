# Are.na Screensaver

A macOS screensaver that shows images from public [Are.na](https://www.are.na/) channels using the [Are.na v3 API](https://www.are.na/developers/explore) and the native [Screen Saver framework](https://developer.apple.com/documentation/screensaver).

## Features

- Displays images from one or multiple public Are.na channels.
- Supports flexible ordering, timing, orientation filters, and layouts.
- Includes custom background colors and optional image titles.
- Keeps playback steady across multiple displays and brief connection interruptions.

## How it works

The screensaver loads image blocks from the Are.na API. It mixes selected channels, avoids recent repeats, and prepares each image before display.

It saves channel data and images for playback during brief network interruptions.

## Build and install

### Requirements:

- macOS 13 or later
- [Xcode](https://apps.apple.com/us/app/xcode/id497799835) with the macOS SDK

### Install the screensaver for the current user:

1. Clone this repository and run `./scripts/install.sh`
2. Open **System Settings > Screen Saver**
3. Select **Are.na** in the **Other** section

The install script builds a universal bundle for Apple silicon and Intel Macs, installing the bundle here:

```text
~/Library/Screen Savers/ArenaScreenSaver.saver
```

To build without installation, run:

```sh
./scripts/build.sh
```

The release bundle appears at `build/Build/Products/Release/ArenaScreenSaver.saver`.


## Development

Start the preview app:

```sh
./scripts/preview.sh
```

The preview app uses the same view and settings as the screensaver. Run the command again after each code change.

Run the test suite:

```sh
swift test
```

The tests cover API responses, channel input, rotation, pagination, retries, offline fallback, and disk-cache behavior.

## Uninstall

Remove the installed bundle:

```sh
rm -rf "$HOME/Library/Screen Savers/ArenaScreenSaver.saver"
```

Then sign out and sign in again, or restart the Mac.

## License

Are.na Screensaver is available under the [MIT License](LICENSE).
