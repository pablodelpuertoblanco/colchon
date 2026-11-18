"""Genera el juego completo de iconos de Android para Colchon.

Para cambiar el icono se edita este archivo y se vuelve a ejecutar:
    python3 design/build_icons.py
Necesita rsvg-convert (paquete librsvg) y Pillow.
"""
import math, os, subprocess

RES = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'android', 'app', 'src', 'main', 'res')
RES = os.path.normpath(RES)
DESIGN = os.path.dirname(os.path.abspath(__file__))

TEAL_D, TEAL_L = '#1C4C4F', '#3C868B'

# El degradado va en coordenadas del lienzo: en una forma plana (una linea
# horizontal) el encuadre del objeto tiene altura cero y no se pintaria.
DEFS = f'''
  <linearGradient id="bg" x1="0.1" y1="0" x2="0.9" y2="1">
    <stop offset="0" stop-color="{TEAL_L}"/><stop offset="1" stop-color="{TEAL_D}"/>
  </linearGradient>
  <linearGradient id="cush" gradientUnits="userSpaceOnUse" x1="120" y1="110" x2="330" y2="400">
    <stop offset="0" stop-color="#FFFEFA"/><stop offset="1" stop-color="#E8DBC2"/>
  </linearGradient>'''


def arc(cx, cy, r, a0, a1):
    x0, y0 = cx + r * math.cos(math.radians(a0)), cy + r * math.sin(math.radians(a0))
    x1, y1 = cx + r * math.cos(math.radians(a1)), cy + r * math.sin(math.radians(a1))
    large = 1 if (a1 - a0) % 360 > 180 else 0
    return f'M {x0:.1f} {y0:.1f} A {r} {r} 0 {large} 1 {x1:.1f} {y1:.1f}'


def euro(stroke, opacity=1.0):
    """Simbolo del euro mullido: arco abierto y dos barras, con puntas redondas."""
    cx, cy, r = 282, 256, 120
    return (f'<g fill="none" stroke="{stroke}" stroke-opacity="{opacity}" stroke-linecap="round">'
            f'<path d="{arc(cx, cy, r, 36, 324)}" stroke-width="58"/>'
            f'<path d="M 100 {cy - 38} L 296 {cy - 38}" stroke-width="42"/>'
            f'<path d="M 100 {cy + 38} L 296 {cy + 38}" stroke-width="42"/>'
            '</g>')


def art(scale=1.0, shadow=True, stroke='url(#cush)'):
    g = f'<g transform="translate(256 256) scale({scale}) translate(-256 -256)">'
    if shadow:
        g += '<g transform="translate(0,12)">' + euro('#0B2E31', 0.22) + '</g>'
    return g + euro(stroke) + '</g>'


def doc(body, defs=DEFS):
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">'
            f'<defs>{defs}</defs>{body}</svg>')


BG = '<rect width="512" height="512" fill="url(#bg)"/>'
FULL = doc(BG + art(0.95))
# El icono adaptativo recorta hasta el 66 de 108 central: el dibujo se reduce
# para no perder las puntas con las mascaras redondas.
FOREGROUND = doc(art(0.86))
# Version monocroma de Android 13: silueta plana, el sistema le pone el color.
MONOCHROME = doc(art(0.86, shadow=False, stroke='#000'), defs='')


def render(svg_text, px, dest):
    open('/tmp/_icon.svg', 'w', encoding='utf-8').write(svg_text)
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    subprocess.run(['rsvg-convert', '-w', str(px), '-h', str(px), '/tmp/_icon.svg', '-o', dest], check=True)


def write(path, content):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, 'w', encoding='utf-8').write(content)


DENSITIES = [('mdpi', 1), ('hdpi', 1.5), ('xhdpi', 2), ('xxhdpi', 3), ('xxxhdpi', 4)]
for name, f in DENSITIES:
    render(FOREGROUND, round(108 * f), f'{RES}/mipmap-{name}/ic_launcher_foreground.png')
    render(MONOCHROME, round(108 * f), f'{RES}/mipmap-{name}/ic_launcher_monochrome.png')
    render(FULL, round(48 * f), f'{RES}/mipmap-{name}/ic_launcher.png')

# Iconos antiguos (Android 7 y anteriores): no los recorta el sistema.
from PIL import Image, ImageDraw
for name, f in DENSITIES:
    px = round(48 * f)
    src = Image.open(f'{RES}/mipmap-{name}/ic_launcher.png').convert('RGBA')
    for kind, dest in (('round', 'ic_launcher_round.png'), ('square', 'ic_launcher.png')):
        m = Image.new('L', (px, px), 0)
        d = ImageDraw.Draw(m)
        if kind == 'round':
            d.ellipse([0, 0, px - 1, px - 1], fill=255)
        else:
            d.rounded_rectangle([0, 0, px - 1, px - 1], radius=max(2, round(px * 0.18)), fill=255)
        out = Image.new('RGBA', (px, px), (0, 0, 0, 0))
        out.paste(src, (0, 0), m)
        out.save(f'{RES}/mipmap-{name}/{dest}')

write(f'{RES}/drawable/ic_launcher_background.xml',
      '<?xml version="1.0" encoding="utf-8"?>\n'
      '<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">\n'
      '    <gradient\n'
      '        android:type="linear"\n'
      '        android:angle="315"\n'
      f'        android:startColor="{TEAL_L}"\n'
      f'        android:endColor="{TEAL_D}" />\n'
      '</shape>\n')

adaptive = ('<?xml version="1.0" encoding="utf-8"?>\n'
            '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '    <background android:drawable="@drawable/ic_launcher_background"/>\n'
            '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
            '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>\n'
            '</adaptive-icon>\n')
write(f'{RES}/mipmap-anydpi-v26/ic_launcher.xml', adaptive)
write(f'{RES}/mipmap-anydpi-v26/ic_launcher_round.xml', adaptive)

# Google Play pide 512x512 y sin transparencia.
play = f'{DESIGN}/icono_google_play_512.png'
render(FULL, 512, play)
Image.open(play).convert('RGB').save(play)
print('iconos generados en', RES)
