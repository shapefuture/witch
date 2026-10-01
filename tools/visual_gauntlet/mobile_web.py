#!/usr/bin/env python3
"""Plays the real exported game (Web build) in a phone-sized touch browser and takes pictures.

    godot --headless --export-release "Web (mobile test build)" build/web/index.html
    python tools/visual_gauntlet/mobile_web.py build/web out_dir [--device "Pixel 7 landscape"]

Needs `playwright` and a Chromium (set PLAYWRIGHT_BROWSERS_PATH or CHROMIUM_PATH). It drives the game
with real touch events (page.touchscreen.tap): wait for the arrival beat, tap through the narration,
tap the brass machine, read the wooden plaques, tap one. Proves touch -> intent -> Mirror -> 3D UI
in an actual mobile-class browser, not just the desktop build.
"""
import asyncio
import glob
import http.server
import os
import socketserver
import sys
import threading

from playwright.async_api import async_playwright


def serve(directory, port=0):
    handler = lambda *a, **k: http.server.SimpleHTTPRequestHandler(*a, directory=directory, **k)
    httpd = socketserver.TCPServer(("127.0.0.1", port), handler)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    return httpd


async def main():
    build, out = sys.argv[1], sys.argv[2]
    device_name = sys.argv[sys.argv.index("--device") + 1] if "--device" in sys.argv else "Pixel 7 landscape"
    os.makedirs(out, exist_ok=True)
    httpd = serve(build)
    url = "http://127.0.0.1:%d/index.html" % httpd.server_address[1]
    exe = os.environ.get("CHROMIUM_PATH") or (glob.glob("/opt/pw-browsers/chromium-*/chrome-linux*/chrome") + glob.glob("/opt/pw-browsers/chromium-*/*/chrome"))[0]
    async with async_playwright() as p:
        browser = await p.chromium.launch(executable_path=exe, args=["--no-sandbox", "--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"])
        device = p.devices[device_name]
        context = await browser.new_context(**device)
        page = await context.new_page()
        logs = []
        page.on("console", lambda m: logs.append(m.text))
        await page.goto(url)
        await page.wait_for_timeout(20000)
        await page.screenshot(path=os.path.join(out, "01_boot.png"))
        vp = page.viewport_size
        # tap through the narration (a tap completes the typing, the next one dismisses the line)
        for i in range(6):
            await page.touchscreen.tap(vp["width"] * 0.5, vp["height"] * 0.55)
            await page.wait_for_timeout(900)
        await page.screenshot(path=os.path.join(out, "02_after_narration.png"))
        # the machine, roughly where the capture shows it (left of centre, low)
        await page.touchscreen.tap(vp["width"] * 0.375, vp["height"] * 0.67)
        await page.wait_for_timeout(4000)
        await page.screenshot(path=os.path.join(out, "03_options.png"))
        # choose the second plaque by touch
        await page.touchscreen.tap(vp["width"] * 0.70, vp["height"] * 0.68)
        await page.wait_for_timeout(5000)
        await page.screenshot(path=os.path.join(out, "04_after_choice.png"))
        with open(os.path.join(out, "console.txt"), "w") as f:
            f.write("\n".join(logs[-80:]))
        await browser.close()
    httpd.shutdown()
    print("pictures in", out)


asyncio.run(main())
