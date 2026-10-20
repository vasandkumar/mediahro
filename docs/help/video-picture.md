---
ids: [VID-037, VID-038, VID-039]
---
# Adjusting the picture

In the player, tap **Picture** (the palette or paintbrush button at the top) to adjust how the video looks. The changes apply straight away, while the video plays.

## This video

These settings are remembered for the video you're watching, and come back the next time you open it:

- **Aspect ratio:** Original uses the file's own shape. Choose 16:9, 4:3, 21:9, 2.35:1, 1.85:1 or 1:1 for a video that looks stretched or squashed.
- **Fit to screen**, **Fill screen** or **Stretch:** show the whole picture with black bars, fill the screen by cutting off the edges, or stretch the picture to the screen's shape. On a phone or tablet, pinch out to fill the screen and pinch in to fit it again.
- **Zoom:** from 50 % to 400 %, to crop black bars or look closer.
- **Left and right**, **Up and down:** once part of the picture is cut off by zoom or Fill screen, move it to show the part you want.
- **Rotate:** turns the picture a quarter turn each time, for phone videos recorded sideways.
- **Mirror** and **Upside down:** flip the picture.

**Reset** puts this video back the way the file has it.

## Quality

These apply to every video:

- **Scaling:** how the picture is enlarged or shrunk to fit your screen. The sharper methods need more of the graphics processor.
- **Deinterlacing:** smooths the comb-like lines of old TV recordings. Automatic only does it for videos that need it.
- **Smooth banding:** smooths the visible steps in skies and dark gradients.
- **Sharpen:** makes edges crisper; a little goes a long way.

## Colour

Brightness, contrast, saturation, gamma and hue, each from −100 to 100. **Reset** puts them all back to 0. For HDR videos, **HDR on this screen** chooses how bright highlights are fitted to your screen (see [HDR video](hdr-video.md)).

## Smooth motion

**Smooth motion** blends neighbouring frames so the video moves evenly on screens whose refresh rate doesn't match the video, for example a 24 fps film on a 60 Hz screen. It is off by default. On phones and tablets it keeps the graphics processor busier and uses noticeably more battery, so Mediahro asks before turning it on.

## Shaders

Shaders are small programs, written by enthusiasts, that upscale or clean up the picture on the graphics processor. Mediahro uses mpv's `.glsl` user-shader format.

Mediahro comes with these:

- **Anime4K A**, **B** and **C**, for animation: A sharpens blurry anime, B cleans up heavily compressed anime, and C upscales clean anime. Each comes in a fast and a best version; choose fast on phones and older computers.
- **FSR**, sharp upscaling for any video.
- **Film grain**, a subtle, moving grain for a film look; it can also hide banding in dark scenes.

You can add other shaders, such as NNEDI3 or SSimSuperRes, from a folder of your own:

1. Put the `.glsl` files in a folder on your device.
2. In **Picture → Shaders**, tap **Choose a shader folder** and pick that folder.
3. Choose a shader from the list. **None** turns shaders off.

The shader you choose stays on for every video until you change it. Shaders are read from your device's own storage; folders from cloud or network locations can't be used. Demanding shaders can make playback stutter on slower devices: if that happens, choose **None**.

## When the device is hot

Shaders and smooth motion work the graphics processor hard. When your device gets hot, or battery saver (Low Power Mode, Energy Saver) is on, Mediahro pauses them and tells you, so the video keeps playing smoothly. They come back on by themselves once the device has cooled down or battery saver is off.
