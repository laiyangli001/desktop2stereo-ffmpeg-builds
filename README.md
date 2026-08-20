# Desktop2Stereo FFmpeg Builds

Reproducible GitHub Actions builds of FFmpeg for Desktop2Stereo. Local developer machines do not need a compiler, MSYS2, Vulkan SDK, or codec development packages.

## Build targets

- Windows amd64: Vulkan Video, NVENC, AMF, oneVPL/QSV, x264, x265, Opus, SRT
- Linux amd64: Vulkan Video, NVENC, oneVPL/QSV, x264, x265, Opus, SRT
- Linux arm64: Vulkan Video, x264, x265, Opus, SRT
- macOS amd64/arm64: VideoToolbox, x264, x265, Opus, SRT

The release package contains FFmpeg/ffprobe together with shared FFmpeg libraries, headers, pkg-config metadata, build information, configuration, and licenses. These SDK files are required by the Desktop2Stereo in-process Vulkan encoding bridge. Every GitHub Release also includes a source archive generated from the exact pinned FFmpeg commit used for the binaries.

## Run a remote build

Open **Actions → Build FFmpeg → Run workflow** and select a target. The first implementation milestone is `Windows-amd64`; use `all` after each target is green.

With GitHub CLI:

```powershell
gh workflow run build.yml --repo laiyangli001/desktop2stereo-ffmpeg-builds -f target=Windows-amd64
gh run list --repo laiyangli001/desktop2stereo-ffmpeg-builds --workflow build.yml
```

Download a successful test artifact from the Actions page. Tagged builds are published as GitHub Releases.

## Licensing

The build scripts are MIT licensed. Distributed FFmpeg binaries use a GPL configuration because libx264 and libx265 are enabled. Public builds never enable `--enable-nonfree`. Every release must include the exact source references, configure output, dependency versions, patches, and applicable license texts.
