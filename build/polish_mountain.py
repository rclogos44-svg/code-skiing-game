#!/usr/bin/env python3
"""Refresh skiable snow relief while retaining route IDs, saves, and designed cliffs.
Run once on an existing generated world. Full generation calls polish() before baking.
"""
import json
import sys
from pathlib import Path
import numpy as np
from PIL import Image


def polish(g, height, layout):
    if layout.get('ski_overhaul') == 1:
        return height
    z, x = np.mgrid[:height.shape[0], :height.shape[1]].astype(np.float32)
    x *= g.SP
    z *= g.SP
    _, ny, _ = g.normals(height, g.SP)
    slope = np.degrees(np.arccos(np.clip(ny, -1, 1)))
    # Broad terrain remains; remove short wavelength chatter from fast snow faces.
    weight = g.smoothstep(8, 18, slope) * (1 - g.smoothstep(34, 44, slope)) * 0.7
    for feature in layout.get('features', []):
        radius = max(feature.get('width', 40) * 0.7, 55)
        dist = np.hypot(x - feature['x'], z - feature['z'])
        weight *= g.smoothstep(radius, radius + 25, dist)
    for kicker in layout.get('kickers', []):
        if 'x' in kicker:
            weight *= g.smoothstep(45, 70, np.hypot(x-kicker['x'], z-kicker['z']))
    for spawn in layout.get('drop_zones', []):
        weight *= g.smoothstep(14, 30, np.hypot(x-spawn['x'],z-spawn['z']))
    smooth = g.blur(height, 2)
    result = height + np.clip(smooth-height, -0.65, 0.65) * weight
    # Three existing safe cliff corridors become readable progression lines, without
    # introducing cliffs across established pistes or race routes.
    cliffs = sorted((f for f in layout['features'] if f['type']=='cliff'), key=lambda f:f['drop'])
    selected = [cliffs[0], cliffs[len(cliffs)//2], cliffs[-1]]
    for level, feature in zip(('Scout', 'Freeride', 'Expert'), selected):
        a = (x-feature['x'])*feature['dx'] + (z-feature['z'])*feature['dz']
        c = -(x-feature['x'])*feature['dz'] + (z-feature['z'])*feature['dx']
        lateral = 1-g.smoothstep(10, 24, np.abs(c))
        # Run-in and recovery: preserve the takeoff edge and open space beneath it.
        corridor = lateral * (g.smoothstep(-85, -65, a)*(1-g.smoothstep(-24,-12,a)) + g.smoothstep(30,45,a)*(1-g.smoothstep(95,120,a)))
        result += np.clip(g.blur(height, 3)-result,-1.0,1.0)*corridor
        if level == 'Expert':
            # A steep, open landing matches the flight off the advanced drop; the
            # lower apron eases gradually back into the existing valley floor.
            ax, az = feature['x']+feature['dx']*8, feature['z']+feature['dz']*8
            anchor = float(height[round(az/g.SP),round(ax/g.SP)])
            landing = anchor - 0.75*np.minimum(a-8,47) - 0.15*np.maximum(a-55,0)
            blend = lateral*g.smoothstep(0,10,a)*(1-g.smoothstep(90,150,a))
            result += (np.minimum(result,landing)-result)*blend
        feature['line_grade'] = level.lower()
        feature['approach_length'] = 70
        feature['landing_clearance'] = 100
        dx, dz = feature['dx'], feature['dz']
        px, pz = feature['x']-dx*65, feature['z']-dz*65
        layout['drop_zones'].append(dict(name=level+' Drop',region=feature['region'],x=px,z=pz,y=float(result[round(pz/g.SP),round(px/g.SP)]),yaw=float(np.arctan2(-dx,-dz)),unlocked=True))
    layout['ski_overhaul'] = 1
    return result.astype(np.float32)


def dress_lines(data, layout, rocks=False):
    data = np.asarray(data, dtype='<f4').reshape(-1,4)
    keep = np.ones(len(data), dtype=bool)
    additions = []
    for f in layout.get('features', []):
        if 'line_grade' not in f:
            continue
        a = (data[:,0]-f['x'])*f['dx']+(data[:,1]-f['z'])*f['dz']
        c = -(data[:,0]-f['x'])*f['dz']+(data[:,1]-f['z'])*f['dx']
        keep &= ~((a>-85)&(a<150)&(np.abs(c)<14))
        if rocks:
            for along in [-35, -18]:
                for side in [-1, 1]:
                    x=f['x']+f['dx']*along-f['dz']*side*20
                    z=f['z']+f['dz']*along+f['dx']*side*20
                    if not np.any(np.hypot(data[:,0]-x,data[:,1]-z)<0.1):
                        additions.append([x,z,3.8 if along==-35 else 2.6,side*0.7])
    return np.concatenate([data[keep], np.asarray(additions,dtype='<f4').reshape(-1,4)])


def main(project):
    import gen_terrain as g
    import map_render
    world = Path(project)/'world'
    layout=json.loads((world/'layout.json').read_text())
    if layout.get('ski_overhaul') == 1:
        print('Mountain already polished; no changes.')
        return
    meta=layout['meta']
    h=np.fromfile(world/'height16.bin',dtype='>u2').reshape(meta['n'],meta['n']).astype(np.float32)*meta['core_scale']+meta['core_min']
    original=h.copy()
    h=polish(g,h,layout)
    # Keep quantization parameters: CPU collision and GPU rendering decode identical bytes.
    packed=np.clip(np.rint((h-meta['core_min'])/meta['core_scale']),0,65535).astype('>u2')
    packed.tofile(world/'height16.bin')
    h=packed.astype(np.float32)*meta['core_scale']+meta['core_min']
    nx,ny,nz=g.normals(h,g.SP)
    comps=[]
    for n in [nx,nz,ny]:
        comps.append((n[:-1,:-1]+n[1:,:-1]+n[:-1,1:]+n[1:,1:])*0.25)
    normal=np.stack(comps,axis=-1)
    normal/=np.maximum(np.linalg.norm(normal,axis=-1,keepdims=True),1e-6)
    Image.fromarray(np.uint8(np.clip(normal*.5+.5,0,1)*255+.5)).save(world/'normal.png')
    sun,ao=g.bake_light(h)
    bake=np.array(Image.open(world/'bake.png'))
    bake[:,:,0]=sun
    bake[:,:,1]=ao
    Image.fromarray(bake).save(world/'bake.png')
    # Preserve terrain IDs and object positions, clearing only the curated approaches.
    for filename in ['trees.bin','rocks.bin']:
        data=np.fromfile(world/filename,dtype='<f4').reshape(-1,4)
        data=dress_lines(data,layout,filename=='rocks.bin')
        data.astype('<f4').tofile(world/filename)
        meta['tree_count' if filename=='trees.bin' else 'rock_count']=len(data)
    (world/'layout.json').write_text(json.dumps(layout,indent=1))
    map_render.render(str(project),2048)
    print('Polished snow relief: max delta %.3fm; RMS %.3fm; %d progression lines' % (np.abs(h-original).max(),np.sqrt(np.mean((h-original)**2)),3))

if __name__=='__main__':
    main(sys.argv[1])
