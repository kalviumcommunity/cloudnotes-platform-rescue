"""Local task checks. Run from repository root: python3 scripts/check.py 1..5."""
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
NS = os.environ.get('NAMESPACE', 'cloudnotes-platform')


def run(*args, capture=False, check=True):
    result = subprocess.run(args, cwd=ROOT, text=True, stdout=subprocess.PIPE if capture else None,
                            stderr=subprocess.STDOUT if capture else None)
    if capture:
        print(result.stdout, end='')
    if check and result.returncode:
        raise RuntimeError(f'Command failed: {args}')
    return result


def docker(*args, **kw):
    return run('docker', *args, **kw)


def request(host, port=8080):
    return f'import urllib.request; r=urllib.request.urlopen("http://{host}:{port}/health", timeout=4); print("HTTP",r.status); print(r.read().decode())'


def task1():
    name = 'platform-local-check'
    docker('rm', '-f', name, check=False, capture=True)
    try:
        docker('run', '-d', '--name', name, '--network', 'platform-rescue-net', '--env-file', 'local/start.env',
               '-v', f'{ROOT / "app"}:/app:ro', '-w', '/app', 'python:3.12-slim-bookworm', 'python', 'server.py')
        import time
        time.sleep(2)
        output = docker('run', '--rm', '--network', 'platform-rescue-net', 'python:3.12-slim-bookworm',
                        'python', '-c', request(name), capture=True).stdout
        assert json.loads(output.splitlines()[-1]) == {'status': 'ok', 'mode': 'production'}
        print('PASS task 1: remote-container HTTP 200, production mode')
    finally:
        docker('rm', '-f', name, capture=True, check=False)


def task2():
    name = 'platform-gateway'
    docker('rm', '-f', name, capture=True, check=False)
    try:
        docker('run', '-d', '--name', name, '--network', 'platform-rescue-net',
               '-v', f'{ROOT / "network/nginx.conf"}:/etc/nginx/nginx.conf:ro', 'nginx:alpine')
        import time
        time.sleep(2)
        for ip, expected in [('10.231.240.20', 200), ('10.231.240.30', 403), ('10.231.240.40', 403)]:
            code = ('import urllib.request, urllib.error; '
                    f'url="http://{name}:8080/health"\n'
                    'try:\n r=urllib.request.urlopen(url,timeout=4); print(r.status)\n'
                    'except urllib.error.HTTPError as e: print(e.code)\n')
            out = docker('run', '--rm', '--network', 'platform-rescue-net', '--ip', ip,
                         'python:3.12-slim-bookworm', 'python', '-c', code, capture=True).stdout
            assert out.strip() == str(expected), f'{ip}: expected {expected}, got {out}'
            print(f'{ip} expected={expected}: PASS')
        print('PASS task 2: permitted client succeeds; both other clients blocked')
    finally:
        docker('rm', '-f', name, capture=True, check=False)


def task3():
    name = 'platform-image-check'
    docker('build', '-t', 'cloudnotes-platform:1.0.0', '.')
    user = docker('image', 'inspect', 'cloudnotes-platform:1.0.0', '--format', '{{.Config.User}}', capture=True).stdout.strip()
    assert user == '10001:10001', 'Runtime must use documented unprivileged UID:GID'
    docker('rm', '-f', name, capture=True, check=False)
    try:
        docker('run', '-d', '--name', name, '--network', 'platform-rescue-net', '-e', 'APP_MODE=production', 'cloudnotes-platform:1.0.0')
        import time
        time.sleep(2)
        docker('run', '--rm', '--network', 'platform-rescue-net', 'python:3.12-slim-bookworm', 'python', '-c', request(name))
        print('PASS task 3: versioned build, UID:GID 10001:10001, runtime HTTP 200')
    finally:
        docker('rm', '-f', name, capture=True, check=False)


def task4():
    run('kubectl', '-n', NS, 'apply', '-f', 'k8s/')
    run('kubectl', '-n', NS, 'rollout', 'status', 'deployment/cloudnotes-platform', '--timeout=45s')
    run('kubectl', '-n', NS, 'get', 'pods', '-l', 'app=cloudnotes-platform')
    run('kubectl', '-n', NS, 'get', 'endpointslices', '-l', 'kubernetes.io/service-name=cloudnotes-platform')
    output = run('kubectl', '-n', NS, 'exec', 'client', '--', 'python', '-c', request('cloudnotes-platform', 80), capture=True).stdout
    assert json.loads(output.splitlines()[-1])['mode'] == 'production'
    print('PASS task 4: Ready rollout and Service-DNS HTTP 200, production mode')


def task5():
    docker('run', '--rm', '--entrypoint', '/bin/promtool', '-v', f'{ROOT / "monitoring"}:/work:ro',
           '-w', '/work', 'prom/prometheus:v3.5.0', 'check', 'rules', 'alerts.yaml')
    docker('run', '--rm', '--entrypoint', '/bin/promtool', '-v', f'{ROOT / "monitoring"}:/work:ro',
           '-w', '/work', 'prom/prometheus:v3.5.0', 'test', 'rules', 'tests.yaml')
    print('PASS task 5: normal traffic, brief spike, and sustained-error tests')


if __name__ == '__main__':
    try:
        {'1': task1, '2': task2, '3': task3, '4': task4, '5': task5}[sys.argv[1]]()
    except (RuntimeError, AssertionError, KeyError, IndexError) as exc:
        print(f'FAIL: {exc}', file=sys.stderr)
        sys.exit(1)
