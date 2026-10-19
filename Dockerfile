FROM python:3.12-slim-bookworm AS build
WORKDIR /build
COPY app/server.py .
RUN python -m py_compile server.py && mkdir /dist && cp server.py /dist/server.py

FROM python:3.12-slim-bookworm AS runtime
WORKDIR /app
# Runtime needs only the packaged server, not build files.
COPY --from=build /missing/server.py /app/server.py
USER root
EXPOSE 8080
CMD ["python", "/app/missing.py"]
