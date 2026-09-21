import os, pathlib, struct, json, hashlib
from PIL import Image
root=pathlib.Path(os.environ['TEMP'])/'fr-minigame-source/pokefirered-master/graphics'
rom=pathlib.Path(r'C:\Users\amand\Downloads\roms\Pokemon_FireRed-.gba').read_bytes()
assets={};targets={}
for group,folder in [('slots','slot_machine/firered'),('crush','berry_crush'),('jump','pokemon_jump'),('dodrio','dodrio_berry_picking')]:
 for p in (root/folder).glob('*.png'):
  im=Image.open(p);w,h=im.size
  if im.mode!='P' or w%8 or h%8:continue
  px=list(im.getdata());raw=bytearray()
  for ty in range(0,h,8):
   for tx in range(0,w,8):
    for y in range(8):
     for x in range(0,8,2):raw.append((px[(ty+y)*w+tx+x]%16)|((px[(ty+y)*w+tx+x+1]%16)<<4))
  pal=im.getpalette();colors=bytes().join(struct.pack('<H',(pal[i]>>3)|((pal[i+1]>>3)<<5)|((pal[i+2]>>3)<<10)) for i in range(0,len(pal),3))
  po=rom.find(colors[:32]);key=group+'/'+p.stem
  assets[key]={'width':w,'height':h,'pal':po,'paletteBytes':len(colors),'gfx':None}
  targets.setdefault(len(raw),{})[bytes(raw)]=key
 for p in (root/folder).glob('*.bin'):
  raw=p.read_bytes();targets.setdefault(len(raw),{})[raw]=group+'/'+p.stem+'/map'
found={}
for off in range(0,len(rom)-4,4):
 if rom[off]!=16:continue
 n=int.from_bytes(rom[off+1:off+4],'little')
 if n not in targets:continue
 out=bytearray();at=off+4
 try:
  while len(out)<n:
   flags=rom[at];at+=1
   for bit in range(7,-1,-1):
    if len(out)>=n:break
    if flags&(1<<bit):
     a,b=rom[at:at+2];at+=2;distance=((a&15)<<8)+b+1
     if distance>len(out):raise ValueError()
     for _ in range((a>>4)+3):out.append(out[-distance])
    else:out.append(rom[at]);at+=1
  key=targets[n].get(bytes(out[:n]))
  if key:found[key]=off
 except (ValueError,IndexError):pass
for key,rec in assets.items():rec['gfx']=found.get(key)
result={'assets':assets,'found':found}
pathlib.Path('tests/content-editor/gen3-smoke/minigame-offsets.json').write_text(json.dumps(result,indent=2))
for k,v in assets.items():print(k,v)
print('MAPS', {k:hex(v) for k,v in found.items() if k.endswith('/map')})
