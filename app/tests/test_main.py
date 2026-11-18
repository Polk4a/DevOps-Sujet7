from fastapi.testclient import TestClient

from main import app

client = TestClient(app)


def test_health():
    reponse = client.get("/health")
    assert reponse.status_code == 200
    assert reponse.json() == {"status": "ok"}


def test_version_expose_le_commit():
    reponse = client.get("/version")
    assert reponse.status_code == 200
    assert "git_sha" in reponse.json()


def test_accueil():
    assert client.get("/").json()["application"] == "s7-demo-app"
