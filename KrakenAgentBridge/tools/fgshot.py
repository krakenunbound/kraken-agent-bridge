"""Capture the Fantasy Grounds window's own image to fgshot.png, even if other
windows cover it (PrintWindow with PW_RENDERFULLCONTENT). Optional crop box:
python fgshot.py x0 y0 x1 y1"""
import ctypes, sys
from pathlib import Path
from ctypes import wintypes
from PIL import Image
user32, gdi32 = ctypes.windll.user32, ctypes.windll.gdi32
user32.SetProcessDPIAware()
HERE = Path(__file__).resolve().parent
# tools/ sits next to server/ inside the KrakenAgentBridge extension folder. Needs Pillow (pip install pillow).
sys.path.insert(0, str(HERE.parent / "server"))
import fgu_mcp
# --role client captures the player window instead of the GM's.
ROLE = "host"
if "--role" in sys.argv:
    i = sys.argv.index("--role")
    ROLE = sys.argv[i + 1]
    del sys.argv[i:i + 2]
h = fgu_mcp.find_fg_window(ROLE)
if not h:
    raise SystemExit("Fantasy Grounds window not found")
r = wintypes.RECT()
user32.GetWindowRect(h, ctypes.byref(r))
w, hgt = r.right - r.left, r.bottom - r.top
hdc = user32.GetWindowDC(h)
mdc = gdi32.CreateCompatibleDC(hdc)
bmp = gdi32.CreateCompatibleBitmap(hdc, w, hgt)
gdi32.SelectObject(mdc, bmp)
ok = user32.PrintWindow(h, mdc, 2)

class BITMAPINFOHEADER(ctypes.Structure):
    _fields_ = [("biSize", wintypes.DWORD), ("biWidth", wintypes.LONG), ("biHeight", wintypes.LONG),
                ("biPlanes", wintypes.WORD), ("biBitCount", wintypes.WORD), ("biCompression", wintypes.DWORD),
                ("biSizeImage", wintypes.DWORD), ("biXPelsPerMeter", wintypes.LONG), ("biYPelsPerMeter", wintypes.LONG),
                ("biClrUsed", wintypes.DWORD), ("biClrImportant", wintypes.DWORD)]
bi = BITMAPINFOHEADER(ctypes.sizeof(BITMAPINFOHEADER), w, -hgt, 1, 32, 0, 0, 0, 0, 0, 0)
buf = ctypes.create_string_buffer(w * hgt * 4)
gdi32.GetDIBits(mdc, bmp, 0, hgt, buf, ctypes.byref(bi), 0)
img = Image.frombuffer("RGB", (w, hgt), buf, "raw", "BGRX", 0, 1)
gdi32.DeleteObject(bmp); gdi32.DeleteDC(mdc); user32.ReleaseDC(h, hdc)
if len(sys.argv) == 5:
    img = img.crop(tuple(map(int, sys.argv[1:5])))
img.save(HERE / "fgshot.png")
print("PrintWindow ok" if ok else "PrintWindow failed", img.size)
