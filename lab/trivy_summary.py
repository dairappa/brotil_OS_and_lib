# Trivy JSON から brotli / node / react 関連だけを抜き出して要約する
import json, sys
KEYS = ('brotli', 'node', 'react')
for path in sys.argv[1:]:
    d = json.load(open(path))
    print(f"######## {d.get('ArtifactName')}   (scanned: {d.get('CreatedAt','')[:10]})")
    for r in d.get('Results', []):
        pkgs, vulns = r.get('Packages', []), r.get('Vulnerabilities', [])
        print(f"  [{r['Class']}/{r['Type']}] {r['Target'][:50]}  packages={len(pkgs)} vulns={len(vulns)}")
        for p in pkgs:
            n = p['Name'].lower()
            if any(k in n for k in KEYS) and 'gyp' not in n:
                print(f"     PKG  {p['Name']} {p['Version']}")
        for v in vulns:
            n = v['PkgName'].lower()
            if any(k in n for k in KEYS) and 'gyp' not in n:
                print(f"     VULN {v['VulnerabilityID']:<16} {v['PkgName']} {v['InstalledVersion']} -> fixed {v.get('FixedVersion','-')}  [{v.get('Severity')}] {v.get('Title','')[:60]}")
