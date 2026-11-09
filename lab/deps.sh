. /lab/aptfix.sh >/dev/null 2>&1
apt-get install -y -qq python3-brotli python3-pil python3-pycurl curl python3-pip fonts-dejavu-core >/dev/null 2>&1
unset https_proxy HTTPS_PROXY
m(){ python3 -c "$1"'
print(sorted({l.split()[-1] for l in open("/proc/self/maps") if "brotli" in l.lower()}) or "NONE")'; }
echo "## python3-brotli の _brotli.so の動的リンク先"; ldd /usr/lib/python3/dist-packages/_brotli*.so | grep -iE 'brotli|libc\.' ; apt-cache show python3-brotli | grep -m1 '^Depends'
echo "## python3-urllib3 / python3-requests の依存関係（brotli関連）"; for p in python3-urllib3 python3-requests; do echo "$p: $(apt-cache show $p | grep -m3 -E '^(Depends|Recommends|Suggests)' | grep -io '[^ ,]*brotli[^ ,]*' | tr '\n' ' ')  $(apt-cache show $p | grep -m3 -E '^(Recommends|Suggests)' | grep -i brotli | cut -d: -f1)"; done
echo "## libbrotli1 に依存する主なパッケージ（逆依存）"; apt-cache rdepends libbrotli1 | sed 1,2d | sort -u | tr -d ' ' | tr '\n' ' '; echo
echo "## ldd: libcurl / libfreetype / Pillow(apt)"; for f in /usr/lib/x86_64-linux-gnu/libcurl.so.4 /usr/lib/x86_64-linux-gnu/libfreetype.so.6; do echo "$f -> $(ldd $f | grep -io 'libbrotli[a-z]*' | sort -u | tr '\n' ' ')"; done
echo "## 実行時: apt版Pillowでフォント読込 → libbrotliがロードされるか"; m 'from PIL import ImageFont; ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 12)'
echo "## 実行時: pycurl (ACCEPT_ENCODING未指定 / 指定)"; m 'import pycurl,io
b=io.BytesIO();c=pycurl.Curl();c.setopt(c.URL,"http://127.0.0.1:8765/");c.setopt(c.WRITEDATA,b);c.perform();print("default:",b.getvalue())
b=io.BytesIO();c.setopt(c.WRITEDATA,b);c.setopt(c.ACCEPT_ENCODING,"");c.perform();print("ACCEPT_ENCODING=\"\":",b.getvalue())'
echo "## curl CLI --compressed"; curl -s --compressed http://127.0.0.1:8765/; echo; curl -V | grep -o 'brotli/[0-9.]*'
echo "## pip版Pillow（wheel同梱ライブラリ）"; pip install -q --break-system-packages --target /pp pillow >/dev/null 2>&1; ls /pp/pillow.libs/ | grep -i -E 'brotli|freetype'
