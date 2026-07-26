# Immich Screensaver

A Windows screensaver that displays photos from your own [Immich](https://immich.app/) server —
with real **multi-monitor support**, album selection and a settings page.

Written in **Lazarus 4 / Free Pascal 3.2.2**.

## Features

- 🖥️ **Multiple monitors** – every selected screen gets its own fullscreen window showing a
  *different* photo, instead of one photo stretched across the whole desktop.
- ⚙️ **Settings page** for server, API key, speed, random mode, image source, monitor selection
  and display mode.
- 🗂️ **Album selection** – albums are loaded straight from Immich; pick any combination, or use
  the entire library.
- 🔀 **Random or sequential** order.
- 🖼️ **Display modes**: fill (crop), fit (letterbox) or stretch.
- 🌫️ **Smooth crossfade** between images, with a configurable duration.
- 🕒 **Clock and date overlay**, and you can place it in any of the four corners.
- ⚡ **Fast startup and smooth playback** – images are prefetched on a background thread, so the
  network never blocks the animation.
- 🔐 Settings are stored per user in `%APPDATA%\ImmichScreensaver\`.

## Requirements

- Windows (x86_64)
- A reachable [Immich](https://immich.app/) instance and an **API key**
  (in Immich: *Account Settings → API Keys*)
- The two OpenSSL DLLs `libssl-1_1-x64.dll` and `libcrypto-1_1-x64.dll` next to the `.scr`
  (needed for HTTPS). They are included in this repository — see
  [OpenSSL DLLs](#openssl-dlls) if you want to supply them yourself.

## Installation

Get the source from [github.com/xchimx/ImmichScreensaver](https://github.com/xchimx/ImmichScreensaver):

```bash
git clone https://github.com/xchimx/ImmichScreensaver.git
```

1. Download or build `ImmichScreensaver.scr` and place it — **together with both DLLs** — in a
   permanent folder (for example `C:\Tools\ImmichScreensaver\`).
2. Right-click the `.scr` file → **Install** (or pick it under *Settings → Personalization →
   Lock screen → Screen saver*).
3. Open **Settings** to enter your server URL and API key.

> Note: if you copy the `.scr` into `C:\Windows\System32\`, the DLLs have to be found there as
> well (or somewhere on the `PATH`).

## Configuration

The settings page can be opened in three ways:

- the **Settings** button in the Windows screensaver dialog,
- right-click the `.scr` file → **Configure**, or
- from the command line:

```bash
ImmichScreensaver.scr /c
```

Available options: server URL, API key (with a *Test connection* button), interval (speed),
random order, display mode, full resolution, crossfade (on/off plus duration), clock and date
(on/off plus position), **albums** (multi-select, nothing checked = whole library) and
**monitors** (multi-select, nothing checked = all monitors).

### Command line parameters

| Parameter | Meaning |
|-----------|---------|
| `/s` | Run the screensaver (fullscreen) |
| `/c` | Open the settings page |
| _(no parameter)_ | Open the settings page — Windows' "Configure" verb passes no arguments |
| `/p` | Preview (not supported, exits immediately) |

> To test fullscreen mode, start it with `/s`. Without a parameter you get the settings page.

### Configuration file

Stored at `%APPDATA%\ImmichScreensaver\immich_config.ini`.
A template is provided in [`immich_config.ini.example`](immich_config.ini.example).

> ⚠️ Your real `immich_config.ini` contains your **API key** and is excluded via `.gitignore`.
> Never commit it.

## Usage

Any mouse movement, click or key press ends the screensaver (after a short grace period so it
does not close itself immediately on startup).

## OpenSSL DLLs

HTTPS requests need OpenSSL. Free Pascal 3.2.2 loads these exact file names on 64-bit Windows:

```
libssl-1_1-x64.dll
libcrypto-1_1-x64.dll
```

Both files are included in this repository (version **1.1.1w**), so you normally do not have to
do anything.

If you prefer to obtain them yourself, take the **OpenSSL 1.1.1 series for Win64**, for example:

- [FireDaemon OpenSSL](https://kb.firedaemon.com/support/solutions/articles/4000121705) —
  prebuilt Windows binaries, includes 1.1.1w
- [Overbyte ICS](https://wiki.overbyte.eu/wiki/index.php/ICS_Download) — ships OpenSSL binaries
  for Delphi/Pascal projects
- [openssl-library.org](https://openssl-library.org/source/old/1.1.1/index.html) — official
  sources if you want to compile them yourself

After downloading, copy the two DLLs next to `ImmichScreensaver.scr`.

> **Important:** it has to be the **1.1.1 series** — FPC 3.2.2 does not load OpenSSL 3.x
> (the file names differ). Note that OpenSSL 1.1.1 reached end-of-life in September 2023;
> 1.1.1w is the last public release.

The bundled DLLs are © The OpenSSL Project and are distributed under the OpenSSL / original
SSLeay dual license. The full license text is included in
[`third-party/OPENSSL-1.1.1w-LICENSE.txt`](third-party/OPENSSL-1.1.1w-LICENSE.txt).

## Building

With Lazarus 4 / FPC 3.2.2 installed:

```bash
lazbuild --build-mode=Release ImmichScreensaver.lpi
```

The result is `ImmichScreensaver.scr` (a post-build step copies the `ImmichScreensaver.scr.exe`
produced by FPC to `ImmichScreensaver.scr`, because FPC always appends `.exe`).

There is also a `Debug` build mode which produces `ImmichScreensaver-debug.exe`.

## Project structure

| File | Contents |
|------|----------|
| `ImmichScreensaver.lpr` | Program entry point |
| `ucontroller.pas` | Controller: mode detection, window creation, image cycling |
| `uscreenwin.pas` | Fullscreen window per monitor, drawing and crossfade |
| `uproducer.pas` | Background thread that prefetches images |
| `uimmich.pas` | Immich API client (albums, asset lists, downloads) |
| `uconfig.pas` | Loading and saving the settings (INI) |
| `usettings.pas` | Settings dialog |
| `uabout.pas` | About dialog |

## License

The project code is licensed under the [MIT License](LICENSE) — free to use, modify and share.

The bundled OpenSSL binaries (`libssl-1_1-x64.dll`, `libcrypto-1_1-x64.dll`) are **not** part of
this project's code. They are © The OpenSSL Project and remain under their own
[OpenSSL / SSLeay dual license](third-party/OPENSSL-1.1.1w-LICENSE.txt).

## Author

Created by **Tobias Schottstädt** — [www.schottstaedt.net](https://www.schottstaedt.net/)

This project is not affiliated with the Immich project. Immich is developed at
[immich.app](https://immich.app/).
