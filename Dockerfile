FROM python:3.12-slim-bookworm AS build
WORKDIR /build
COPY app/server.py .
RUN python -m py_compile server.py && mkdir /dist && cp server.py /dist/server.py


UID:GID - `10001:10001`



