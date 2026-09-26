from __future__ import annotations

import io
import json
import logging
import os
import socket
import threading
import time
from typing import Any

import httpx
from PIL import Image
import torch
from transformers import AutoModel, AutoModelForCausalLM, AutoProcessor, Qwen3VLForConditionalGeneration


API_URL = os.environ["PHOTO_AI_API_URL"].rstrip("/")
API_TOKEN = os.environ["PHOTO_AI_API_TOKEN"]
WORKER_ID = os.getenv("PHOTO_AI_WORKER_ID", f"{socket.gethostname()}-gpu0")
POLL_SECONDS = int(os.getenv("PHOTO_AI_POLL_SECONDS", "30"))
MAX_EDGE = int(os.getenv("PHOTO_AI_MAX_EDGE", "1280"))
VISION_FALLBACK_MODEL = os.getenv("PHOTO_AI_VISION_FALLBACK_MODEL", "microsoft/Florence-2-large")
logger = logging.getLogger("photo-ai-worker")
logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"), format="%(asctime)sZ %(levelname)s %(message)s")


class Api:
    def __init__(self) -> None:
        self.client = httpx.Client(
            base_url=API_URL,
            headers={"Authorization": f"Bearer {API_TOKEN}"},
            timeout=httpx.Timeout(180, connect=30),
        )

    def lease(self) -> list[dict[str, Any]]:
        response = self.client.post("/v1/jobs/lease", json={"worker_id": WORKER_ID, "batch_size": 1})
        response.raise_for_status()
        return response.json()["jobs"]

    def image(self, asset_id: str) -> bytes:
        response = self.client.get(f"/v1/assets/{asset_id}/inference-image")
        response.raise_for_status()
        return response.content

    def heartbeat(self, job: dict[str, Any]) -> None:
        response = self.client.post(
            f"/v1/jobs/{job['id']}/heartbeat", json={"lease_token": job["lease_token"]}
        )
        response.raise_for_status()

    def complete(self, job: dict[str, Any], result: dict[str, Any]) -> None:
        response = self.client.post(
            f"/v1/jobs/{job['id']}/complete",
            json={"lease_token": job["lease_token"], "result": result},
        )
        response.raise_for_status()

    def fail(self, job: dict[str, Any], error: str, retryable: bool = True, fallback: str | None = None) -> None:
        response = self.client.post(
            f"/v1/jobs/{job['id']}/fail",
            json={"lease_token": job["lease_token"], "error": error[:4000], "retryable": retryable,
                  "fallback_model_name": fallback},
        )
        response.raise_for_status()


class Heartbeat:
    def __init__(self, api: Api, job: dict[str, Any]) -> None:
        self.api, self.job = api, job
        self.stop = threading.Event()
        self.thread = threading.Thread(target=self._run, daemon=True)

    def __enter__(self):
        self.thread.start()
        return self

    def __exit__(self, *_: object) -> None:
        self.stop.set()
        self.thread.join(timeout=5)

    def _run(self) -> None:
        while not self.stop.wait(120):
            try:
                self.api.heartbeat(self.job)
            except Exception:
                logger.exception("heartbeat_failed job_id=%s", self.job["id"])


def inference_image(data: bytes) -> Image.Image:
    image = Image.open(io.BytesIO(data)).convert("RGB")
    image.thumbnail((MAX_EDGE, MAX_EDGE), Image.Resampling.LANCZOS)
    return image


class ModelRunner:
    """Loads one model at a time so an 8 GB GPU is never occupied by both stages."""

    def __init__(self) -> None:
        self.key: tuple[str, str] | None = None
        self.model: Any = None
        self.processor: Any = None

    def unload(self) -> None:
        self.model = self.processor = None
        self.key = None
        if torch.cuda.is_available():
            torch.cuda.empty_cache()

    def load(self, job: dict[str, Any]) -> None:
        key = (job["stage"], job["model_name"])
        if key == self.key:
            return
        self.unload()
        revision = job["model_revision"]
        name = job["model_name"]
        self.processor = AutoProcessor.from_pretrained(name, revision=revision, trust_remote_code=True)
        if job["stage"] == "embedding":
            self.model = AutoModel.from_pretrained(
                name, revision=revision, torch_dtype=torch.float16, device_map="cuda"
            )
        else:
            if name.startswith("Qwen/"):
                self.model = Qwen3VLForConditionalGeneration.from_pretrained(
                    name, revision=revision, torch_dtype="auto", device_map="cuda", trust_remote_code=True
                )
            else:
                self.model = AutoModelForCausalLM.from_pretrained(
                    name, revision=revision, torch_dtype=torch.float16, device_map="cuda", trust_remote_code=True
                )
        self.model.eval()
        self.key = key

    @torch.inference_mode()
    def run(self, job: dict[str, Any], image: Image.Image) -> dict[str, Any]:
        self.load(job)
        if job["stage"] == "embedding":
            inputs = self.processor(images=image, return_tensors="pt").to("cuda")
            if hasattr(self.model, "get_image_features"):
                features = self.model.get_image_features(**inputs)
            else:
                features = self.model(**inputs).pooler_output
            features = torch.nn.functional.normalize(features.float(), dim=-1)[0].cpu().tolist()
            return {"embedding": features}

        if job["model_name"] == "microsoft/Florence-2-large":
            result: dict[str, Any] = {"objects": [], "scene": [], "activities": [], "people": []}
            for task, key in (("<MORE_DETAILED_CAPTION>", "caption"), ("<OCR>", "ocr_text")):
                inputs = self.processor(text=task, images=image, return_tensors="pt").to("cuda")
                generated = self.model.generate(**inputs, max_new_tokens=512, do_sample=False, num_beams=3)
                decoded = self.processor.batch_decode(generated, skip_special_tokens=False)[0]
                parsed = self.processor.post_process_generation(decoded, task=task, image_size=image.size)
                value = parsed.get(task, parsed) if isinstance(parsed, dict) else parsed
                result[key] = value if isinstance(value, str) else json.dumps(value, ensure_ascii=False)
            result.update({"location_guess": None, "event_guess": None, "quality_score": None})
            return result

        prompt = (
            "Return only strict JSON with keys caption, objects, scene, activities, people, "
            "location_guess, event_guess, ocr_text, quality_score. Use short English taxonomy values; "
            "use null when uncertain. Never identify a person by name."
        )
        if hasattr(self.processor, "apply_chat_template"):
            messages = [{"role": "user", "content": [{"type": "image", "image": image}, {"type": "text", "text": prompt}]}]
            text = self.processor.apply_chat_template(messages, tokenize=False, add_generation_prompt=True)
            inputs = self.processor(text=[text], images=[image], return_tensors="pt").to("cuda")
        else:
            inputs = self.processor(text=prompt, images=image, return_tensors="pt").to("cuda")
        generated = self.model.generate(**inputs, max_new_tokens=512, do_sample=False)
        input_length = inputs.get("input_ids").shape[-1] if inputs.get("input_ids") is not None else 0
        decoded = self.processor.batch_decode(generated[:, input_length:], skip_special_tokens=True)[0].strip()
        start, end = decoded.find("{"), decoded.rfind("}")
        if start < 0 or end <= start:
            raise ValueError("model did not return a JSON object")
        result = json.loads(decoded[start : end + 1])
        if not isinstance(result, dict):
            raise ValueError("model JSON root is not an object")
        return result


def main() -> None:
    if not torch.cuda.is_available():
        raise SystemExit("CUDA is required; refusing CPU inference")
    api, runner = Api(), ModelRunner()
    logger.info("worker_started id=%s gpu=%s", WORKER_ID, torch.cuda.get_device_name(0))
    while True:
        try:
            jobs = api.lease()
        except Exception:
            logger.exception("lease_failed")
            time.sleep(POLL_SECONDS)
            continue
        if not jobs:
            time.sleep(POLL_SECONDS)
            continue
        job = jobs[0]
        try:
            with Heartbeat(api, job):
                result = runner.run(job, inference_image(api.image(job["asset_id"])))
                api.complete(job, result)
            logger.info("job_completed id=%s asset=%s stage=%s", job["id"], job["asset_id"], job["stage"])
        except Exception as exc:
            logger.exception("job_failed id=%s", job["id"])
            try:
                oom = isinstance(exc, torch.cuda.OutOfMemoryError) or "out of memory" in str(exc).casefold()
                fallback = VISION_FALLBACK_MODEL if oom and job["stage"] == "vision" and job["model_name"] != VISION_FALLBACK_MODEL else None
                api.fail(job, f"{type(exc).__name__}: {exc}", retryable=not oom, fallback=fallback)
            except Exception:
                logger.exception("failure_report_failed id=%s", job["id"])
            runner.unload()


if __name__ == "__main__":
    main()
