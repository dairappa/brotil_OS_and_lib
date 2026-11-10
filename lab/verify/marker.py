# バイナリ内に修正で追加されたエラーコード名があるかを見る（攻撃データは使わない）
import sys, glob, re
for pat in sys.argv[1:]:
    for p in sorted(glob.glob(pat)):
        d = open(p, 'rb').read()
        base = b'FORMAT_EXUBERANT_NIBBLE' in d          # Brotliデコーダを含む目印
        fix = sorted(set(m.decode() for m in re.findall(rb'[A-Z_]*BLOCK_SWITCH[A-Z_]*', d)))
        print(f"   {p.split('/')[-1][:48]:<48} decoder={'yes' if base else 'no ':<3} BLOCK_SWITCH marker={fix or 'none'}")
