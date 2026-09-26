FROM python:3.13-alpine
WORKDIR /app
COPY app.py ./
COPY public ./public
COPY scripts ./scripts
RUN mkdir -p /app/data
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PORT=8088 GRANTS_DB=/app/data/grants.sqlite
EXPOSE 8088
CMD ["python3", "app.py"]
