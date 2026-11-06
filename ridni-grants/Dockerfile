FROM python:3.13-alpine@sha256:79e7a9b9ff1cbceff819f856fb374477792a5967759d94df266de7b7b4120e6f
WORKDIR /app
COPY app.py ./
COPY public ./public
COPY scripts ./scripts
RUN mkdir -p /app/data
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PORT=8088 GRANTS_DB=/app/data/grants.sqlite
EXPOSE 8088
CMD ["python3", "app.py"]
