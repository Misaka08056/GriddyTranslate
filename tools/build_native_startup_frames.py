"""Package the already approved Godot splash frames for the Win32 launcher.

This is a developer tool; neither Python, FFmpeg nor these libraries ship in
the portable application. Windows' built-in WIC decoder plays the frame pack.
"""
from pathlib import Path
import argparse
import json
import struct
import sys


def main():
    root = Path(__file__).resolve().parent.parent
    sys.path.insert(0, str(root / "qa" / "video-tools"))
    import av
    import cv2

    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, default=root / "qa" / "cybertranslator-preview" / "cybertranslator-startup.mp4")
    parser.add_argument("--output", type=Path, default=root / "tools" / "native-startup.frames")
    parser.add_argument("--frames-json", type=Path, help="Use pre-rendered, approved HD JPEGs directly")
    options = parser.parse_args()
    frames = []
    width = height = 0
    if options.frames_json:
        from fractions import Fraction
        import numpy as np
        rate = Fraction(30, 1)
        for entry in json.loads(options.frames_json.read_text(encoding="utf-8-sig")):
            path = options.frames_json.parent / entry["file"]
            if path.suffix.lower() in (".jpg", ".jpeg"):
                jpeg = path.read_bytes()
            else:
                success, encoded = cv2.imencode(".jpg", cv2.imread(str(path)), [cv2.IMWRITE_JPEG_QUALITY, 97])
                if not success:
                    raise RuntimeError("Could not encode startup frame")
                jpeg = encoded.tobytes()
            pixels = cv2.imdecode(np.frombuffer(jpeg, dtype="uint8"), cv2.IMREAD_COLOR)
            height, width = pixels.shape[:2]
            frames.append(jpeg)
    else:
      with av.open(str(options.input)) as movie:
        stream = movie.streams.video[0]
        rate = stream.average_rate
        for frame in movie.decode(stream):
            pixels = frame.to_ndarray(format="bgr24")
            height, width = pixels.shape[:2]
            success, jpeg = cv2.imencode(".jpg", pixels, [
                cv2.IMWRITE_JPEG_QUALITY, 97,
                cv2.IMWRITE_JPEG_OPTIMIZE, 1,
                cv2.IMWRITE_JPEG_SAMPLING_FACTOR, cv2.IMWRITE_JPEG_SAMPLING_FACTOR_444,
            ])
            if not success:
                raise RuntimeError("Could not encode startup frame")
            frames.append(jpeg.tobytes())
    if width * 9 != height * 16 or width < 640 or len(frames) != 330:
        raise RuntimeError("Expected the approved 16:9, eleven-second splash")
    header = struct.pack("<8sIIIII", b"CYBRF01\0", width, height,
                         rate.numerator, rate.denominator, len(frames))
    first = len(header) + 4 * (len(frames) + 1)
    offsets = [first]
    for jpeg in frames:
        offsets.append(offsets[-1] + len(jpeg))
    options.output.write_bytes(header + struct.pack("<" + "I" * len(offsets), *offsets) + b"".join(frames))
    print(f"{options.output}: {len(frames)} frames, {width}x{height}, {rate} fps, {offsets[-1]} bytes")


if __name__ == "__main__":
    main()
