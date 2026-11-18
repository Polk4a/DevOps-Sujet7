"""Application témoin du Sujet 7 : une petite API web dont seule l'image compte.

Elle ne fait volontairement presque rien : ce qui est démontré, c'est le chemin de l'image
(build, push, plus tard SBOM, scan, signature) et son admission sur le cluster.
"""

import os
import platform

from fastapi import FastAPI

GIT_SHA = os.environ.get("GIT_SHA", "inconnu")

app = FastAPI(title="s7-demo-app", version=GIT_SHA[:12])


@app.get("/")
def accueil() -> dict:
    return {"application": "s7-demo-app", "message": "Sujet 7 : application témoin", "git_sha": GIT_SHA}


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}


@app.get("/version")
def version() -> dict:
    return {"git_sha": GIT_SHA, "python": platform.python_version()}
