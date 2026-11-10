# 共有ライブラリが自己申告するBrotliのバージョン (BrotliDecoderVersion) を表示
import ctypes, sys, glob
for pat in sys.argv[1:]:
    for p in sorted(glob.glob(pat)):
        v = ctypes.CDLL(p).BrotliDecoderVersion()
        print(f"   {p} -> BrotliDecoderVersion = {v>>24}.{(v>>12)&0xfff}.{v&0xfff}")
