#!/usr/bin/env python3
"""无武器茶壶：mouth 发水滴，lid 发蒸汽；动画挂点跟随壶嘴。"""
import json
import sys
from pathlib import Path
from PIL import ImageDraw
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent.parent / 'scripts'))
from pixel import blank, Sheet

def pot(shift=0):
    im = blank(48, 48)
    d = ImageDraw.Draw(im)
    ink, cream, shade = '#263550', '#f5eedc', '#d9a066'
    # Handle, body, lid and spout are all part of the character sprite.
    d.rectangle((7+shift, 25, 18+shift, 39), outline=ink, width=3)
    d.ellipse((13+shift, 23, 35+shift, 44), fill=cream, outline=ink, width=2)
    d.polygon([(32+shift,33),(38+shift,30),(40+shift,26),(43+shift,26),(40+shift,36),(33+shift,39)],fill=cream,outline=ink)
    d.rectangle((17+shift,21,31+shift,24),fill=shade,outline=ink)
    d.rectangle((22+shift,18,26+shift,21),fill=ink)
    d.rectangle((18+shift,44,21+shift,47),fill=ink)
    d.rectangle((28+shift,44,31+shift,47),fill=ink)
    d.rectangle((25+shift,29,26+shift,31),fill=ink)
    return im

def build():
    sh=Sheet(48,48,cols=3)
    for shift in (0,1,-1): sh.add(pot(shift))
    sh.save(str(HERE/'sheet.png'))
    im=blank(8,8); ImageDraw.Draw(im).ellipse((0,0,7,7),fill='#75dfbe',outline='#263550'); im.save(HERE/'drop.png')
    im=blank(10,10); ImageDraw.Draw(im).ellipse((0,0,9,9),fill='#f5eedc',outline='#d9a066'); im.save(HERE/'steam.png')
    anims={k:{'frames':[0,1,2],'durations':[12,12,12],'loop':True} for k in ['idle','walk','jump','fall','land','hurt','guard','ko','double_jump']}
    for anim in anims.values():
        anim['sockets']={'mouth':[[42,27],[43,27],[41,27]],'lid':[[24,18],[25,18],[23,18]]}
    anims['pour']={'frames':[0,1,2], 'sockets':{'mouth':[[42,27],[43,27],[41,27]],'lid':[[24,18],[25,18],[23,18]]}}
    anims['steam_pour']=dict(anims['pour'])
    def shot(asset, socket, angle, damage=4):
        return {'type':'shoot','anim':'pour','socket':socket,'projectile':asset,'aim':'fixed','angle':angle,'speed':3,'lifetime':40,'startup':12,'active':2,'recovery':16,'damage':damage,'knockback':{'angle':35,'force':15}}
    data={'format':1,'name':'茶壶','frame_size':[48,48],'anchor':[24,48],
          'sockets':{'mouth':[42,27],'lid':[24,18]},
          'stats':{'hp':100,'body':[36,30],'weight':4,'gravity':0.4,'max_fall':5,'air_control':0.6},
          'assets':{'drop':{'kind':'projectile','image':'drop.png','shape':'circle','size':[8,8]},'steam':{'kind':'projectile','image':'steam.png','shape':'circle','size':[10,10]}},
          'anims':anims,'actions':{'move':{'type':'move','speed':2.2,'accel':0.3},'jump':{'type':'jump','velocity':6.6,'max_count':2},'water':shot('drop','mouth',0),'steam':shot('steam','lid',90,3)},
          'input':{'attack.neutral':'water','attack.side':'water','attack.up':'steam','attack.down':'water','special.neutral':'steam','special.side':'water','special.up':'steam','special.down':'water','jump':'jump'}}
    data['actions']['water']['name']='壶嘴喷水'
    data['actions']['steam']['name']='壶盖蒸汽'
    data['actions']['steam']['anim']='steam_pour'
    (HERE/'character.json').write_text(json.dumps(data,ensure_ascii=False,indent=1))
if __name__=='__main__': build()
