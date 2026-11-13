# ConoOS

ConoOS is an operating-system-inspired app that runs inside the system already
installed on your device. It is built with Flutter and does not replace or
modify the host operating system.

## What works in this prototype

- An adaptive dark workspace for mobile and desktop-sized screens.
- App launcher and local search for built-in apps, with a persistent app registry
  defined in the shell.
- Notes saved on-device using app preferences.
- A basic calculator.
- DUO with independently interactive Notes, Calculator, and Cono AI panes,
  side-by-side on wider displays.
- Desktop app windows with drag, resize, minimize, maximize, close, focus, and
  restore from the taskbar.
- Files selection through the host system's file picker.
- A touch drawing canvas with PNG export through the host save dialog.
- Host Bridge shortcuts that users explicitly register and launch.
- Ladybird, an in-app browser with address/search input, history, reload, and
  embedded pages on Android, iOS, macOS, and Windows. Linux opens pages in the
  host browser because the embedded WebView plugin does not support Linux.
- Cono AI chat UI, available from the app launcher and the desktop right-click
  menu. Explicit `open example.com` and `search for ...` commands open Ladybird
  directly through a deterministic user-command handler; normal chat uses the
  selected local Cono Nova model.
- Tier-specific Cono AI daily limits stored on-device: Phone 200, Balanced 150,
  and Large 100 requests.

## JARVIS-style direction

The [referenced video](https://youtu.be/bl9646MVDA4) is a design reference, not
a requirement for voice. ConoOS is intended to be silent and text-first: on
desktop, right-click the workspace and choose **Cono AI** to open its chat, or
open the same app from the normal app launcher. Voice, reminders, screen
awareness, and host-computer control are not implemented.

The model is named **Cono Nova**. Its three randomly initialized Transformer
presets (25M, 38M, and 85M parameters) were each trained for one bounded CPU
epoch and exported as local INT8 ONNX packages. The checkpoint files and OASST1
corpus are ignored by Git and remain on the training machine; import the matching
`.onnx` file in Cono AI to use it. These are experimental starter models, not
capable general-purpose assistants: each run used only 128 training and 128
validation windows from a small corpus. Normal chat uses only the selected local
Cono Nova model, with no hosted-provider or fallback model. The selected tier's
daily limit applies to actual model requests.
The model selector uses one shared daily counter, so switching tiers cannot
reset requests already used that day. Large can be imported as a separate
package, but no download service or signed model release is configured yet.

The request limit is stored locally, so it applies per app installation and can
be reset by clearing app data or reinstalling. Enforcing a limit across
accounts/devices would require an authenticated service, which is not part of
this offline prototype.

Bridge intentionally does not enumerate installed apps: platform permissions
and policies differ, and iOS does not permit general app enumeration. Users
register shortcuts themselves; a shortcut only works if the host platform and
target app support its URL scheme. Ladybird uses the host platform's WebView
(Android WebView, WKWebView, or WebView2), not the separate Ladybird browser
engine. It supports HTTP(S) pages; Linux uses the host browser for HTTPS links.
Plain HTTP pages are not encrypted; use HTTPS where available. Web indexing and
broad host-app discovery are not implemented yet. Search terms are sent to
DuckDuckGo; website requests go directly to the chosen site. ConoOS remains an
app running inside the host OS, not a replacement operating system.

## Download and run on Windows

The Windows build is distributed as a portable ZIP, not an installer. Download
the `windows-x64` ZIP from [GitHub Releases](https://github.com/indven-swe/cono-os/releases),
extract the entire folder, then double-click `cono_os.exe` inside it. Keep the
other files beside the executable; deleting the extracted folder removes the
app. Cono AI also requires importing the matching Cono Nova `.onnx` model from
`training/checkpoints/`; model files are not included in the app ZIP.

Training still needs an approved corpus with enough representative text and
suitable compute. The training command creates a deterministic held-out split. More suitable
training data, longer training, and device evaluation are still needed. Model
size alone does not establish that it will be useful or fit every target device.

Python is used for model training; Flutter/Dart remains the ConoOS app stack.
The corpus and generated checkpoints are intentionally ignored by Git.

## Build and test

With Flutter installed in a suitable development or remote build environment:

```sh
flutter pub get
dart run tool/make_icon.dart
dart run flutter_launcher_icons
flutter analyze --no-fatal-infos
flutter test
flutter build apk --debug
flutter build windows --debug
flutter build linux --debug
```

Platform builds require their corresponding Flutter and native platform
toolchains. The project owner does not need to install these tools locally;
CI or a remote development environment can be used instead. Pull-request CI
runs Flutter analysis/tests, Python model tests, and Android/Windows/Linux debug
builds. Release CI also builds the available mobile and desktop targets.

## Cono AI training

Training requires a local, approved text corpus. Use JSONL with one
`{"text":"..."}` record per line, or a UTF-8 text file with documents separated
by blank lines. Keep private or unlicensed data out of the repository:
`training/data/` and `training/checkpoints/` are ignored by Git.

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r training/requirements.txt
python -m unittest discover -s training/tests
python -m training.prepare_oasst
python -m training.train --dataset training/data/cono-nova-oasst1-en.jsonl --model-size phone-25m
python -m training.train --dataset training/data/cono-nova-oasst1-en.jsonl --model-size balanced-38m
python -m training.train --dataset training/data/cono-nova-oasst1-en.jsonl --model-size large-85m
python -m training.export_onnx --checkpoint training/checkpoints/cono-nova-phone-25m.pt --output training/checkpoints/cono-nova-phone-25m.onnx
python -m training.export_onnx --checkpoint training/checkpoints/cono-nova-balanced-38m.pt --output training/checkpoints/cono-nova-balanced-38m.onnx
python -m training.export_onnx --checkpoint training/checkpoints/cono-nova-large-85m.pt --output training/checkpoints/cono-nova-large-85m.onnx
```

`prepare_oasst` downloads the [OASST1 conversation dataset](https://huggingface.co/datasets/OpenAssistant/oasst1)
(Apache-2.0) into the ignored `training/data/` directory. It keeps reviewed,
English, non-synthetic messages and builds conversations using the highest
ranked human reply. No pretrained model weights are used. You may instead train
on your own JSONL or text corpus.

Training defaults to `phone-25m`. To choose a larger model, pass
`--model-size balanced-38m` or `--model-size large-85m`. Approximate raw FP32
weight sizes are 97 MiB, 145 MiB, and 326 MiB respectively. The exporter
creates INT8 weight-quantized ONNX packages with a fixed 256-token input for
local CPU inference. Phone speed, battery use, and memory have not been
benchmarked; the 85M preset will be considerably heavier on a phone.

Increasing size does not automatically increase intelligence. A larger run
needs more suitable training data and compute, and a trained checkpoint cannot
simply grow in place: the selected architecture must be trained as its own
model. The current byte tokenizer also means the default 256-token context is
only a few dozen words. The filtered OASST1 corpus prepared by this project has
2,116 conversations (about 4 MB), which is a starter dataset, not enough to
claim a generally capable assistant. Training runs or a falling validation
loss do not by themselves establish that the assistant is useful.

For a bounded CPU smoke run, pass `--max-windows 128`; this limits training and
validation to 128 sequence windows each. Leaving it unset uses all available
windows and may take a long time on CPU. A bounded run verifies the pipeline but
is not sufficient training for a useful assistant.

The trainer initializes all weights randomly and saves the best held-out
checkpoint under `training/checkpoints/`. CPU training may be very slow; GPU
availability is detected automatically when using CUDA. The trainer itself
does not download data or use pretrained weights; the separate preparation
command downloads OASST1 from Hugging Face. The exporter produces a
weight-quantized ONNX file with model and preset metadata. In Cono AI, use
**Import model** to select the matching `.onnx` file for the chosen tier; it is
stored in the app's local support directory and inference runs on-device.
