#!/usr/bin/env python3
"""Generate a full-shape, one-frame PE command stream from parameters.bin."""
from __future__ import annotations
import json, math, struct
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]; REPO=ROOT.parents[1]
MAN=json.loads((REPO/'upstream/parameters/manifest.json').read_text())
BLOB=(REPO/'upstream/parameters/parameters.bin').read_bytes()
OPS=MAN['operators']; WIDTH=1166

def tensor(op,name):
 e=OPS[op]['tensors'][name]; raw=BLOB[e['offset']:e['offset']+e['nbytes']]
 fmt={'int8':'b','uint8':'B','int32':'i','int64':'q','float64':'d'}[e['dtype']]
 return list(struct.unpack('<'+fmt*(len(raw)//struct.calcsize(fmt)),raw))
def rshift(v,s):
 if s==0:return v
 q=(abs(v)+(1<<(s-1)))>>s
 return -q if v<0 else q
def sat(v):return max(-127,min(127,v))
def rq(v,m,s):return rshift(v*m,s)
def gsu(op,input_q,input_binary):
 wih=tensor(op,'weight_ih_q'); rows=640; cols=len(input_q)
 im=tensor(op,'input_requantizer.multiplier'); ish=tensor(op,'input_requantizer.right_shift')
 bias=tensor(op,'bias_q'); lut=tensor(op,'sigmoid_lut')
 cm=tensor(op,'cellgate_requantizer.multiplier'); cs=tensor(op,'cellgate_requantizer.right_shift')
 bm=tensor(op,'bn_requantizer.multiplier'); bs=tensor(op,'bn_requantizer.right_shift'); bb=tensor(op,'bn_bias_q')
 acc=[]
 for r in range(rows):
  if input_binary: a=sum(wih[r*cols+c] for c,x in enumerate(input_q) if x)
  else: a=sum(input_q[c]*wih[r*cols+c] for c in range(cols))
  acc.append(a)
 gates=[sat(rshift(rq(acc[r],im[r],ish[r])+bias[r],8)) for r in range(rows)]
 state=[]
 for n in range(320):
  lam=lut[gates[n]+127]; cell=gates[n+320]
  pre=sat(rshift(rq((255-lam)*cell,cm[n],cs[n]),8))
  state.append(sat(rshift(rq(pre,bm[n],bs[n])+bb[n],8)))
 return acc,gates,state,[int(x>=0) for x in state]
def projection(spikes):
 op='fb_model.proj'; w=tensor(op,'weight_q'); m=tensor(op,'requantizer.multiplier')
 s=tensor(op,'requantizer.right_shift'); b=tensor(op,'bias_q'); acc=[]; out=[]
 for r in range(64):
  a=sum(w[r*320+c] for c,x in enumerate(spikes) if x);acc.append(a)
  out.append(sat(rshift(rq(a,m[r],s[r])+b[r],8)))
 return acc,out
def twos(v,bits): return v & ((1<<bits)-1)
commands=[]
def emit(clear=0,enable=0,mode=0,a=0,spike=0,bs=None,direct=None,check=None):
 bs=bs or [0]*16; direct=direct or [0]*16
 word=clear | (enable<<1) | (mode<<2) | (twos(a,8)<<4) | (spike<<12)
 for i,v in enumerate(bs):word|=twos(v,8)<<(13+8*i)
 for i,v in enumerate(direct):word|=twos(v,32)<<(141+32*i)
 if check is not None:
  word|=1<<653
  for i,v in enumerate(check):word|=twos(v,32)<<(654+32*i)
 commands.append(word)
def matrix_commands(weights,rows,cols,inputs,binary,expected):
 for base in range(0,rows,16):
  emit(clear=1)
  active=[c for c,x in enumerate(inputs) if (x if binary else True)]
  for c in active:
   bs=[weights[(base+l)*cols+c] if base+l<rows else 0 for l in range(16)]
   emit(enable=1,mode=1 if binary else 0,a=0 if binary else inputs[c],spike=1,bs=bs)
  emit(check=[expected[base+l] if base+l<rows else 0 for l in range(16)])

scale=tensor('fb_model.sequence_model.layers.0.cell','input_scale')[0]
raw=[math.sin(i*.31)+.37*math.cos(i*.17)+.1*((i%7)-3) for i in range(64)]
mean=sum(raw)/64; var=sum((x-mean)**2 for x in raw)/64
ln=[(x-mean)/math.sqrt(var+1e-5) for x in raw]
input_q=[sat(round(x/scale)) for x in ln]
op1='fb_model.sequence_model.layers.0.cell';op2='fb_model.sequence_model.layers.1.cell'
a1,g1,s1,sp1=gsu(op1,input_q,False); a2,g2,s2,sp2=gsu(op2,sp1,True); ap,proj=projection(sp2)
matrix_commands(tensor(op1,'weight_ih_q'),640,64,input_q,False,a1)
matrix_commands(tensor(op2,'weight_ih_q'),640,320,sp1,True,a2)
matrix_commands(tensor('fb_model.proj','weight_q'),64,320,sp2,True,ap)

orders=[5,3,1]; spectra=[((i*17+9)%101-50,(i*29+5)%97-48) for i in range(5)]
df=[]; offset=0; direct=[0]*16
for band,order in enumerate(orders):
 real=imag=0
 for k in range(order):
  cr,ci=proj[offset+2*k],proj[offset+2*k+1];sr,si=spectra[k]
  real+=sr*cr-si*ci;imag+=sr*ci+si*cr
 df.extend([real,imag]);offset+=2*order
emit(clear=1)
offset=0
for k in range(5):
 direct=[0]*16
 for band,order in enumerate(orders):
  if k<order:
   base=sum(2*o for o in orders[:band]);cr,ci=proj[base+2*k],proj[base+2*k+1];sr,si=spectra[k]
   direct[2*band]=sr*cr-si*ci;direct[2*band+1]=sr*ci+si*cr
 emit(enable=1,mode=3,direct=direct)
emit(check=df+[0]*10)

out=ROOT/'tb/vectors/pe_small_model_commands.hex'
digits=(WIDTH+3)//4;out.write_text('\n'.join(f'{x:0{digits}x}' for x in commands)+'\n')
(ROOT/'tb/vectors/pe_small_model_commands.count').write_text(str(len(commands))+'\n')
summary={'shape':'64->320->320->64','commands':len(commands),'fb1_active':sum(sp1),
 'fb2_active':sum(sp2),'projection_min':min(proj),'projection_max':max(proj),
 'projection_checksum':sum((i+1)*v for i,v in enumerate(proj)),'deepfilter':df,
 'layernorm_q_checksum':sum((i+1)*v for i,v in enumerate(input_q))}
(ROOT/'reports/pe_small_model').mkdir(parents=True,exist_ok=True)
(ROOT/'reports/pe_small_model/reference_summary.json').write_text(json.dumps(summary,indent=2)+'\n')
print('PE_SMALL_MODEL_REFERENCE',json.dumps(summary,sort_keys=True))
