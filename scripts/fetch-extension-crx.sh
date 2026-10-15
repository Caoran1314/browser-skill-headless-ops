#!/bin/sh
# Download the BrowserSkill extension from the Chrome Web Store and unpack the CRX3
# into a plain directory that Chromium can load with --load-extension.
#
# Usage: fetch-extension-crx.sh [out-dir] [extension-id]
#   out-dir         default: $HOME/bsk-ext        (unpacked extension lands in <out>/ext)
#   extension-id    default: hhcmgoofomhgciiibhipgmgkgnoenaoi (Chrome Web Store)
#                   Edge Add-ons id:  emacgiaaaiojkkpkddmmdfhmokgmnikg
# Env: PRODV (browser version sent to the store, default 141.0.0.0), https_proxy/http_proxy
set -eu

OUT=${1:-"${BSK_EXT_DIR:-$HOME/bsk-ext}"}
ID=${2:-hhcmgoofomhgciiibhipgmgkgnoenaoi}
PRODV=${PRODV:-141.0.0.0}

mkdir -p "$OUT"
URL="https://clients2.google.com/service/update2/crx?response=redirect&os=linux&arch=x86_64&os_arch=x86_64&nacl_arch=x86-64&prod=chromiumcrx&prodchannel=unknown&prodversion=${PRODV}&acceptformat=crx3&x=id%3D${ID}%26uc"

echo "==> downloading CRX (id=$ID)" >&2
curl -fsSL -A "Mozilla/5.0" "$URL" -o "$OUT/extension.crx" || {
  echo "download failed — check network/proxy; Edge id only works when the Edge store is reachable" >&2
  exit 1
}

python3 - "$OUT" <<'PY'
import io, json, os, sys, zipfile

out = sys.argv[1]
data = open(os.path.join(out, "extension.crx"), "rb").read()
if data[:4] != b"Cr24":
    sys.exit("not a CRX (magic %r) — the store returned HTML or an error page" % data[:4])
version = int.from_bytes(data[4:8], "little")
if version not in (2, 3):
    sys.exit("unsupported CRX version %d" % version)

# CRX3 = "Cr24" | version | protobuf header length | header | ZIP payload.
# CRX2 = "Cr24" | version | pubkey len | sig len | pubkey | sig | ZIP payload.
if version == 3:
    header_len = int.from_bytes(data[8:12], "little")
    payload = data[12 + header_len:]
else:
    pub_len = int.from_bytes(data[8:12], "little")
    sig_len = int.from_bytes(data[12:16], "little")
    payload = data[16 + pub_len + sig_len:]

offset = payload.find(b"PK\x03\x04")
if offset < 0:
    sys.exit("no ZIP payload found in CRX")

ext = os.path.join(out, "ext")
os.makedirs(ext, exist_ok=True)
zipfile.ZipFile(io.BytesIO(payload[offset:])).extractall(ext)

manifest = json.load(open(os.path.join(ext, "manifest.json")))
print("extension %s %s mv %s -> %s" % (
    manifest.get("name"), manifest.get("version"), manifest.get("manifest_version"), ext))
PY
