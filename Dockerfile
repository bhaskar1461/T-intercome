FROM python:3.11-alpine

# Set working directory
WORKDIR /app

# OCI annotations and Docker labels according to GitHub Container Registry guidelines
LABEL org.opencontainers.image.source="https://github.com/bhaskar1461/T-intercome"
LABEL org.opencontainers.image.description="SplitBuds PTT — Nothing OS Split-Channel Walkie-Talkie Web Companion & Sideload Server"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.title="SplitBuds PTT"
LABEL org.opencontainers.image.vendor="bhaskar1461"

# Copy web companion assets and IPA file
COPY web /app/web
COPY SplitBudsPTT.ipa* /app/

# Expose default HTTP port
EXPOSE 8080

ENV PORT=8080
ENV PYTHONUNBUFFERED=1

# Healthcheck probe
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD wget -qO- http://localhost:8080/ || exit 1

# Start web companion & artifact distribution server
CMD ["python", "/app/web/server.py"]
