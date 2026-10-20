---
ids: [IMG-007]
---
# Photos on a map

The **Map** tab shows every photo that carries a GPS position.

## Reading the map

- A round picture is a photo. A number on it says how many photos are close together there. Tap it to zoom in until they separate; when photos are on exactly the same spot, tap opens them as a list.
- Drag to move, pinch (or turn the mouse wheel, or press **+** and **-**) to zoom, double-tap to zoom in one step. The arrow keys move the map. **Show all photos** fits every photo on screen.
- Tap a single photo to open it in the viewer; swiping there goes through the photos that have a location.

## Map pictures are off until you turn them on

Without map pictures the photos sit on a plain grid of latitude and longitude lines. Nothing leaves your device.

**Turn on map pictures** (also in **Privacy → Map tiles**) lets the map ask `tiles.mediahro.com` for the map pictures of the area you look at. Those requests say which map squares you view and carry your IP address; they never include your photos or where they were taken. The map data is © OpenStreetMap contributors. Pictures you have seen are kept on the device (up to 256 MB) so places you visit often work offline. You can turn it off again at any time.

## Place names

Places are found on your device from a bundled list of cities with at least 15,000 people (data from GeoNames, CC BY 4.0). The details sheet of a photo shows the nearest city, and the **Places** tab groups photos by city.

## Setting or removing a location

- **One photo:** Details → **Edit details** → **Choose on map**. Move the map so the pin is where the photo was taken, or search for a city, then **Use this location**. You can also type latitude and longitude.
- **Several photos:** select them, then **More → Set location** or **Remove location**. Mediahro writes the position into each file (or a small `.xmp` file next to camera RAW files). A file it cannot write to is reported; the others are still changed. Videos are skipped.
