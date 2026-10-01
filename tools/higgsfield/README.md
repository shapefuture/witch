# Higgsfield (image and video generation)

`hf.py` drives the [Higgsfield API](https://docs.higgsfield.ai/docs/llms.txt) through the official Python SDK
(`higgsfield-client`, pinned in `requirements.txt` because `hf.py` uses its transport).

```sh
pip install -r tools/higgsfield/requirements.txt
cp .env.example .env.local        # then fill in HF_KEY=key-id:key-secret (git-ignored)
python tools/higgsfield/hf.py check
python tools/higgsfield/hf.py models edit                      # search the live listing
python tools/higgsfield/hf.py schema alibaba/qwen-image-3/edit   # a model's input schema
python tools/higgsfield/hf.py estimate alibaba/qwen-image-3/edit --args '{"prompt": "...", "image_urls": ["https://..."]}'
python tools/higgsfield/hf.py run alibaba/qwen-image-3/edit --args-file job.json --upload image_urls=ref.png --max-usd 0.10
python tools/higgsfield/hf.py run bytedance/seedance-2.5/image-to-video --args-file clip.json --upload image_url=still.png \
    --max-usd 3 --allow-unpriced                               # per-second models have no fixed estimate
python tools/higgsfield/hf.py resume build/higgsfield/<job>    # after a crash or timeout
python tools/higgsfield/hf.py catalog                          # refresh catalog/ (about a minute, free)
python tools/higgsfield/test_hf.py                             # offline tests (mock API)
```

## The catalog

`catalog/CATALOG.md` lists every model this account can call: path, operation, required inputs, the main
options and a baseline price, with a link to its docs page. `catalog/models.json` holds the full input
schemas, the docs links and the raw estimates. Both are written by `hf.py catalog` from
`GET /models?include_schema=true` (an authenticated listing the docs don't advertise; the per-model docs
pages remain the authority) plus a crawl of the docs. Refresh it when a model you need is missing.

What the catalog showed on 2026-10-01 (83 models: 16 image, 67 video):

- **No masks.** Every image edit is instruction-based: a prompt plus reference images. To change part of a
  picture, edit the whole image, then blend the result back over the original locally with our own mask so
  the untouched pixels stay exact.
- **No audio-only and no image-to-3D models.** Some video models generate a soundtrack (`generate_audio`).
- **Some schemas under-report what is required** (Kling O3 wants `prompt`, reference-to-video models want
  `video_urls` / `audio_urls`); the estimate's refusal names the missing field, and the catalog shows it.
- **Per-second models** (Seedance and others) answer the estimate with a description, not a number:
  Seedance 2.5 is about $0.21/s at 480p, $0.46/s at 720p (the default) and $1.14/s at 1080p.

## Models that fit this project

For the plate plan in `docs/art/plates.md` (the painted reference as the wide plate, other shots and
characters from it), baseline prices at defaults:

| Need | Model | Why | Baseline |
|---|---|---|---|
| Clean plate (remove the witch and raccoon), outpaint to 21:9, variants | `alibaba/qwen-image-3/edit` | up to 3 references, 21:9 output, `seed` and `negative_prompt` for repeatable edits, 2k | $0.040 |
| Edits that must hold the input closely | `ideogram/v4.0` | `image_weight` 1-100 sets how much of the input is kept; 22:9 and 23:9 outputs | $0.060 |
| Many references at once (style + layout + character sheets) | `xai/grok-imagine-image-2.0` | up to 10 references | $0.060 |
| Highest resolution (4k) and up to 16 references | `marketing-studio/image` | 4k, 21:9; ten times the price at its default (high quality, 2k) | $0.439 |
| Cheap drafts | `higgsfield-ai/soul/v2/image-to-image` | 1080p at most, `seed`, batch of 4 | $0.004 |
| Motion studies from a still (parallax, cloth, dust) | `kling-video/v2.5-turbo/standard/image-to-video`, `alibaba/wan-3.0/image-to-video` | the cheapest image-to-video | see catalog |

## API rules (from the docs, 2026-10-01)

| Topic | Rule | hf.py |
|---|---|---|
| [Requests](https://docs.higgsfield.ai/docs/concepts/requests.md) | `queued` -> `in_progress` -> `completed` / `failed` / `nsfw` / `canceled`; use the returned `status_url` | polls `status_url` |
| [Polling](https://docs.higgsfield.ai/docs/concepts/polling.md) | start at 2 s, grow to 10 s, add jitter; retry network errors and 5xx | same |
| [Idempotency](https://docs.higgsfield.ai/docs/concepts/idempotency.md) | one key per intended generation; resend the same body with the same key after an ambiguous failure; a changed body with a used key is a 422 | key stored in `job.json` before submitting; `resume` reuses it |
| [Errors](https://docs.higgsfield.ai/docs/concepts/errors.md) | 400 bad input or concurrency reached, 401 credentials, 403 insufficient credits, 422 validation, 423 model blocked, 503 model not ready; keep `X-Correlation-ID` for support | correlation id in `job.json` |
| [Rate limits](https://docs.higgsfield.ai/docs/concepts/rate-limits.md) | the limit is concurrency (2 on this account until $25 is added in 28 days; see the console) | one job at a time |
| [Uploads](https://docs.higgsfield.ai/docs/concepts/file-uploads.md) | presigned URL, valid 1 h; jpeg, png, webp, gif, wav, mp4; never send the API key to storage | `--upload FIELD=PATH` |
| [Billing](https://docs.higgsfield.ai/docs/concepts/billing-and-retention.md) | only `completed` is charged; a canceled queued request is refunded; outputs are kept at least 7 days; credits expire after a year | downloads at once |
| [SDK](https://docs.higgsfield.ai/docs/how-to/sdk.md) | `HF_KEY` or `HF_API_KEY` + `HF_API_SECRET`; `subscribe`, `submit`, `status`, `result`, `cancel`, `upload_file` | wraps the SDK transport |

Also in the docs: [webhooks](https://docs.higgsfield.ai/docs/how-to/webhooks.md) (not used: this container
has no public URL), the [OpenAPI file](https://docs.higgsfield.ai/docs/openapi.json) (supplementary), the
[model reference](https://docs.higgsfield.ai/docs/models.md) and the [console](https://console.higgsfield.ai).

## Jobs

Each job is a folder under `build/higgsfield/` (git-ignored, and `.gdignore`d so Godot doesn't import raw
generations) holding the outputs and `job.json`: model, arguments, estimate, idempotency key, request id,
correlation id, final status and result, and every file with its sha256. Copy what you keep into `assets/`
and commit it with its `job.json` beside it as provenance.
