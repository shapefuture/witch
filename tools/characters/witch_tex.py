"""Texture painters for the antler witch (v2), ported from the user's source.

Felt and boucle wool (multi-scale noise), the tree-of-life cape, the appliqué skirt strip
(moons, stars, owls, bears, footprints, masks, antlers), the green vest with root embroidery,
the maroon bib, sleeves, boots, satchels, strap, bird, and the small sprites for the charms and
satchel contents (oak leaf, carrot, lavender, mushroom, map, feather, house). Every painter
draws at its native size with 3-4x supersampling; `build_atlas` lands them in one atlas.

The source imported a missing `fw_core` (`K.ATL`); `atlas.Atlas` replaces it. The painted face
is gone: the face is the photo plate (`face_plate.py`). Painter bodies are the source's own
(compact style kept so they diff against it); only the overridden first drafts were dropped.
"""
# flake8: noqa
import numpy as np, math, random
from PIL import Image, ImageDraw, ImageFilter
def C(c): return tuple(int(round(max(0,min(1,v))*255)) for v in c)
SS=4
class Cv:
    def __init__(s,w,h,bg=None,im=None,ss=SS):
        s.w,s.h,s.ss=w,h,ss
        if im is not None: s.im=im.resize((w*ss,h*ss),Image.NEAREST).convert('RGB')
        else: s.im=Image.new('RGB',(w*ss,h*ss),C(bg))
        s.d=ImageDraw.Draw(s.im)
    def poly(s,pts,fill): s.d.polygon([(x*s.ss,y*s.ss) for x,y in pts],fill=C(fill))
    def ell(s,cx,cy,rx,ry,fill): s.d.ellipse([(cx-rx)*s.ss,(cy-ry)*s.ss,(cx+rx)*s.ss,(cy+ry)*s.ss],fill=C(fill))
    def line(s,pts,fill,width): s.d.line([(x*s.ss,y*s.ss) for x,y in pts],fill=C(fill),width=max(1,int(round(width*s.ss))),joint='curve')
    def rect(s,x0,y0,x1,y1,fill): s.d.rectangle([x0*s.ss,y0*s.ss,x1*s.ss,y1*s.ss],fill=C(fill))
    def soft(s,cx,cy,rx,ry,color,alpha,blur=3):
        m=Image.new('L',s.im.size,0); ImageDraw.Draw(m).ellipse([(cx-rx)*s.ss,(cy-ry)*s.ss,(cx+rx)*s.ss,(cy+ry)*s.ss],fill=255)
        m=m.filter(ImageFilter.GaussianBlur(blur*s.ss)).point(lambda v:int(v*alpha)); s.im.paste(Image.new('RGB',s.im.size,C(color)),(0,0),m)
    def out(s): return s.im.resize((s.w,s.h),Image.BOX)
def arr(im): return np.asarray(im).astype(float)/255.
def img(a): return Image.fromarray((np.clip(a,0,1)*255+.5).astype(np.uint8))

def boucle(w,h,c,seed=1,amp=.09,clump=3):
    """fuzzy wool: multi-scale noise + bright/dark loops, tileable enough for nearest-sampled low-res"""
    r=np.random.RandomState(seed); n=r.randn(h,w)*amp*.6
    for sc,a in ((2,.07),(4,.06)):
        sm=r.randn(h//sc+2,w//sc+2); sm=np.kron(sm,np.ones((sc,sc)))[:h,:w]; n+=sm*a
    base=np.ones((h,w,3))*A(c)[None,None,:]*(1+n[...,None])
    sp=r.rand(h,w); base[sp>.965]*=1.28; base[sp<.035]*=.72
    return img(base)
A=np.array

def tex_cape():
    W=384; base=boucle(W,W,(.45,.13,.26),seed=5,amp=.10)
    cv=Cv(W,W,im=base,ss=3); tree_of_life(cv,.26*W*3,.27*W*3,.74*W*3,.97*W*3) if False else None
    # draw at ss resolution: coordinates in output px so scale
    s=cv.ss
    class Z:  # adapter drawing in output-pixel units
        def line(self,p,c,w): cv.line(p,c,w)
        def poly(self,p,c): cv.poly(p,c)
    tree_of_life(Z(),.24*W,.26*W,.76*W,.97*W)
    out=cv.out(); a=arr(out)
    # subtle wool fuzz over embroidery
    r=np.random.RandomState(9); a*= (1+r.randn(W,W,1)*.03); return img(a)

# ============================================================ skirt strip with appliqué icons
GOLD=(.88,.68,.30); BRONZE=(.80,.52,.30); ROSE=(.80,.48,.42)
def ic_crescent(cv,cx,cy,R,rot,col):
    n=12; o=[(cx+R*math.cos(rot+t),cy+R*math.sin(rot+t)) for t in np.linspace(.55,2*math.pi-.55,n)]
    i=[(cx+R*.40*math.cos(rot)+R*.80*math.cos(rot+t),cy+R*.40*math.sin(rot)+R*.80*math.sin(rot+t)) for t in np.linspace(.70,2*math.pi-.70,n)]
    cv.poly(o+i[::-1],col)
def ic_star(cv,cx,cy,R,n,col,rot=0):
    pts=[]
    for k in range(2*n): rr=R if k%2==0 else R*(.42 if n==8 else .46); t=rot+math.pi/2+k*math.pi/n; pts.append((cx+rr*math.cos(t),cy-rr*math.sin(t)))
    cv.poly(pts,col)
def ic_owl(cv,cx,cy,R,col,dark):
    pts=[(-.55,-.9),(-.30,-.62),(.30,-.62),(.55,-.9),(.72,-.25),(.58,.62),(.28,1.0),(-.28,1.0),(-.58,.62),(-.72,-.25)]
    cv.poly([(cx+x*R*.78,cy+y*R) for x,y in pts],col)
    for sg in (-1,1):
        cv.ell(cx+sg*R*.30,cy-R*.28,R*.24,R*.24,dark); cv.ell(cx+sg*R*.30,cy-R*.28,R*.16,R*.16,col); cv.ell(cx+sg*R*.30,cy-R*.28,R*.07,R*.07,dark)
    cv.poly([(cx-R*.08,cy+R*.0),(cx+R*.08,cy+R*.0),(cx,cy+R*.2)],dark)
    for k in range(3): cv.line([(cx-R*.35+k*R*.18,cy+R*.45),(cx-R*.30+k*R*.18,cy+R*.75)],dark,max(.8,R*.06))
def ic_bear(cv,cx,cy,R,col,dark,flip=1):
    pts=[(-.95,.05),(-.85,-.35),(-.45,-.52),(.05,-.55),(.30,-.62),(.38,-.88),(.52,-.62),(.72,-.58),(.98,-.22),(.95,.0),(.72,.05),(.58,.30),(.60,.72),(.42,.72),(.34,.42),(-.05,.45),(-.12,.72),(-.34,.72),(-.36,.42),(-.62,.40),(-.66,.72),(-.86,.72),(-.92,.30)]
    cv.poly([(cx+flip*x*R,cy+y*R*.95) for x,y in pts],col); cv.ell(cx+flip*R*.78,cy-R*.3,R*.05,R*.05,dark)
def ic_foot(cv,cx,cy,R,col):
    for a in (-.55,0,.55):
        cv.line([(cx,cy),(cx+math.sin(a)*R*1.0,cy-math.cos(a)*R*1.0)],col,max(1.0,R*.14))
        cv.ell(cx+math.sin(a)*R*1.0,cy-math.cos(a)*R*1.0,R*.1,R*.1,col)
    cv.line([(cx,cy),(cx,cy+R*.6)],col,max(1.0,R*.14))
def ic_mask(cv,cx,cy,R,col,dark):
    cv.poly([(cx-R*.55,cy-R*.9),(cx+R*.55,cy-R*.9),(cx+R*.62,cy+R*.2),(cx+R*.3,cy+R*.95),(cx-R*.3,cy+R*.95),(cx-R*.62,cy+R*.2)],col)
    for sg in (-1,1): cv.ell(cx+sg*R*.26,cy-R*.22,R*.17,R*.2,dark)
    cv.poly([(cx-R*.08,cy+R*.15),(cx+R*.08,cy+R*.15),(cx,cy+R*.38)],dark)
    for k in range(3): cv.line([(cx-R*.22+k*R*.22,cy+R*.58),(cx-R*.22+k*R*.22,cy+R*.82)],dark,max(.8,R*.07))
def ic_antler(cv,cx,cy,R,col):
    cv.line([(cx,cy+R),(cx,cy-R*.2)],col,max(1.0,R*.15))
    for sg in (-1,1):
        cv.line([(cx,cy+R*.1),(cx+sg*R*.7,cy-R*.5),(cx+sg*R*.55,cy-R*1.0)],col,max(1.0,R*.13)); cv.line([(cx+sg*R*.45,cy-R*.3),(cx+sg*R*1.0,cy-R*.35)],col,max(1.0,R*.1))

def tex_felt(c,seed,W=128,H=128):
    a=arr(boucle(W,H,c,seed=seed,amp=.06)); return img(a)

# ============================================================ sleeves, hair, boots, leather, strap, bird, hand, misc
def tex_sleeve():
    W,H=256,96; a=boucle(W,H,(.36,.15,.45),seed=17,amp=.08); cv=Cv(W,H,im=a,ss=3)
    def at(u,v,kind,R,rot=0):
        for du in (0,1,-1):
            x=(u+du)*W; y=v*H
            if -R<=x<=W+R:
                if kind=='m': ic_crescent(cv,x+1,y+1.2,R,rot,(.23,.09,.30)); ic_crescent(cv,x,y,R,rot,GOLD)
                else: ic_star(cv,x+1,y+1.2,R,8,(.23,.09,.30)); ic_star(cv,x,y,R,8,GOLD)
    for base in (.5,0.0):      # front and back
        at(base,.60,'m',9.5,-.6 if base>0 else -2.5)
        at(base+.125,.86,'s',6.8); at(base-.125 if base>0 else .875,.86,'s',6.8)
    at(.75,.55,'s',5.5); at(.25,.55,'s',5.5)
    return cv.out()
def tex_hair():
    W,H=64,128; r=np.random.RandomState(3); a=np.zeros((H,W,3)); lo=A((.62,.33,.12)); mid=A((.86,.54,.20)); hi=A((.96,.70,.32))
    for x in range(W):
        u=x/W; broad=(u<.25) or (.5<=u<.75)
        base=mid if broad else lo*1.08
        col=np.tile(base,(H,1)); 
        t=np.linspace(0,1,H)[:,None]; col=col*(.78+.28*np.sin(t*math.pi))                   # root dark -> bright mid -> darker tip
        col*= (1+r.randn()*.045)
        a[:,x]=col
    for k in range(10):                                                                     # strand streaks (vertical lines)
        x0=r.randint(0,W-1); L=r.randint(30,110); y0=r.randint(0,H-L); sgn=r.choice((-1,1))
        a[y0:y0+L,x0:x0+1+(k%2)]*=1+sgn*.13
    return img(a)
def tex_boots():
    W=H=128; cv=Cv(W,H,(.14,.13,.09),ss=4); a=boucle(W,H,(.15,.14,.10),seed=19,amp=.04); cv=Cv(W,H,im=a,ss=4)
    # lower toe region brown w/ embossed leaf pattern; laces zigzag on shaft; sole
    cv.rect(0,88,W,H,(.40,.24,.15)); cv.poly([(0,86),(W,86),(W,96),(0,96)],(.30,.18,.11))
    for k in range(5):
        y=8+k*15; cv.line([(34,y),(94,y+10)],(.50,.46,.22),2.4); cv.line([(94,y),(34,y+10)],(.50,.46,.22),2.4)
        cv.ell(34,y,2.2,2.2,(.58,.56,.30)); cv.ell(94,y,2.2,2.2,(.58,.56,.30))
    cv.poly([(64,102),(48,92),(52,110),(64,118),(76,110),(80,92)],(.55,.34,.22)); cv.line([(64,94),(64,118)],(.30,.18,.11),1.6)
    for sg in (-1,1): cv.line([(64,106),(64+sg*14,98)],(.30,.18,.11),1.4)
    cv.rect(0,120,W,H,(.20,.12,.08)); return cv.out()
def tex_leather(w=128,h=128,seed=23,base=(.31,.20,.14)):
    a=boucle(w,h,base,seed=seed,amp=.05); return a
def tex_pouch():
    W=H=128; a=boucle(W,H,(.31,.21,.15),seed=24,amp=.05); cv=Cv(W,H,im=a,ss=3); st=(.68,.52,.32)
    for y in range(10,H-10,6): cv.line([(9,y),(9,y+3)],st,1.1); cv.line([(W-9,y),(W-9,y+3)],st,1.1)
    for k in np.linspace(0,math.pi,24): cv.ell(W/2+(W/2-9)*math.cos(k),H-16+16*math.sin(k)*0,0,0,st) if False else None
    for k in np.linspace(0,math.pi,22): cv.line([(W/2+(W/2-9)*math.cos(k),H-22+13*math.sin(k)),(W/2+(W/2-9)*math.cos(k)+1.5,H-22+13*math.sin(k)+1)],st,1.1)
    return cv.out()
def tex_flap():
    W,H=128,96; a=boucle(W,H,(.33,.22,.15),seed=25,amp=.05); cv=Cv(W,H,im=a,ss=3); st=(.66,.50,.30)
    # stitched border (dashes) inset from the edge, following a rounded flap outline
    pts=[]; 
    for t in np.linspace(0,1,60):
        pass
    inset=7
    for x in range(inset+4,W-inset-4,6): cv.line([(x,inset),(x+3,inset)],st,1.1)
    for y in range(inset+4,H-inset-14,6): cv.line([(inset,y),(inset,y+3)],st,1.1); cv.line([(W-inset,y),(W-inset,y+3)],st,1.1)
    for k in np.linspace(math.pi,0,22):
        cx=W/2; x=cx+(W/2-inset)*math.cos(k); y=(H-inset-14)+ (inset+10)*math.sin(k)*-1+ (inset+10)
        cv.ell(x,min(H-inset-2,y),.9,.9,st)
    cv.ell(W/2,H-24,5,5,(.20,.13,.09)); cv.ell(W/2,H-24,3,3,(.45,.38,.28))        # tab rivet
    return cv.out()
def tex_strap():
    W,H=32,128; a=boucle(W,H,(.38,.22,.15),seed=27,amp=.05); cv=Cv(W,H,im=a,ss=3); st=(.72,.55,.34)
    for y in range(3,H,6): cv.line([(4,y),(4,y+3)],st,1.0); cv.line([(W-4,y),(W-4,y+3)],st,1.0)
    cv.rect(0,0,1.5,H,(.22,.13,.09)); cv.rect(W-1.5,0,W,H,(.22,.13,.09)); return cv.out()
BIRD=dict(x0=-.14,y0=-.01,w=.40,h=.34)
def bird_xy(x,y,W=128): return ((x-BIRD['x0'])/BIRD['w']*W,(1-(y-BIRD['y0'])/BIRD['h'])*W)
def tex_bird():
    W=128; cv=Cv(W,W,(.60,.58,.56),ss=4); P_=lambda x,y:bird_xy(x,y,W); S=lambda r:r/BIRD['w']*W
    a=arr(cv.out()); yy,xx=np.mgrid[0:W,0:W]
    # base: back darker (right/top), belly lighter (left/lower)
    X=BIRD['x0']+xx/W*BIRD['w']; Y=BIRD['y0']+(1-yy/W)*BIRD['h']
    belly=np.clip((-X+.02)/.12,0,1)*np.clip((.18-Y)/.18,0,1); col=A((.60,.58,.56))[None,None,:]*(1-belly[...,None])+A((.82,.79,.76))[None,None,:]*belly[...,None]
    cv=Cv(W,W,im=img(col),ss=4)
    cv.ell(*P_(-.03,.235),S(.052),S(.05),(.76,.74,.72))                                  # pale head
    cv.soft(*P_(-.045,.20),S(.03),S(.03),(.88,.85,.80),.5,2)                             # cheek
    # wing: darker with feather steps
    wing=[(.0,.20),(.05,.17),(.11,.11),(.17,.045),(.2,.0),(.14,.02),(.1,.04),(.08,.0),(.045,.04),(.02,.09),(-.01,.15)]
    cv.poly([P_(x,y) for x,y in wing],(.47,.44,.43))
    for k in range(5): cv.line([P_(.02+k*.035,.17-k*.025),P_(.06+k*.04,.075-k*.012)],(.34,.31,.31),1.3)
    cv.poly([P_(x,y) for x,y in [(.06,.2),(.13,.19),(.2,.14),(.14,.14)]],(.70,.67,.66))   # tail base
    cv.poly([P_(x,y) for x,y in [(.07,.20),(.14,.30),(.19,.31),(.11,.19)]],(.78,.75,.74)) # tail feather (pale)
    cv.ell(*P_(-.058,.243),S(.012),S(.012),(.08,.07,.07)); cv.ell(*P_(-.062,.247),S(.004),S(.004),(1,1,.95))  # eye
    cv.poly([P_(x,y) for x,y in [(-.085,.235),(-.1,.225),(-.085,.215)]],(.92,.60,.32))   # beak
    cv.line([P_(-.01,.03),P_(-.01,.0)],(.92,.62,.62),2.0); cv.line([P_(.015,.03),P_(.015,.0)],(.92,.62,.62),2.0)
    return cv.out()
def tex_hand():
    W=H=64; a=boucle(W,H,(.93,.80,.72),seed=29,amp=.03); cv=Cv(W,H,im=a,ss=4)
    for y in (22,42): cv.line([(0,y),(W,y)],(.74,.56,.50),1.3)
    cv.poly([(10,52),(54,52),(50,62),(14,62)],(.97,.88,.82)); cv.line([(10,52),(54,52)],(.80,.62,.56),.9)
    cv.rect(0,0,W,2,(.80,.64,.58)); return cv.out()

def sprite_oak():
    W=H=48; cv=Cv(W,H,(.35,.55,.30),ss=4); cv.im=Image.new('RGB',(W*4,H*4),C((.70,.42,.18))); cv.d=ImageDraw.Draw(cv.im)
    cv.line([(24,44),(24,6)],(.45,.25,.10),1.6)
    for y,l in ((14,14),(22,16),(30,14),(38,9)):
        cv.line([(24,y+6),(24-l,y)],(.45,.25,.10),1.0); cv.line([(24,y+6),(24+l,y)],(.45,.25,.10),1.0)
    cv.soft(24,24,18,22,(.55,.28,.10),.30,6); return cv.out()
def sprite_carrot():
    W,H=32,48; cv=Cv(W,H,(.78,.62,.40),ss=4); cv.soft(16,26,12,24,(.64,.48,.30),.5,5)
    for k in range(5): y=8+k*8; cv.line([(6,y),(26,y+2)],(.55,.40,.24),1.1)
    cv.rect(0,0,W,7,(.45,.36,.20)); return cv.out()
def sprite_lav():
    W,H=32,48; cv=Cv(W,H,(.45,.55,.30),ss=4)
    for k in range(9):
        x=4+k*3; cv.line([(x,46),(16,24)],(.40,.50,.28),1.0)
        for j in range(6): cv.ell(x+ (j%2)*1.2-0.5,8+ j*3.5+(k%3),1.7,1.7,(.60,.44,.72) if (j+k)%3 else (.48,.34,.60))
    return cv.out()
def sprite_shroom():
    W=H=48; cv=Cv(W,H,(.82,.68,.52),ss=4); cv.soft(24,24,18,18,(.66,.50,.36),.5,6)
    for k in range(6): cv.line([(6+k*7,4),(8+k*7,44)],(.62,.46,.32),1.0)
    return cv.out()
def sprite_map():
    W,H=64,48; a=boucle(W,H,(.92,.80,.54),seed=31,amp=.04); cv=Cv(W,H,im=a,ss=4); ink=(.60,.42,.22)
    cv.line([(8,36),(18,26),(28,32),(40,18),(54,22)],ink,1.1); cv.ell(18,26,1.4,1.4,ink); cv.ell(40,18,1.4,1.4,ink)
    cv.poly([(46,32),(52,32),(49,40)],ink); cv.line([(8,10),(30,8)],ink,.9); cv.line([(8,14),(24,13)],ink,.9)
    cv.soft(32,24,34,26,(.70,.52,.28),.30,6); return cv.out()
def sprite_feather():
    W,H=32,64; cv=Cv(W,H,(.60,.64,.56),ss=4); cv.line([(16,2),(16,62)],(.40,.42,.36),1.4)
    for k in range(12):
        y=6+k*4.4; cv.line([(16,y),(3+k*.4,y-5)],(.46,.52,.44),1.0); cv.line([(16,y),(29-k*.4,y-5)],(.46,.52,.44),1.0)
    return cv.out()
def sprite_house():
    W=H=64; cv=Cv(W,H,(.62,.38,.20),ss=4)
    for k in range(10): cv.line([(0,3+k*6),(W,3+k*6)],(.44,.26,.14),1.0)
    cv.rect(0,0,W,3,(.30,.18,.10)); return cv.out()
def tex_wand():
    W=H=32; cv=Cv(W,H,(.92,.78,.84),ss=4); cv.soft(16,16,14,14,(1,.92,.96),.5,6); cv.rect(0,28,W,H,(.74,.56,.66)); return cv.out()
def tex_wood(): return boucle(32,32,(.38,.30,.22),seed=41,amp=.10)

# ================= overrides: bolder embroidery, larger appliqué icons =================
def _smooth(pts,n=3):
    pts=[tuple(p) for p in pts]
    if len(pts)<3: return pts
    Pp=[(2*pts[0][0]-pts[1][0],2*pts[0][1]-pts[1][1])]+pts+[(2*pts[-1][0]-pts[-2][0],2*pts[-1][1]-pts[-2][1])]; out=[]
    for i in range(1,len(Pp)-2):
        p0,p1,p2,p3=Pp[i-1],Pp[i],Pp[i+1],Pp[i+2]
        for k in range(n):
            t=k/n; out.append(tuple(.5*((2*p1[j])+(-p0[j]+p2[j])*t+(2*p0[j]-5*p1[j]+4*p2[j]-p3[j])*t*t+(-p0[j]+3*p1[j]-3*p2[j]+p3[j])*t**3) for j in (0,1)))
    out.append(pts[-1]); return out
def _stroke(cv,pts,w0,w1,bark,bark_d,hi):
    N=len(pts)-1
    for i in range(N): t=i/max(1,N); cv.line(pts[i:i+2],bark_d,(w0+(w1-w0)*t)+1.8)
    for i in range(N): t=i/max(1,N); cv.line(pts[i:i+2],bark,(w0+(w1-w0)*t))
    for i in range(N): t=i/max(1,N); w=(w0+(w1-w0)*t); cv.line([(pts[i][0]-w*.18,pts[i][1]-w*.18),(pts[i+1][0]-w*.18,pts[i+1][1]-w*.18)],hi,max(.8,w*.28))
def tree_of_life(cv,x0,y0,x1,y1,seed=3):
    r=random.Random(seed); W=x1-x0; H=y1-y0
    bark=(.58,.48,.22); bark_d=(.28,.20,.08); hi=(.78,.66,.36); leaf=(.52,.62,.33); leaf_d=(.32,.42,.20); gold=(.90,.74,.62)
    def leafp(x,y,ang,s):
        c,sn=math.cos(ang),math.sin(ang); pts=[]
        for t in np.linspace(0,2*math.pi,10,endpoint=False):
            lx=s*(.5+.5*math.cos(t)); ly=s*.36*math.sin(t); pts.append((x+lx*c-ly*sn,y+lx*sn+ly*c))
        cv.poly(pts,leaf_d); cv.poly([(x+(p[0]-x)*.78+ (x-p[0])*0,y+(p[1]-y)*.78) for p in pts],leaf)
    def branch(px,py,ang,ln,wd,depth):
        pts=[(px,py)]; a=ang; x,y=px,py
        for i in range(5):
            a+=r.uniform(-.34,.34); x+=math.sin(a)*ln/5; y-=math.cos(a)*ln/5; pts.append((x,y))
        pts=_smooth(pts,3); _stroke(cv,pts,wd,max(1.6,wd*.5),bark,bark_d,hi)
        if depth<3:
            for k,t in enumerate((.50,.80)):
                i=int(t*(len(pts)-1)); sg=-1 if (k+depth)%2 else 1
                branch(pts[i][0],pts[i][1],a+sg*r.uniform(.55,.95),ln*r.uniform(.52,.66),wd*.6,depth+1)
            branch(pts[-1][0],pts[-1][1],a+r.uniform(-.3,.3),ln*.5,wd*.55,depth+1)
        else:
            for t in (.6,1.0):
                i=int(t*(len(pts)-1)); leafp(pts[i][0],pts[i][1],a-math.pi/2+r.uniform(-.9,.9),r.uniform(8,11))
    tx=x0+.5*W
    # roots (thick, tapering, spreading)
    for a0,l,wd in ((-1.35,.34,6),(-1.0,.30,6.5),(-.62,.34,7),(-.25,.27,6),(.12,.24,6),(.42,.30,6.5),(.78,.33,7),(1.08,.30,6.5),(1.4,.34,6)):
        x,y=tx+a0*3,y0+.60*H; pts=[(x,y)]; a=math.pi+a0*.52
        for i in range(6):
            a+=r.uniform(-.18,.18)-a0*.025; x+=math.sin(a)*l*H/6; y-=math.cos(a)*l*H/6; pts.append((x,min(y,y0+.995*H)))
        _stroke(cv,_smooth(pts,3),wd,1.6,bark,bark_d,hi)
    # twisted trunk: three braided strands
    for off,w in ((-5,8),(5,8),(0,9)):
        pts=[(tx+off*(1-i/5)*1.0+ (3 if i%2 else -3)*(0.4 if off else 0.0),y0+(.66-i*.032)*H) for i in range(6)]
        _stroke(cv,_smooth(pts,3),w,w*.75,bark,bark_d,hi)
    for a0,l,wd in ((-.95,.46,8.5),(-.5,.52,8.5),(-.08,.56,8.5),(.38,.52,8.5),(.85,.46,8.5),(-1.38,.30,6),(1.28,.30,6)):
        branch(tx+a0*2.5,y0+.52*H,a0,l*H*.95,wd,1)
    def moon(cx,cy,R,rot):
        n=14; o=[(cx+R*math.cos(rot+t),cy+R*math.sin(rot+t)) for t in np.linspace(.6,2*math.pi-.6,n)]
        i=[(cx+R*.42*math.cos(rot)+R*.82*math.cos(rot+t),cy+R*.42*math.sin(rot)+R*.82*math.sin(rot+t)) for t in np.linspace(.75,2*math.pi-.75,n)]
        cv.poly(o+i[::-1],gold)
    def star(cx,cy,R,n=4):
        pts=[]
        for k in range(2*n): rr=R if k%2==0 else R*.32; t=math.pi/2+k*math.pi/n; pts.append((cx+rr*math.cos(t),cy-rr*math.sin(t)))
        cv.poly(pts,gold)
    X=lambda u:x0+u*W; Y=lambda v:y0+v*H
    moon(X(.52),Y(.11),12,-.4); star(X(.60),Y(.15),4.5); moon(X(.17),Y(.70),12.5,.5); star(X(.31),Y(.63),4.5); star(X(.31),Y(.76),4.2)
    moon(X(.82),Y(.64),13,-.2); star(X(.70),Y(.82),4.2); star(X(.90),Y(.80),5); star(X(.5),Y(.99),6.5,4)
def tex_vest2():
    W=256; a=boucle(W,W,(.31,.35,.14),seed=11,amp=.07); cv=Cv(W,W,im=a,ss=3); r=random.Random(5); root=(.66,.52,.28); dk=(.26,.19,.08); hi=(.80,.68,.40)
    def rootline(x,y,ang,ln,wd,depth):
        pts=[(x,y)]; a_=ang
        for i in range(6): a_+=r.uniform(-.28,.28); x+=math.sin(a_)*ln/6; y-=math.cos(a_)*ln/6; pts.append((x,y))
        pts=_smooth(pts,3); _stroke(cv,pts,wd,max(1.2,wd*.5),root,dk,hi)
        if depth<3:
            for t in (.4,.72):
                i=int(t*(len(pts)-1)); rootline(pts[i][0],pts[i][1],a_+r.choice((-1,1))*r.uniform(.5,.9),ln*.5,wd*.66,depth+1)
    for x0,ang,ln in ((.46,.0,.66),(.60,.14,.55),(.34,-.16,.55),(.70,.3,.42),(.24,-.3,.40)):
        rootline(x0*W,.99*W,ang,ln*W*.64,4.6,1)
    return cv.out()
def tex_bib():
    W,H=192,128; a=boucle(W,H,(.46,.12,.25),seed=13,amp=.09); cv=Cv(W,H,im=a,ss=3); r=random.Random(8); root=(.86,.62,.50); dk=(.36,.10,.18); hi=(.97,.80,.68)
    def rootline(x,y,ang,ln,wd,depth):
        pts=[(x,y)]; a_=ang
        for i in range(6): a_+=r.uniform(-.2,.2); x+=math.sin(a_)*ln/6; y+=math.cos(a_)*ln/6; pts.append((x,y))
        pts=_smooth(pts,3); _stroke(cv,pts,wd,max(1.0,wd*.5),root,dk,hi)
        if depth<3:
            for t in (.4,.7):
                i=int(t*(len(pts)-1)); rootline(pts[i][0],pts[i][1],a_+r.choice((-1,1))*r.uniform(.45,.85),ln*.52,wd*.68,depth+1)
    for x0,y0,ang,ln in ((.27,.36,.18,.5),(.73,.34,-.14,.52),(.50,.60,.0,.34)): rootline(x0*W,y0*H,ang,ln*H,3.4,1)
    for sg,x0 in ((1,.08),(-1,.92)): _stroke(cv,_smooth([(x0*W,.34*H),(x0*W+sg*14,.26*H),(x0*W+sg*34,.34*H)],3),2.0,1.2,root,dk,hi)
    return cv.out()

def tex_skirt():
    W,H=1024,160; a=boucle(W,H,(.43,.22,.52),seed=7,amp=.05); arr_=arr(a)
    for f in range(10):
        x0=int(f*W/10); x1=int((f+1)*W/10); arr_[:,x0:x1]*=1.0+(.06 if f%2==0 else -.05)
    cv=Cv(W,H,im=img(arr_),ss=3); r=random.Random(21); shad=(.24,.10,.34)
    kinds=['m','s8','owl','bear','s5','foot','mask','m','s8','s5','antler','bear','owl','m']
    for f in range(10):
        x0=f*W/10; cols=[(.30,.24),(.70,.30),(.32,.66),(.72,.72)] if f%2 else [(.50,.22),(.28,.60),(.70,.64)]
        for (fu,fv) in cols:
            k=r.choice(kinds); cx=x0+W/10*(fu+r.uniform(-.05,.05)); cy=H*(fv+r.uniform(-.05,.05)); R=r.uniform(16,23); rot=r.uniform(-.9,.9); fl=r.choice((1,-1))
            def draw(ox,oy,col,dk):
                if k=='m': ic_crescent(cv,cx+ox,cy+oy,R,rot,col)
                elif k=='s8': ic_star(cv,cx+ox,cy+oy,R,8,col)
                elif k=='s5': ic_star(cv,cx+ox,cy+oy,R,5,col,rot*.3)
                elif k=='owl': ic_owl(cv,cx+ox,cy+oy,R*.95,col,dk)
                elif k=='bear': ic_bear(cv,cx+ox,cy+oy,R*1.05,col,dk,fl)
                elif k=='foot': ic_foot(cv,cx+ox,cy+oy,R*.95,col)
                elif k=='mask': ic_mask(cv,cx+ox,cy+oy,R*.9,col,dk)
                elif k=='antler': ic_antler(cv,cx+ox,cy+oy,R*.95,col)
            col=GOLD if k in('m','s8','s5') else (ROSE if k in('foot','antler','mask') else BRONZE)
            draw(1.8,2.0,shad,shad); draw(0,0,col,(.40,.20,.16))
    return cv.out()

# ============================================================ allocate + paint (one atlas, <= 512 px)
# (name, native w, h, painter, scale into the atlas)
TILES = (('skirt', 1024, 160, lambda: tex_skirt(), .49), ('cape', 384, 384, lambda: tex_cape(), .5),
         ('vest', 256, 256, lambda: tex_vest2(), .5), ('bib', 192, 128, lambda: tex_bib(), .5),
         ('boucle', 128, 128, lambda: boucle(128, 128, (.44, .12, .26), seed=2, amp=.10), .5),
         ('mantle', 128, 128, lambda: tex_felt((.31, .34, .13), 12), .5), ('boots', 128, 128, lambda: tex_boots(), .5),
         ('bird', 128, 128, lambda: tex_bird(), .5), ('pouch', 128, 128, lambda: tex_pouch(), .5),
         ('flap', 128, 96, lambda: tex_flap(), .5), ('sleeve', 256, 96, lambda: tex_sleeve(), .5),
         ('hair', 64, 128, lambda: tex_hair(), .5), ('strap', 32, 128, lambda: tex_strap(), .5),
         ('house', 64, 64, lambda: sprite_house(), .5), ('oak', 48, 48, lambda: sprite_oak(), 1.),
         ('carrot', 32, 48, lambda: sprite_carrot(), 1.), ('lav', 32, 48, lambda: sprite_lav(), 1.),
         ('shroom', 48, 48, lambda: sprite_shroom(), .67), ('map', 64, 48, lambda: sprite_map(), .75),
         ('feather', 32, 64, lambda: sprite_feather(), .75), ('wood', 32, 32, lambda: tex_wood(), 1.),
         ('hoodtip', 64, 64, lambda: boucle(64, 64, (.40, .10, .23), seed=44, amp=.10), 1.))


def build_atlas(at):
    """Allocate and paint every tile into `at` (an atlas.Atlas)."""
    for name, w, h, paint, sc in TILES:
        at.alloc(name, w, h, sc)
    for name, w, h, paint, sc in TILES:
        at.paste(name, paint())
    return at
