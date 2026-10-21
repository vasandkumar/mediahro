# Writes a synthetic 75-frame HDR10+ (profile B) metadata JSON in hdr10plus_tool's schema.
import json, sys
out = sys.argv[1]
N = 75
CUT = 38
def frame(i):
    scene = 0 if i < CUT else 1
    first = 0 if scene == 0 else CUT
    bright = scene == 1
    return {
        "BezierCurveData": {
            "Anchors": [143, 298, 447, 592, 731, 864, 891, 917, 938],
            "KneePointX": 164,
            "KneePointY": 240,
        },
        "LuminanceParameters": {
            "AverageRGB": 1200 if bright else 263,
            "LuminanceDistributions": {
                "DistributionIndex": [1, 5, 10, 25, 50, 75, 90, 95, 99],
                "DistributionValues": [0, 600, 1200, 2400, 4800, 7000, 8000, 9000, 9500] if bright
                                      else [0, 6080, 92, 1, 4, 107, 726, 1784, 5843],
            },
            "MaxScl": [50000, 50000, 50000] if bright else [7768, 6589, 6912],
        },
        "NumberOfWindows": 1,
        "TargetedSystemDisplayMaximumLuminance": 400,
        "SceneFrameIndex": i - first,
        "SceneId": scene,
        "SequenceFrameIndex": i,
    }
doc = {
    "JSONInfo": {"HDR10plusProfile": "B", "Version": "1.0"},
    "SceneInfo": [frame(i) for i in range(N)],
    "SceneInfoSummary": {"SceneFirstFrameIndex": [0, CUT], "SceneFrameNumbers": [CUT, N - CUT]},
    "ToolInfo": {"Tool": "hand-written", "Version": "0"},
}
with open(out, "w") as f:
    json.dump(doc, f, indent=2)
