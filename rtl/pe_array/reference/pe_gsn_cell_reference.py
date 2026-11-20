#!/usr/bin/env python3
"""Export real-parameter, bit-exact vectors for one integer GSN/GSU cell."""
from __future__ import annotations
import json,math,struct
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1];REPO=ROOT.parents[1]
MAN=json.loads((REPO/'upstream/parameters/manifest.json').read_text());BLOB=(REPO/'upstream/parameters/parameters.bin').read_bytes()
OPS=MAN['operators'];WIDTH=490
NAMES=['fb_model.sequence_model.layers.0.cell','fb_model.sequence_model.layers.1.cell']

def tensor(op,name):
 e=OPS[op]['tensors'][name];raw=BLOB[e['offset']:e['offset']+e['nbytes']]
 f={'int8':'b','uint8':'B','int32':'i','int64':'q','float64':'d'}[e['dtype']]
 return list(struct.unpack('<'+f*(len(raw)//struct.calcsize(f)),raw))
def rs(v,s):
 if s==0:return v
 q=(abs(v)+(1<<(s-1)))>>s
 return -q if v<0 else q
def sat(v):return max(-127,min(127,v))
def rq(v,m,s):return rs(v*m,s)
def params(op,n):
 im=tensor(op,'input_requantizer.multiplier');ish=tensor(op,'input_requantizer.right_shift')
 rm=tensor(op,'recurrent_requantizer.multiplier');rsh=tensor(op,'recurrent_requantizer.right_shift');b=tensor(op,'bias_q')
 pm=tensor(op,'cx_requantizer.multiplier');ps=tensor(op,'cx_requantizer.right_shift')
 cm=tensor(op,'cellgate_requantizer.multiplier');cs=tensor(op,'cellgate_requantizer.right_shift')
 bm=tensor(op,'bn_requantizer.multiplier');bs=tensor(op,'bn_requantizer.right_shift');bb=tensor(op,'bn_bias_q')
 return (im[n],ish[n],rm[n],rsh[n],b[n],im[n+320],ish[n+320],rm[n+320],rsh[n+320],b[n+320],pm[n],ps[n],cm[n],cs[n],bm[n],bs[n],bb[n])
def evaluate(op,n,ia,ra,prev):
 p=params(op,n);lut=tensor(op,'sigmoid_lut')
 fg_u=rs(rq(ia,p[0],p[1])+rq(ra,p[2],p[3])+p[4],8);fg=sat(fg_u)
 cg_u=rs(rq(ia,p[5],p[6])+rq(ra,p[7],p[8])+p[9],8);cg=sat(cg_u)
 lam=lut[fg+127]
 pre_u=rs(rq(lam*prev,p[10],p[11])+rq((255-lam)*cg,p[12],p[13]),8);pre=sat(pre_u)
 state_u=rs(rq(pre,p[14],p[15])+p[16],8);state=sat(state_u)
 return p,(fg,cg,lam,pre,state,int(state>=0),int(fg_u<-127 or fg_u>127),int(cg_u<-127 or cg_u>127),int(pre_u<-127 or pre_u>127),int(state_u<-127 or state_u>127))
def twos(v,w):return v&((1<<w)-1)
def pack(layer,ia,ra,prev,p,e,tag):
 fields=[(layer,1),(ia,32),(ra,32),(prev,8),(p[0],32),(p[1],6),(p[2],32),(p[3],6),(p[4],32),(p[5],32),(p[6],6),(p[7],32),(p[8],6),(p[9],32),(p[10],32),(p[11],6),(p[12],32),(p[13],6),(p[14],32),(p[15],6),(p[16],32),(tag,10),(e[0],8),(e[1],8),(e[2],8),(e[3],8),(e[4],8),(e[5],1),(e[6],1),(e[7],1),(e[8],1),(e[9],1)]
 word=0;off=0
 for value,width in fields:word|=twos(value,width)<<off;off+=width
 assert off==WIDTH
 return word
def matvec(op,name,values,binary=False):
 w=tensor(op,name);cols=len(values);rows=640
 return [sum(w[r*cols+c] if binary else w[r*cols+c]*values[c] for c in range(cols) if (values[c] if binary else True)) for r in range(rows)]

scale=tensor(NAMES[0],'input_scale')[0]
raw=[math.sin(i*.31)+.37*math.cos(i*.17)+.1*((i%7)-3) for i in range(64)]
mean=sum(raw)/64;var=sum((x-mean)**2 for x in raw)/64
inp=[sat(round(((x-mean)/math.sqrt(var+1e-5))/scale)) for x in raw]
hx0=[int((i*13+7)%17<4) for i in range(320)];prev0=[(i*37)%255-127 for i in range(320)]
ia0=matvec(NAMES[0],'weight_ih_q',inp);ra0=matvec(NAMES[0],'weight_hh_q',hx0,True)
vectors=[];states0=[];spikes0=[];clip=[0,0,0,0]
for n in range(320):
 p,e=evaluate(NAMES[0],n,ia0[n],ra0[n],prev0[n]);vectors.append(pack(0,ia0[n],ra0[n],prev0[n],p,e,n));states0.append(e[4]);spikes0.append(e[5]);clip=[a+b for a,b in zip(clip,e[6:])]
for k in range(16):
 n=(k*19)%320;ia=(-1 if k&1 else 1)*(700000+k*12345);ra=(-1 if k&2 else 1)*(900000-k*23456);prev=-127 if k&4 else 127
 p,e=evaluate(NAMES[0],n,ia,ra,prev);vectors.append(pack(0,ia,ra,prev,p,e,320+k));clip=[a+b for a,b in zip(clip,e[6:])]

hx1=[int((i*11+3)%19<5) for i in range(320)];prev1=[(i*53+11)%255-127 for i in range(320)]
ia1=matvec(NAMES[1],'weight_ih_q',spikes0,True);ra1=matvec(NAMES[1],'weight_hh_q',hx1,True)
states1=[];spikes1=[]
for n in range(320):
 p,e=evaluate(NAMES[1],n,ia1[n],ra1[n],prev1[n]);vectors.append(pack(1,ia1[n],ra1[n],prev1[n],p,e,336+n));states1.append(e[4]);spikes1.append(e[5]);clip=[a+b for a,b in zip(clip,e[6:])]
for k in range(16):
 n=(k*23)%320;ia=(-1 if k&1 else 1)*(950000-k*11111);ra=(-1 if k&2 else 1)*(750000+k*22222);prev=-127 if k&4 else 127
 p,e=evaluate(NAMES[1],n,ia,ra,prev);vectors.append(pack(1,ia,ra,prev,p,e,656+k));clip=[a+b for a,b in zip(clip,e[6:])]

digits=(WIDTH+3)//4
(ROOT/'tb/vectors/pe_gsn_cell_vectors.hex').write_text('\n'.join(f'{x:0{digits}x}' for x in vectors)+'\n')
(ROOT/'tb/vectors/pe_gsn_cell_vectors.count').write_text(str(len(vectors))+'\n')
for i,op in enumerate(NAMES):
 lut=tensor(op,'sigmoid_lut');(ROOT/f'tb/vectors/pe_gsn_cell_lut{i}.hex').write_text('\n'.join(f'{x:02x}' for x in lut)+'\n')
summary={'vectors':len(vectors),'real_channels_per_layer':320,'stress_per_layer':16,'layer0_spikes':sum(spikes0),'layer1_spikes':sum(spikes1),'layer0_state_checksum':sum((i+1)*x for i,x in enumerate(states0)),'layer1_state_checksum':sum((i+1)*x for i,x in enumerate(states1)),'clip_counts':{'forget':clip[0],'cellgate':clip[1],'state_pre':clip[2],'state':clip[3]}}
(ROOT/'reports/pe_gsn_cell').mkdir(parents=True,exist_ok=True);(ROOT/'reports/pe_gsn_cell/reference_summary.json').write_text(json.dumps(summary,indent=2)+'\n')
print('PE_GSN_CELL_REFERENCE',json.dumps(summary,sort_keys=True))
