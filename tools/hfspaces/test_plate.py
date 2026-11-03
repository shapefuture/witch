#!/usr/bin/env python3
"""Offline checks for plate.py (no network, no quota): python3 tools/hfspaces/test_plate.py"""
import json
import os
import sys
import tempfile
import types
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
import plate  # noqa: E402

FAKE = "hf_" + "x" * 34                     # shaped like a token, not one


class FakeJob:
    def __init__(self, answer):
        self.answer = answer

    def result(self, timeout=None):
        if isinstance(self.answer, Exception):
            raise self.answer
        return self.answer


class FakeClient:
    """Stands in for gradio_client.Client: records what was sent and answers with a picture (or raises)."""
    made = []
    answers = {}

    def __init__(self, space_id, token=None, verbose=False, download_files=None, analytics_enabled=True):
        self.space_id, self.token, self.analytics = space_id, token, analytics_enabled
        self.download = Path(download_files)
        self.sent = []
        FakeClient.made.append(self)

    def submit(self, api_name=None, **args):
        self.sent.append((api_name, args))
        answer = FakeClient.answers[self.space_id]
        if isinstance(answer, Exception):
            return FakeJob(answer)
        from PIL import Image
        self.download.mkdir(parents=True, exist_ok=True)
        path = self.download / "image.webp"
        Image.new("RGB", (64, 36), (120, 40, 160)).save(path, "WEBP")
        return FakeJob((str(path), args.get("seed")))


def fake_gradio():
    module = types.ModuleType("gradio_client")
    module.Client = FakeClient
    module.handle_file = lambda p: {"path": p, "meta": {"_type": "gradio.FileData"}}
    return module


class Quota:
    """A quota that a successful call spends: 4 s and one run."""

    def __init__(self, seconds=300.0, runs=8):
        self.seconds, self.runs = seconds, runs

    def __call__(self):
        return {"seconds": self.seconds, "of": 300.0, "runs": self.runs, "runs_of": 8, "resets_at": None}

    def spend(self, seconds=4.0):
        self.seconds -= seconds
        self.runs -= 1


class PlateTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.env = mock.patch.dict(os.environ, {"HF_ENV_FILE": str(self.tmp / "none.env")}, clear=False)
        self.env.start()
        os.environ.pop(plate.TOKEN_NAME, None)
        FakeClient.made, FakeClient.answers = [], {}
        self.modules = mock.patch.dict(sys.modules, {"gradio_client": fake_gradio()})
        self.modules.start()
        self.quota = Quota()
        self.patches = [mock.patch.object(plate, "quota", self.quota),
                        mock.patch.object(plate, "space_state", lambda sid: {"stage": "RUNNING", "hardware": "zero-a10g", "sha": "abc"}),
                        mock.patch.object(plate.time, "sleep", lambda s: None)]
        for p in self.patches:
            p.start()

    def tearDown(self):
        for p in self.patches:
            p.stop()
        self.modules.stop()
        self.env.stop()
        plate._secret["value"] = ""

    def env_file(self, text):
        path = self.tmp / "test.env"
        path.write_text(text, encoding="utf-8")
        os.environ["HF_ENV_FILE"] = str(path)

    def test_token_from_file_and_environment_wins(self):
        self.env_file("OTHER=1\nexport %s=\"%s\"\n" % (plate.TOKEN_NAME, FAKE))
        self.assertEqual(plate.load_token(), (FAKE, "test.env"))
        os.environ[plate.TOKEN_NAME] = "hf_" + "y" * 34
        self.assertEqual(plate.load_token(), ("hf_" + "y" * 34, "environment"))

    def test_missing_token_sends_nothing(self):
        out = self.tmp / "a"
        self.assertEqual(plate.chain("gen", ("schnell",), {"prompt": "p", "seed": 1, "size": (64, 36)}, out), 2)
        self.assertEqual(FakeClient.made, [])

    def test_scrub_hides_the_token(self):
        self.env_file("%s=%s\n" % (plate.TOKEN_NAME, FAKE))
        plate.load_token()
        self.assertNotIn(FAKE, plate.scrub("401 for Bearer %s at x" % FAKE))

    def test_guard_refuses_before_sending(self):
        self.env_file("%s=%s\n" % (plate.TOKEN_NAME, FAKE))
        self.quota.seconds = 50.0                              # dev asks for 75 s
        out = self.tmp / "b"
        self.assertEqual(plate.chain("gen", ("dev",), {"prompt": "p", "seed": 1, "size": (64, 36)}, out), 1)
        self.assertEqual(FakeClient.made, [])
        record = json.loads((self.tmp / "b.json").read_text())
        self.assertFalse(record["ok"])
        self.assertEqual(record["attempts"][0]["outcome"], "Refused")
        self.quota.seconds, self.quota.runs = 300.0, 0          # no runs left: refused too
        self.assertEqual(plate.chain("gen", ("schnell",), {"prompt": "p", "seed": 1, "size": (64, 36)}, out), 1)
        self.assertEqual(FakeClient.made, [])

    def test_qwen_counts_double(self):
        self.env_file("%s=%s\n" % (plate.TOKEN_NAME, FAKE))
        self.quota.seconds = 200.0                             # 120 s on xlarge is 240 s of quota
        with self.assertRaises(plate.Refused):
            plate.run_one("qwen", "gen", {"prompt": "p", "seed": 1, "size": (64, 36)}, self.tmp / "q")

    def test_auto_falls_through_in_order_and_records(self):
        self.env_file("%s=%s\n" % (plate.TOKEN_NAME, FAKE))
        FakeClient.answers = {"black-forest-labs/FLUX.1-schnell": RuntimeError("You have exceeded your free GPU quota (60s requested vs. 12s left)"),
                              "Qwen/Qwen-Image-2512": RuntimeError("The upstream Gradio app has raised an exception"),
                              "black-forest-labs/FLUX.1-dev": "picture"}
        out = self.tmp / "c"
        self.assertEqual(plate.chain("gen", plate.GEN_ORDER, {"prompt": "a marsh", "seed": 3, "size": (1536, 864)}, out), 0)
        self.assertEqual([c.space_id for c in FakeClient.made], ["black-forest-labs/FLUX.1-schnell", "Qwen/Qwen-Image-2512",
                                                                  "black-forest-labs/FLUX.1-dev"])
        self.assertTrue(all(c.analytics is False and c.token == FAKE for c in FakeClient.made))
        record = json.loads((self.tmp / "c.json").read_text())
        self.assertEqual([a["outcome"] for a in record["attempts"]], ["QuotaError", "SpaceError", "ok"])
        self.assertEqual(record["space"], "black-forest-labs/FLUX.1-dev")
        self.assertEqual(record["calls"][0]["arguments"]["seed"], 3)
        self.assertEqual(record["calls"][0]["arguments"]["width"], 1536)
        self.assertEqual(record["returned_format"], "webp")
        self.assertTrue((self.tmp / "c.png").exists() and (self.tmp / "c.webp").exists())
        self.assertFalse((self.tmp / "c.download").exists())
        self.assertNotIn(FAKE, (self.tmp / "c.json").read_text())

    def test_every_space_failing_is_recorded_once_each(self):
        self.env_file("%s=%s\n" % (plate.TOKEN_NAME, FAKE))
        FakeClient.answers = {sid: RuntimeError("the upstream Gradio app has raised an exception (%s)" % FAKE)
                              for sid in ("black-forest-labs/FLUX.1-schnell", "Qwen/Qwen-Image-2512", "black-forest-labs/FLUX.1-dev")}
        out = self.tmp / "g"
        self.assertEqual(plate.chain("gen", plate.GEN_ORDER, {"prompt": "p", "seed": 1, "size": (64, 36)}, out), 1)
        self.assertEqual(len(FakeClient.made), 3)                    # each tried once, nothing retried
        text = (self.tmp / "g.json").read_text()
        self.assertEqual([a["outcome"] for a in json.loads(text)["attempts"]], ["SpaceError"] * 3)
        self.assertNotIn(FAKE, text)                                # the token in an error message is scrubbed
        self.assertFalse((self.tmp / "g.download").exists())

    def test_qwen_never_asks_for_the_prompt_rewriter(self):
        self.env_file("%s=%s\n" % (plate.TOKEN_NAME, FAKE))
        FakeClient.answers = {"Qwen/Qwen-Image-2512": "picture", "Qwen/Qwen-Image-Edit": "picture"}
        plate.run_one("qwen", "gen", {"prompt": "p", "seed": 1, "size": (1536, 864)}, self.tmp / "d")
        sent = FakeClient.made[-1].sent[0][1]
        self.assertIs(sent["prompt_enhance"], False)
        self.assertEqual(sent["aspect_ratio"], "16:9")
        source = self.tmp / "in.png"
        from PIL import Image
        Image.new("RGB", (32, 18)).save(source)
        record = plate.run_one("qwen-edit", "edit", {"prompt": "p", "seed": 1, "size": (0, 0), "image": source}, self.tmp / "e")
        self.assertIs(FakeClient.made[-1].sent[0][1]["rewrite_prompt"], False)
        self.assertEqual(record["calls"][0]["arguments"]["image"], {"file": "in.png"})
        self.assertEqual(record["input_image"]["file"], str(source))

    def test_dry_run_sends_nothing(self):
        self.env_file("%s=%s\n" % (plate.TOKEN_NAME, FAKE))
        self.assertEqual(plate.chain("gen", plate.GEN_ORDER, {"prompt": "p", "seed": 1, "size": (64, 36)}, self.tmp / "f", dry_run=True), 0)
        self.assertEqual(FakeClient.made, [])
        self.assertFalse((self.tmp / "f.json").exists())

    def test_fit_crops_to_the_aspect(self):
        from PIL import Image
        src = self.tmp / "wide.png"
        im = Image.new("RGB", (1664, 928), (0, 0, 255))        # Qwen's 16:9 is 1.793, a little wider than 16:9
        im.paste((255, 0, 0), (0, 0, 7, 928))                  # a red band at the far left is cropped away
        im.save(src)
        out = plate.fit(src, self.tmp / "fit.png")
        with Image.open(out) as fitted:
            self.assertEqual(fitted.size, (1280, 720))
            self.assertEqual(fitted.getpixel((0, 360)), (0, 0, 255))

    def test_erase_paints_out_marks_and_nothing_else(self):
        import numpy as np
        from PIL import Image
        a = np.zeros((60, 80, 3), np.uint8)
        a[:, :] = np.linspace(180, 230, 80).astype(np.uint8)[None, :, None]   # a cream face with a gradient
        a[20:30, 30:34] = 20                                                  # a "1"
        a[10:14, 60:70] = 15                                                  # a dark mark outside the box: kept
        src, dst = self.tmp / "clock.png", self.tmp / "clock_clean.png"
        Image.fromarray(a).save(src)
        changed = plate.erase(src, dst, [(26, 16, 40, 34)])
        b = np.asarray(Image.open(dst))
        self.assertGreaterEqual(changed, 40)
        self.assertLess(int(np.abs(b[20:30, 30:34].astype(int) - a[20:30, 29:30].astype(int)).max()), 8)   # filled like its neighbours
        outside = np.ones((60, 80), bool)
        outside[16:34, 26:40] = False
        self.assertTrue((b[outside] == a[outside]).all())
        self.assertEqual(plate.box_arg("1, 2,30,40"), (1, 2, 30, 40))

    def test_declared_gpu(self):
        self.assertEqual(plate.declared_gpu("@spaces.GPU()\ndef infer(): pass"), ("60", "large"))
        self.assertEqual(plate.declared_gpu("@spaces.GPU\ndef infer(): pass"), ("60", "large"))
        self.assertEqual(plate.declared_gpu('@spaces.GPU(duration=120, size="xlarge")\ndef f(): pass'), ("120", "xlarge"))
        self.assertEqual(plate.declared_gpu("@spaces.GPU(duration=generation_duration)\ndef f(): pass"), ("generation_duration", "large"))
        self.assertEqual(plate.declared_gpu("def f(): pass"), (None, None))

    def test_registry_matches_the_calls(self):
        self.assertEqual(set(plate.SPACES), set(plate.CALLS))
        self.assertEqual(plate.GEN_ORDER, ("schnell", "qwen", "dev"))
        for key in plate.GEN_ORDER:
            self.assertIn("gen", plate.SPACES[key]["modes"])
        for key in ("kontext", "qwen-edit"):
            self.assertIn("edit", plate.SPACES[key]["modes"])


if __name__ == "__main__":
    unittest.main(verbosity=1)
