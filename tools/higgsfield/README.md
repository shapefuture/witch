# Higgsfield (image, video and audio generation)

`hf.py` drives the [Higgsfield API](https://docs.higgsfield.ai) through the official Python SDK
(`higgsfield-client`, pinned in `requirements.txt` because `hf.py` uses its transport).

```sh
pip install -r tools/higgsfield/requirements.txt
cp .env.example .env.local        # then fill in HF_KEY=key-id:key-secret (git-ignored)
python tools/higgsfield/hf.py check
python tools/higgsfield/hf.py estimate bytedance/seedance-2.5/text-to-video --args '{"prompt": "...", "duration": 5}'
python tools/higgsfield/hf.py run bytedance/seedance-2.5/text-to-video --args-file job.json --max-usd 1.50
python tools/higgsfield/hf.py run <image-to-video model> --args '{"prompt": "..."}' --upload image_url=ref.png --max-usd 1
python tools/higgsfield/hf.py resume build/higgsfield/<job>    # after a crash or timeout
python tools/higgsfield/test_hf.py                              # offline tests (mock API)
```

How a request goes:

1. **Estimate** (`POST /estimate/<model>` with the same arguments; free). `run` refuses when the
   price is above `--max-usd`, which is required.
2. **Submit** (`POST /<model>`) with an `Idempotency-Key` that is written to `job.json` first. The
   SDK retries 408/429/5xx; the key makes a retried or resumed submit cost once.
3. **Poll** the returned `status_url` with backoff until `completed`, `failed`, `nsfw` or
   `canceled`. Only `completed` is charged.
4. **Download** at once: outputs live only about 7 days. Images come from `images[]`, video from
   `video.url`, audio from `audio` / `audios[]`. Downloads go out without the API key.

Each job is a folder under `build/higgsfield/` (git-ignored, and `.gdignore`d so Godot doesn't import
raw generations) holding the outputs and `job.json`: model, arguments, estimate, idempotency key,
request id, final status and result, and every file with its sha256. Copy what you keep into
`assets/` and commit it with the `job.json` beside it as its provenance.

Model paths and their parameters are on [console.higgsfield.ai/models](https://console.higgsfield.ai/models);
the price depends on the parameters, so estimate with the exact arguments you will run.

The cloud environment must allow `api.higgsfield.ai` (and the storage host the outputs are served from)
in its network settings.
