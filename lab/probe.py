import sys, importlib
def maps(): return sorted({l.split()[-1] for l in open('/proc/self/maps') if 'brotli' in l.lower()})
print(f"[py] {sys.executable} {sys.version.split()[0]}")
for m in ('brotli', 'brotlicffi'):
    try: mod = importlib.import_module(m); print(f"[py] import {m}: OK -> {getattr(mod,'__file__','?')}")
    except ImportError as e: print(f"[py] import {m}: NG ({e})")
try:
    import urllib3
    from urllib3.util.request import ACCEPT_ENCODING
    print(f"[py] urllib3 {urllib3.__version__} ACCEPT_ENCODING={ACCEPT_ENCODING!r}")
    r = urllib3.request('GET', 'http://127.0.0.1:8765/')
    print(f"[py] urllib3 br-response decoded: {r.data!r}")
except ImportError: print("[py] urllib3: not installed")
except Exception as e: print(f"[py] urllib3 br-response: ERROR {type(e).__name__}: {e}")
try:
    import requests
    r = requests.get('http://127.0.0.1:8765/')
    print(f"[py] requests sent Accept-Encoding={r.request.headers['Accept-Encoding']!r} body={r.content!r}")
except ImportError: print("[py] requests: not installed")
except Exception as e: print(f"[py] requests: ERROR {type(e).__name__}: {e}")
import urllib.request
print(f"[py] stdlib urllib body(raw)={urllib.request.urlopen('http://127.0.0.1:8765/').read()!r}")
print(f"[py] libbrotli mapped in process: {maps() or 'NONE'}")
