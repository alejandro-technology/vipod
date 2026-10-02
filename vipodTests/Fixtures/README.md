# Audio test fixture

`VIPOD-TestTone.mp3` is a deterministic one-second 440 Hz sine tone generated locally with ffmpeg's `sine` source and libmp3lame encoder. Its ID3 title, artist, and album tags are synthetic test metadata. No third-party audio or recording is used. Regenerate with:

```sh
/opt/homebrew/bin/ffmpeg -f lavfi -i 'sine=frequency=440:duration=1' -ar 44100 -ac 1 -codec:a libmp3lame -b:a 64k -metadata title='VIPOD Test Tone' -metadata artist='VIPOD Test Suite' -metadata album='Synthetic Fixtures' VIPOD-TestTone.mp3
```

`VIPOD-ArtworkTone.m4a` is a three-second synthetic tone with an embedded red JPEG cover. The presentation tests import it through the real repository and check the rendered cover pixels, track changes, and playback updates. Regenerate with:

```sh
ffmpeg -f lavfi -i 'sine=frequency=440:duration=3' -f lavfi -i 'color=c=red:s=64x64' -map 0:a -map 1:v -c:a aac -b:a 64k -c:v mjpeg -frames:v 1 -disposition:v attached_pic -metadata title='VIPOD Artwork Tone' -metadata artist='VIPOD Test Suite' -metadata album='Synthetic Fixtures' VIPOD-ArtworkTone.m4a
```
