#!/usr/bin/env python3
"""Text embeddings through NVIDIA NIM (`nvidia/nemotron-3-embed-1b`), for offline tools only.

The game never calls this: embeddings are a build-time aid (finding near-duplicate lines in the text table,
suggesting motif rhymes to an author, the private tone study). Nothing here ships.

    from nim import embed
    D = embed(passages, 'passage')     # documents you index
    q = embed([question], 'query')     # what you search with (the model is asymmetric)
    scores = q @ D.T                   # rows are unit length, so a dot product is a cosine

The key is read from the environment variable NVIDIA_NIM_KEY and is never printed, logged or written. Results
are cached under .cache/embeddings/ (git-ignored), keyed by model, input type and text, so a rerun costs nothing.
rerank(question, passages) reorders a short candidate list (nvidia/nemotron-3.5-rerank-8b); logits compare only within one question.
EMBED_MOCK=1 returns deterministic hash vectors with no network, for tests of the plumbing.
"""
import hashlib
import json
import os
import time
import urllib.error
import urllib.request

import numpy as np

URL = 'https://integrate.api.nvidia.com/v1/embeddings'
MODEL = 'nvidia/nemotron-3-embed-1b'
DIMS = 2048
BATCH = 32
REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CACHE_DIR = os.path.join(REPO, '.cache', 'embeddings')


def _key(text, input_type):
    return hashlib.sha256(('%s\0%s\0%s' % (MODEL, input_type, text)).encode('utf-8')).hexdigest()


def _cache_path():
    return os.path.join(CACHE_DIR, MODEL.replace('/', '_') + '.npz')


def _load_cache():
    path = _cache_path()
    if not os.path.exists(path):
        return {}
    data = np.load(path)
    return {k: data[k] for k in data.files}


def _save_cache(cache):
    os.makedirs(CACHE_DIR, exist_ok=True)
    tmp = _cache_path() + '.tmp.npz'
    np.savez(tmp, **cache)
    os.replace(tmp, _cache_path())


def _mock(texts):
    out = []
    for t in texts:
        seed = int.from_bytes(hashlib.sha256(t.encode('utf-8')).digest()[:8], 'little')
        out.append(np.random.default_rng(seed).standard_normal(DIMS))
    return out


RERANK_URL = 'https://ai.api.nvidia.com/v1/retrieval/nvidia/nemotron-3.5-rerank-8b/reranking'
RERANK_MODEL = 'nvidia/nemotron-3.5-rerank-8b'
# Rate limits and transient server errors are retried with growing waits; any other status fails at once.
RETRY_CODES = (429, 500, 502, 503, 504)


def _post(url, body):
    key = os.environ.get('NVIDIA_NIM_KEY')
    if not key:
        raise RuntimeError('NVIDIA_NIM_KEY is not set (or set EMBED_MOCK=1 for an offline run)')
    data = json.dumps(body).encode('utf-8')
    for attempt in range(4):
        req = urllib.request.Request(url, data=data, method='POST', headers={
            'Authorization': 'Bearer ' + key, 'Content-Type': 'application/json'})
        try:
            return json.load(urllib.request.urlopen(req, timeout=120))
        except urllib.error.HTTPError as e:
            if e.code in RETRY_CODES and attempt < 3:
                time.sleep(5 * (attempt + 1))
                continue
            raise RuntimeError('NIM HTTP %d' % e.code) from None   # never echo the request: it holds the key
        except urllib.error.URLError:
            if attempt < 3:
                time.sleep(5 * (attempt + 1))
                continue
            raise RuntimeError('NIM unreachable after retries') from None
    raise RuntimeError('NIM: retries exhausted')


def _request(texts, input_type):
    resp = _post(URL, {'model': MODEL, 'input': texts, 'input_type': input_type, 'encoding_format': 'float'})
    return [d['embedding'] for d in sorted(resp['data'], key=lambda d: d['index'])]


def rerank(question, passages):
    """Relevance logit of each passage for the question, in the order given (higher is better).

    Only for reordering a short candidate list from embed(), never for searching a corpus. A logit is comparable
    within one question, not across questions.
    """
    if os.environ.get('EMBED_MOCK') == '1':
        return np.asarray([np.random.default_rng(int.from_bytes(hashlib.sha256(
            (question + '\0' + p).encode('utf-8')).digest()[:8], 'little')).standard_normal() for p in passages])
    resp = _post(RERANK_URL, {'model': RERANK_MODEL, 'query': {'text': question},
                              'passages': [{'text': p} for p in passages]})
    logit = {r['index']: r['logit'] for r in resp['rankings']}
    return np.asarray([logit[i] for i in range(len(passages))], dtype=np.float64)


def embed(texts, input_type):
    """Unit-length float32 rows, one per text. input_type is 'query' or 'passage'."""
    if input_type not in ('query', 'passage'):
        raise ValueError("input_type must be 'query' or 'passage'")
    texts = list(texts)
    if os.environ.get('EMBED_MOCK') == '1':
        v = np.asarray(_mock(texts), dtype=np.float32)
    else:
        cache = _load_cache()
        keys = [_key(t, input_type) for t in texts]
        todo = [i for i, k in enumerate(keys) if k not in cache]
        for s in range(0, len(todo), BATCH):
            idx = todo[s:s + BATCH]
            for i, vec in zip(idx, _request([texts[i] for i in idx], input_type)):
                cache[keys[i]] = np.asarray(vec, dtype=np.float32)
        if todo:
            _save_cache(cache)
        v = np.asarray([cache[k] for k in keys], dtype=np.float32).reshape(len(texts), DIMS)
    return v / np.maximum(np.linalg.norm(v, axis=1, keepdims=True), 1e-12)
