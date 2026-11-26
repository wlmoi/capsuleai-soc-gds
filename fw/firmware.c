/* CapsuleAI SoC firmware: run one frame through the CNN engine and make the triage decision.
 * Decision (as in WP1): exit if z_exit[normal] - z_exit[abnormal] >= T_EXIT  -> class 0 (normal);
 * otherwise argmax of the head logits after lowering the normal logit by DELTA. */
#include "params.h"
#define ENG(o)  (*(volatile unsigned *)(0x10000000u + (o)))
#define GPIO    (*(volatile unsigned *)0x20000000u)
#define DBG     (*(volatile unsigned *)0x20000004u)

static long long rd48(unsigned off) {
    unsigned lo = ENG(off);
    int hi = (int)ENG(off + 4);
    return ((long long)hi << 32) | lo;
}

void main(void) {
    ENG(0x00) = 1;                               /* start */
    while (!(ENG(0x04) & 2)) ;                   /* wait for done */
    long long e0 = rd48(0x80), e1 = rd48(0x88);
    int cls = 0, exited = 0;
    if (e0 - e1 >= T_EXIT) {
        exited = 1;
    } else {
        long long best = rd48(0x40) - DELTA;
        for (int j = 1; j < 4; j++) {
            long long z = rd48(0x40 + 8 * j);
            if (z > best) { best = z; cls = j; }
        }
    }
    DBG = ENG(0x08);                             /* engine cycles */
    GPIO = 0xCA000000u | (exited << 8) | cls;    /* result + signature */
    for (;;) ;
}
