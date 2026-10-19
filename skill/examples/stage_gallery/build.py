#!/usr/bin/env python3
"""接口演示场景，无用户照片：背景人物抛球和挥拍；正式生成须对齐用户原图。"""
import json
import sys
from pathlib import Path
from PIL import ImageDraw
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE.parent.parent/'scripts'))
from pixel import blank

def build():
    im=blank(480,270);d=ImageDraw.Draw(im)
    d.rectangle((0,0,479,269),fill='#1c263b')
    d.rectangle((20,25,460,180),fill='#263550',outline='#435774',width=3)
    for x in (80,200,320): d.rectangle((x,40,x+60,80),fill='#435774',outline='#a3b5cd',width=2)
    d.rectangle((60,200,420,269),fill='#d9a066',outline='#263550',width=3)
    for x,y,w in [(124,166,72),(284,166,72),(200,134,72)]:d.rectangle((x,y,x+w-1,y+3),fill='#f5eedc')
    for x,shirt in [(28,'#75dfbe'),(410,'#f47778')]:
        d.rectangle((x+14,70,x+32,88),fill='#d9a066')
        d.rectangle((x+12,89,x+34,120),fill=shirt)
        d.rectangle((x+16,121,x+20,135),fill='#101522')
        d.rectangle((x+27,121,x+31,135),fill='#101522')
    d.rectangle((55,96,68,102),fill='#d9a066')
    d.rectangle((420,91,432,97),fill='#d9a066')
    im.save(HERE/'bg.png')
    ball=blank(8,8);ImageDraw.Draw(ball).ellipse((0,0,7,7),fill='#f47778',outline='#d9a066');ball.save(HERE/'ball.png')
    bat=blank(40,8);ImageDraw.Draw(bat).rectangle((0,2,39,5),fill='#d9a066',outline='#f5eedc');bat.save(HERE/'bat.png')
    common={'period':240,'warn':45,'damage':5,'knockback':{'angle':45,'force':20},'radius':4}
    data={'format':1,'kind':'stage','name':'背景机关演示','background':'bg','spawns':[[100,200],[180,200],[280,200],[380,200]],
          'assets':{'bg':{'kind':'background','image':'bg.png'},'ball':{'kind':'hazard','image':'ball.png'},'bat':{'kind':'hazard','image':'bat.png'}},
          'elements':[{'rect':[60,200,360,70],'collide':'solid','background_region':True}]+[{'rect':[x,y,w,4],'collide':'platform','background_region':True} for x,y,w in [(124,166,72),(284,166,72),(200,134,72)]]+[
              {'id':'thrower','rect':[28,70,48,66],'collide':'none','background_region':True,'trap':dict(common,type='shoot',origin=[34,29],asset='ball',angle=0,speed=3,lifetime=110)},
              {'id':'batter','rect':[410,65,54,71],'collide':'none','background_region':True,'trap':dict(common,type='swing',origin=[16,29],asset='bat',grip=[1,4],length=38,radius=2,active=30,offset=90,**{'from':-60,'to':-120})}]}
    (HERE/'stage.json').write_text(json.dumps(data,ensure_ascii=False,indent=1))
if __name__=='__main__':build()
