FROM python:3.12.11-slim-bookworm@sha256:519591d6871b7bc437060736b9f7456b8731f1499a57e22e6c285135ae657bf7

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

RUN groupadd --system --gid 10001 photo-ai \
    && useradd --system --uid 10001 --gid photo-ai --home-dir /app photo-ai
WORKDIR /app
COPY api/requirements.txt ./requirements.txt
RUN pip install -r requirements.txt
COPY api/app.py ./app.py
COPY schema.sql ./schema.sql
USER 10001:10001
EXPOSE 8000
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers"]
