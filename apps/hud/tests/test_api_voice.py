import shutil
from fastapi.testclient import TestClient
from app.main import app, web_dir
from app.voice.transcriber import AudioError, Transcriber


def test_health(monkeypatch):
    with TestClient(app) as client:
        response=client.get('/api/health'); assert response.status_code==200 and response.json()['status']=='online'


def test_audio_upload_validation():
    with TestClient(app) as client:
        response=client.post('/api/transcribe',files={'audio':('x.txt',b'hello','text/plain')}); assert response.status_code==400


def test_static_assets_do_not_depend_on_cwd(monkeypatch, tmp_path):
    monkeypatch.chdir(tmp_path)
    assert web_dir.is_absolute()
    with TestClient(app) as client:
        assert client.get('/').status_code == 200
        assert client.get('/static/app.js').status_code == 200


async def test_audio_temp_cleanup(config,monkeypatch):
    config.whisper_model_path.write_bytes(b'x'); t=Transcriber(config)
    monkeypatch.setattr(shutil,'which',lambda x:f'/usr/bin/{x}')
    async def fail(*a,**k): raise AudioError('failed')
    monkeypatch.setattr(t,'_run',fail)
    try: await t.transcribe(b'abc','audio/webm')
    except AudioError: pass
    assert list((config.runtime/'tmp').iterdir())==[]
