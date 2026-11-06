FROM pytorch/pytorch:2.8.0-cuda12.8-cudnn9-runtime@sha256:417bd75df6365104c283ea4c1651fb3530d9eb5a4c2fafa51943cff2a94e6385

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    HF_HOME=/models/huggingface

WORKDIR /worker
COPY worker/requirements.txt ./requirements.txt
RUN pip install -r requirements.txt
COPY worker/worker.py ./worker.py
RUN useradd --system --uid 10001 --create-home --home-dir /worker photo-ai \
    && chown -R 10001:10001 /worker
USER 10001:10001
CMD ["python", "worker.py"]
