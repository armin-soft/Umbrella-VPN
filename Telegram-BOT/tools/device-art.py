"""Optional developer tool: regenerate bundled schematic artwork (pip install Pillow).
No runtime image service, fonts, personal data or hardware-model guesses are used.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter
import math
OUT = Path(__file__).resolve().parents[1] / 'Assets' / 'devices'
OUT.mkdir(parents=True, exist_ok=True)
for kind in ('mobile', 'computer', 'unknown'):
    im = Image.new('RGB', (1200, 800)); px = im.load()
    for y in range(800):
        for x in range(1200):
            glow = max(0, 1 - math.hypot((x-700)/850, (y-300)/650))
            px[x,y] = (int(9+9*glow), int(17+35*glow), int(35+51*glow))
    d = ImageDraw.Draw(im)
    for r in (230, 310, 390): d.ellipse((600-r,390-r,600+r,390+r),outline=(30,61,83),width=2)
    for x in range(85,1150,42):
        for y in range(100,710,42): d.ellipse((x,y,x+2,y+2),fill=(48,74,95))
    shadow=Image.new('RGBA',im.size); sd=ImageDraw.Draw(shadow);sd.ellipse((245,635,955,730),fill=(0,0,0,180));shadow=shadow.filter(ImageFilter.GaussianBlur(25));im=Image.alpha_composite(im.convert('RGBA'),shadow);d=ImageDraw.Draw(im)
    if kind == 'mobile':
        d.rounded_rectangle((430,94,770,698),48,fill='#52677e',outline='#92b2c6',width=2)
        d.rounded_rectangle((438,101,762,691),43,fill='#091422')
        d.rounded_rectangle((450,117,750,675),35,fill='#153749')
        d.rounded_rectangle((544,125,656,149),12,fill='#081421')
        d.rounded_rectangle((550,650,650,656),3,fill='#90b3c4')
        center=(600,370); scale=1
    elif kind == 'computer':
        d.rounded_rectangle((238,163,962,600),24,fill='#52677e',outline='#92b2c6',width=2)
        d.rounded_rectangle((246,171,954,592),18,fill='#081421')
        d.rounded_rectangle((265,193,935,567),8,fill='#153749')
        d.ellipse((596,179,603,186),fill='#4c657d')
        d.polygon([(238,600),(962,600),(1060,669),(140,669)],fill='#788b9c')
        d.rounded_rectangle((140,660,1060,682),12,fill='#425973')
        d.polygon([(530,607),(670,607),(697,642),(503,642)],fill='#4d6479')
        center=(600,360);scale=1
    else:
        d.rounded_rectangle((390,185,810,605),70,fill='#153749',outline='#65899f',width=3)
        center=(600,380);scale=1
    cx,cy=center
    # Umbrella motif and a shield, not an OS/manufacturer logo or a trust assertion.
    d.polygon([(cx,cy-112),(cx+98,cy-76),(cx+88,cy+37),(cx+57,cy+83),(cx,cy+119),(cx-57,cy+83),(cx-88,cy+37),(cx-98,cy-76)],fill='#11313e',outline='#6ce1d1',width=3)
    d.pieslice((cx-55,cy-48,cx+55,cy+62),180,360,fill='#66ddcd')
    d.line((cx,cy+7,cx,cy+55),fill='#a9f3e7',width=6)
    d.arc((cx-23,cy+40,cx+1,cy+66),0,180,fill='#a9f3e7',width=5)
    d.rounded_rectangle((88,69,148,75),3,fill='#66ddcd')
    d.rounded_rectangle((1052,725,1112,731),3,fill='#66ddcd')
    im.convert('RGB').save(OUT/f'{kind}.png',optimize=True)
