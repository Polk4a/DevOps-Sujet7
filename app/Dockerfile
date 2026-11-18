# Application témoin du Sujet 7 (J2). Trois étapes :
#   deps    : environnement virtuel, dépendances installées par hash (--require-hashes)
#   test    : tests unitaires, exécutés par la CI avant toute image (cible --opt target=test)
#   runtime : image finale, sans outils de test, utilisateur non-root 10001
# L'image de base est épinglée par digest (make pins). Ne jamais revenir à un tag seul.
ARG PYTHON_IMAGE=docker.io/library/python:3.13-slim@sha256:e48f59cdba69a3cbd9ed2cf0f348d90d45a8d350d98134cf1070bc106ee9ed90

FROM ${PYTHON_IMAGE} AS deps
ENV PIP_NO_CACHE_DIR=1 PIP_DISABLE_PIP_VERSION_CHECK=1 PYTHONDONTWRITEBYTECODE=1
RUN python -m venv /opt/venv
COPY requirements.txt /tmp/requirements.txt
RUN /opt/venv/bin/pip install --require-hashes --no-deps -r /tmp/requirements.txt

FROM deps AS test
COPY requirements-dev.txt /tmp/requirements-dev.txt
RUN /opt/venv/bin/pip install --require-hashes --no-deps -r /tmp/requirements-dev.txt
WORKDIR /src
COPY main.py pytest.ini ./
COPY tests ./tests
RUN /opt/venv/bin/python -m pytest -q -p no:cacheprovider

FROM ${PYTHON_IMAGE} AS runtime
ARG GIT_SHA=inconnu
ENV PATH=/opt/venv/bin:$PATH \
    GIT_SHA=${GIT_SHA} \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1
RUN groupadd --gid 10001 app && useradd --uid 10001 --gid 10001 --no-create-home --shell /usr/sbin/nologin app
COPY --from=deps /opt/venv /opt/venv
COPY main.py /app/main.py
WORKDIR /app
USER 10001:10001
EXPOSE 8080
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080", "--no-server-header"]
