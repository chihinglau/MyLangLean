# -*- coding: utf-8 -*-
"""Build a tiny black-video + sample-audio MP4 for on-device verification
(AC-6: the app plays the audio track of an imported video and drives the
word-level subtitles without rendering video)."""
import sys

import av
import numpy as np

SRC = r"app/assets/audio/sample.mp3"
DST = r".tools/studio-out/sample-black.mp4"


def main() -> None:
    in_c = av.open(SRC)
    out = av.open(DST, "w")

    vstream = out.add_stream("libx264", rate=24)
    vstream.width = 320
    vstream.height = 180
    vstream.pix_fmt = "yuv420p"
    vstream.options = {"crf": "28", "preset": "veryfast"}

    astream_in = in_c.streams.audio[0]
    astream = out.add_stream("aac", rate=astream_in.rate)
    astream.layout = "stereo"

    duration = float(in_c.duration / av.time_base) if in_c.duration else 18.0
    n_frames = int(duration * 24)
    black_rgb = np.zeros((180, 320, 3), dtype=np.uint8)

    for _ in range(n_frames):
        vf = av.VideoFrame.from_ndarray(
            black_rgb, format="rgb24").reformat(format="yuv420p")
        for packet in vstream.encode(vf):
            out.mux(packet)
    for packet in vstream.encode():
        out.mux(packet)

    for frame in in_c.decode(audio=0):
        for packet in astream.encode(frame):
            out.mux(packet)
    for packet in astream.encode():
        out.mux(packet)

    out.close()
    in_c.close()
    print("VIDEO_READY", DST)


if __name__ == "__main__":
    sys.exit(main())
