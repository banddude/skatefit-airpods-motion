#!/usr/bin/env python3
"""Generate the same original 120 mm optical reference image and printable PDF.

No network assets or third-party licensed artwork. Output is deterministic.
The ARReferenceImage uses the entire square at exactly 0.120 m physical width.
"""
from pathlib import Path
from random import Random
from PIL import Image, ImageDraw, ImageFont
from reportlab.pdfgen.canvas import Canvas
from reportlab.lib.utils import ImageReader
from reportlab.lib.units import mm

ROOT = Path(__file__).resolve().parents[1]
IMAGE_SET = ROOT / "SkateMotion/Assets.xcassets/BoardOpticalMarker.imageset"
RESOURCES = ROOT / "SkateMotion/Resources"
IMAGE_SET.mkdir(parents=True, exist_ok=True)
RESOURCES.mkdir(parents=True, exist_ok=True)
IMAGE_PATH = IMAGE_SET / "BoardOpticalMarker.png"
PDF_PATH = RESOURCES / "SkateFit_Board_Tracking_Marker_120mm.pdf"
SIZE = 1024
rng = Random(13042026)
image = Image.new("RGB", (SIZE, SIZE), "white")
d = ImageDraw.Draw(image)
# Distinct high-contrast continuous image with nonrepeating, sharp corners.
d.rectangle((8, 8, 1015, 1015), outline="#071323", width=16)
d.rectangle((35, 35, 988, 988), outline="black", width=7)
n = 34
cell = 26
left = (SIZE - n * cell) // 2
top = (SIZE - n * cell) // 2
for row in range(n):
    for col in range(n):
        x = left + col * cell
        y = top + row * cell
        code = rng.randrange(16)
        if code < 7:
            d.rectangle((x+1, y+1, x+cell-2, y+cell-2), fill=(15,22,34))
        elif code < 10:
            d.ellipse((x+3, y+3, x+cell-4, y+cell-4), fill=(22,34,51))
        elif code < 12:
            d.line((x+2,y+2,x+cell-3,y+cell-3), fill=(12,18,28), width=6)
        elif code < 14:
            d.line((x+cell-3,y+2,x+2,y+cell-3), fill=(12,18,28), width=6)
# Asymmetric central signature allows ARKit to distinguish 0/90/180 degree turns.
d.ellipse((409,409,615,615), fill="white", outline=(10,15,22), width=18)
d.polygon([(512,437),(580,575),(445,554)], fill=(4,9,17))
# Top nose direction stays legible to a person even if computer vision sees only texture.
d.rectangle((282,58,742,136), fill="white", outline="black", width=6)
try:
    font=ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 48)
except OSError:
    font=ImageFont.load_default()
d.text((512,95),"NOSE",fill="black",font=font,anchor="mm")
# Bottom label is asymmetric and part of printed size.
d.rectangle((222,885,802,966), fill="white", outline="black", width=5)
d.text((512,926),"SKATEFIT BOARD V1",fill="black",font=font,anchor="mm")
image.save(IMAGE_PATH,optimize=True)
# Asset catalog metadata included for deterministic XcodeGen builds.
(IMAGE_SET / "Contents.json").write_text(
    '{"images":[{"filename":"BoardOpticalMarker.png","idiom":"universal"}],'
    '"info":{"author":"xcode","version":1}}\n',encoding="utf-8")
# Letter-size portrait. The outer image edges are exactly 120 mm apart at 100% print scale.
page_w,page_h=612,792
canvas=Canvas(str(PDF_PATH),pagesize=(page_w,page_h),pageCompression=1,invariant=1)
canvas.setTitle("SkateFit 120 mm Optical Board Marker")
canvas.setFont("Helvetica-Bold",19)
canvas.drawCentredString(page_w/2,page_h-68,"SkateFit | Board Space Marker")
canvas.setFont("Helvetica",11)
canvas.drawCentredString(page_w/2,page_h-90,"Print at 100% ACTUAL SIZE, never 'Fit to Page'")
side=120*mm
x=(page_w-side)/2
y=(page_h-side)/2+22
canvas.drawImage(ImageReader(image),x,y,width=side,height=side,mask="auto")
canvas.setStrokeColorRGB(0,0,0)
canvas.setLineWidth(1)
canvas.line(64,110,64+50*mm,110)
for at in (0,50*mm):
    canvas.line(64+at,103,64+at,117)
canvas.setFont("Helvetica",9)
canvas.drawString(64,122,"CHECK: this line must measure exactly 50 mm on paper.")
canvas.drawString(64,92,"Attach the 120 mm square rigidly to the nose, clear of shoes and wheels.")
canvas.drawString(64,76,"Keep a tripod-mounted iPhone still and the full marker visible.")
canvas.drawString(64,60,"Camera tracks MARKER position only, not foot or wheel contact.")
canvas.showPage()
canvas.save()
print(f"IMAGE {IMAGE_PATH} ({IMAGE_PATH.stat().st_size} bytes)")
print(f"PDF {PDF_PATH} ({PDF_PATH.stat().st_size} bytes)")
