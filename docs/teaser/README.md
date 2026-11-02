# Teaser
The animated teaser at the top of the README. `teaser.html` is the source, `teaser.gif` is
rendered from it. The operations on the card are an illustration, not a real result.

| File | Content |
| --- | --- |
| `teaser.html` | The animation, loops when opened, `?t=<ms>` freezes it at one point in time. |
| `teaser.gif` | Rendered from `teaser.html`, embedded in the README. |
| `New-UnwireTeaser.ps1` | Renders every frame with headless Edge and builds `teaser.gif`. |
| `ConvertTo-UnwireGif.ps1` | GIF encoder in PowerShell (palette, LZW), no tool needed. |
| `tests/` | Pester tests of the encoder, decoded back with System.Drawing. |

After a change to `teaser.html` (Windows, Edge installed):
```powershell
./docs/teaser/New-UnwireTeaser.ps1
```
