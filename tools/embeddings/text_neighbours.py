#!/usr/bin/env python3
"""Meaning-level checks over the text table (data/text/ru.json), using nim.py's embeddings. Offline, for authors.

    python3 tools/embeddings/text_neighbours.py dupes            # lines that say nearly the same thing
    python3 tools/embeddings/text_neighbours.py rhymes           # same meaning, different words (motif candidates)
    python3 tools/embeddings/text_neighbours.py query "..."      # the closest lines to a phrase

`dupes` catches accidental repetition (a reworded line that now duplicates another). `rhymes` borrows the echo
rule from room_engine (high cosine, low word overlap): two lines that mean the same thing in different words are
candidates for an authored motif, never applied automatically. Prints keys and scores; writes nothing to the repo.
Calibration (2026-10-16, this model, 108 lines): the median pair scores 0.59, the top 1% 0.84, the top 0.1%
0.93; the defaults sit at the top 1% (rhymes) and the top 0.1% (dupes). Short lines score high by default.
EMBED_MOCK=1 runs without the network (scores are then meaningless; only the plumbing is tested).
"""
import argparse
import json
import os
import re
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from nim import REPO, embed  # noqa: E402

TEXT = os.path.join(REPO, 'data', 'text', 'ru.json')


def lines():
    table = json.load(open(TEXT, encoding='utf-8'))
    return [(k, v) for k, v in table.items() if not k.startswith('_') and isinstance(v, str) and v.strip()]


def words(text):
    return set(re.findall(r'\w+', text.lower()))


def jaccard(a, b):
    a, b = words(a), words(b)
    return len(a & b) / max(1, len(a | b))


def pairs(items, vectors, keep):
    sims = vectors @ vectors.T
    out = []
    for i in range(len(items)):
        for j in range(i + 1, len(items)):
            s = float(sims[i, j])
            if keep(s, items[i][1], items[j][1]):
                out.append((s, items[i][0], items[j][0], jaccard(items[i][1], items[j][1])))
    return sorted(out, reverse=True)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    d = sub.add_parser('dupes')
    d.add_argument('--min', type=float, default=0.92, help='cosine at or above which two lines count as duplicates')
    r = sub.add_parser('rhymes')
    r.add_argument('--min', type=float, default=0.84, help='cosine at or above which two lines share a meaning')
    r.add_argument('--max-words', type=float, default=0.20, help='word overlap (Jaccard) at or below which they differ in words')
    q = sub.add_parser('query')
    q.add_argument('text')
    q.add_argument('-k', type=int, default=5)
    a = ap.parse_args(argv)

    items = lines()
    vectors = embed([v for _, v in items], 'passage')
    if a.cmd == 'query':
        scores = (embed([a.text], 'query') @ vectors.T)[0]
        for i in np.argsort(-scores)[:a.k]:
            print('%.3f  %s' % (scores[i], items[i][0]))
        return 0
    if a.cmd == 'dupes':
        found = pairs(items, vectors, lambda s, x, y: s >= a.min)
    else:
        found = pairs(items, vectors, lambda s, x, y: s >= a.min and jaccard(x, y) <= a.max_words)
    for s, k1, k2, jac in found:
        print('%.3f  words %.2f  %s  ~  %s' % (s, jac, k1, k2))
    print('%d lines, %d pairs' % (len(items), len(found)), file=sys.stderr)
    return 0


if __name__ == '__main__':
    sys.exit(main())
