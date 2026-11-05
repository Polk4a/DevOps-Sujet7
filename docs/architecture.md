# Architecture de la chaîne CI/CD sécurisée (Sujet 7)

Version : v0.2 du 2026-11-05. Sections 3 (lignes cluster), 4, 5 (étapes 8 à 12) et 9 (hypothèses cluster) :
étudiant A. Sections 2, 3 (lignes CI), 5 (étapes 1 à 7) : étudiant B.

## 1. Objectifs et périmètre

Une image déployée doit pouvoir justifier d'où elle vient, de quoi elle est faite et qui l'a construite.
La CI ne signe que ce qui a passé le scan ; le cluster refuse tout ce qui n'est pas signé par notre clé.
Les deux contrôles sont indépendants : la compromission de l'un ne suffit pas à faire exécuter une image non vérifiée.

Hors périmètre : la détection en cours d'exécution (une CVE publiée après le déploiement n'est pas détectée), la haute
disponibilité du plan de contrôle, la gestion de plusieurs clusters.

## 2. Vue d'ensemble

```mermaid
flowchart LR
  subgraph POSTE["Poste développeur"]
    DEV["commit, pull request"]
  end
  subgraph GH["GitHub (hors labo)"]
    REPO["Dépôt, tags de jalon, secrets CI"]
  end
  OP["Opérateur ou attaquant"]
  subgraph LABO["Labo : réseau s7-net, CA privée"]
    subgraph FORGE["VM s7-forge"]
      RUN["Runner CI éphémère"]
      REG[("Registre registry.s7.internal")]
    end
    subgraph K8S["Cluster k3s"]
      API["API server"]
      KYV["Kyverno : webhook d'admission"]
      POD["Pod, namespace demo"]
    end
  end
  DEV -->|"git push"| REPO
  REPO -->|"déclenche le job"| RUN
  RUN -->|"1 build, 2 SBOM, 3 scan Trivy bloquant"| RUN
  RUN -->|"4 push par digest, 5 signature et attestations"| REG
  OP -->|"kubectl apply"| API
  API --> KYV
  KYV -->|"vérifie origine, signature, attestations avec cosign.pub"| REG
  KYV -->|"admis"| POD
  KYV -.->|"refusé"| API
```

## 3. Composants et choix

| Composant | Rôle | Où | Choix | ADR |
| --- | --- | --- | --- | --- |
| Dépôt Git | source de vérité, tags de jalon | GitHub | existant | ADR-002 |
| Runner CI | build, SBOM, scan, signature, attestation | VM `s7-forge` | [A COMPLETER : étudiant B] | ADR-002 |
| Registre | images, signatures, attestations | VM `s7-forge` | [A COMPLETER : étudiant B] | ADR-002 |
| Outils supply chain | Syft, Trivy, Cosign | runner | versions dans `versions.yaml` | ADR-003 |
| Virtualisation | VM du socle | hôte du labo | KVM/libvirt, image cloud Ubuntu 24.04, cloud-init | ADR-001 |
| Cluster | exécution de l'application | `s7-cp` + `s7-w1` (+ `s7-w2`) | k3s `v1.35.9+k3s1`, Traefik et ServiceLB désactivés | ADR-001 |
| Admission | vérifie origine, signature, puis attestations | namespace `kyverno` | Kyverno v1.19.2 (chart 3.9.2), `ImageValidatingPolicy` | ADR-004 |
| CA privée | certificat du registre | générée par B | approuvée par le runner, containerd sur chaque nœud et Kyverno | ADR-002 |
| Application témoin | API web + Dockerfile (saine et vulnérable) | namespace `demo` | [A COMPLETER : étudiant B] | |

## 4. Infrastructure

### 4.1 Machines physiques

Relevé complet dans [docs/inventaire.md](inventaire.md).

| Machine | CPU | RAM | Disque | KVM |
| --- | --- | --- | --- | --- |
| [A COMPLETER : reporter la ligne produite par infra/inventaire.sh] | | | | |

### 4.2 Machines virtuelles

| VM | Rôle | vCPU | RAM | Disque | IP |
| --- | --- | --- | --- | --- | --- |
| `s7-forge` | runner CI + registre | 2 | 4 Go | 60 Go | 192.168.100.10 |
| `s7-cp` | serveur k3s (plan de contrôle, SQLite intégré) | 2 | 4 Go | 30 Go | 192.168.100.20 |
| `s7-w1` | agent k3s (charge applicative) | 2 | 4 Go | 30 Go | 192.168.100.21 |
| `s7-w2` (si la RAM le permet) | agent k3s | 2 | 4 Go | 30 Go | 192.168.100.22 |

Total : 6 vCPU, 12 Go de RAM et 120 Go de disque pour 3 VM ; 8 vCPU, 16 Go et 150 Go avec `s7-w2`. Il faut garder
au moins 2 Go pour l'hôte. Si la machine a moins de 16 Go, on passe à 3 Go par VM sur `s7-cp` et `s7-w1` et on
renonce à `s7-w2` ; `s7-forge` garde 4 Go, car le build et le scan d'une image Python le demandent.

Toutes les VM sont créées depuis la même image cloud Ubuntu 24.04 (répertoire daté, contrôlée par `SHA256SUMS`),
en disques qcow2 adossés à cette image. Cloud-init fixe le nom d'hôte, l'IP statique, l'utilisateur `s7` (clé SSH
seulement, pas de mot de passe), les entrées DNS du projet, chrony et le certificat de la CA privée.

### 4.3 Réseau et adressage

| Plage | Usage | Remarque |
| --- | --- | --- |
| 192.168.100.0/24 | réseau libvirt `s7-net` (NAT), passerelle .1 | à changer s'il chevauche le réseau du labo |
| 10.42.0.0/16 | pods (flannel VXLAN, valeur par défaut de k3s) | MTU des pods = MTU de l'interface − 50 |
| 10.43.0.0/16 | services Kubernetes (valeur par défaut de k3s) | CoreDNS en 10.43.0.10 |

| Nom | IP | Port(s) exposé(s) |
| --- | --- | --- |
| `registry.s7.internal` | 192.168.100.10 | 443 (registre en TLS) |
| `k3s-cp.s7.internal` | 192.168.100.20 | 6443 (API Kubernetes), 10250 (kubelet) |
| `k3s-w1.s7.internal` | 192.168.100.21 | 10250 (kubelet), NodePort 30000-32767 |

Les noms sont déclarés dans le DNS du réseau libvirt (élément `<dns><host>`) et, en secours, dans `/etc/hosts` par
cloud-init. Le suffixe `.internal` évite `.local`, réservé à mDNS.

### 4.4 Confiance TLS envers le registre

Le registre présente un certificat émis par la CA privée du projet (SAN `registry.s7.internal`). Seul le certificat
public de la CA (`security/ca/ca.crt`) est versionné. Il doit être approuvé à trois endroits côté cluster, sinon on
obtient `x509: certificate signed by unknown authority` :

1. **containerd sur chaque nœud**, pour tirer les images, par `/etc/rancher/k3s/registries.yaml` :

   ```yaml
   mirrors:
     registry.s7.internal:
       endpoint:
         - "https://registry.s7.internal"
   configs:
     "registry.s7.internal":
       tls:
         ca_file: /etc/rancher/k3s/ca-s7.crt
   ```

2. **le magasin de certificats du système** des nœuds (`/usr/local/share/ca-certificates/` puis
   `update-ca-certificates`), pour les outils lancés sur les nœuds ;
3. **le contrôleur d'admission Kyverno**, qui interroge le registre pour lire signatures et attestations, par la
   valeur Helm `admissionController.caCertificates.data`.

### 4.5 Durcissement du cluster (prévu en J2)

- Binaire k3s et script d'installation vérifiés par SHA-256, version figée (ADR-001).
- Traefik et ServiceLB désactivés ; aucun service exposé hors NodePort de l'application témoin.
- Secrets chiffrés au repos (`--secrets-encryption`) ; kubeconfig en `0600`, jamais versionné.
- Pod Security Admission sur `demo` : `enforce=baseline`, `warn=restricted`, puis `enforce=restricted` si
  l'application témoin tourne sans root.
- Kyverno en échec fermé sur `demo` (ADR-004) ; `kube-system` et `kyverno` exclus.
- Chrony sur toutes les VM ; accès SSH par clé uniquement.

## 5. Flux détaillé

Étapes 1 à 7 (CI) : [A COMPLETER : étudiant B, du `git push` à la signature et aux attestations dans le registre]

8. **Demande de déploiement.** Un opérateur (ou un attaquant disposant d'un accès à l'API) envoie un manifeste
   (`kubectl apply`) créant un pod dans `demo`. L'API server authentifie, autorise (RBAC) puis appelle les webhooks
   d'admission.
9. **Vérification de l'origine.** Kyverno refuse toute image qui ne vient pas de `registry.s7.internal/s7/`.
   *Preuve* : message de refus de la politique.
10. **Vérification de la signature.** Kyverno résout le tag en digest, lit la signature dans le registre (TLS avec la
    CA privée) et la vérifie avec `cosign.pub`. En J4, il vérifie aussi l'attestation SLSA. *Échec* : pod refusé avec
    le message de la politique ; *registre ou Kyverno injoignable* : refus (échec fermé).
11. **Réécriture par digest.** Le pod admis référence l'image par son digest vérifié (`mutateDigest`) : le tag ne peut
    plus être remplacé entre la vérification et l'exécution.
12. **Exécution.** Le kubelet du nœud demande l'image à containerd, qui la tire du registre en TLS (via
    `registries.yaml`) ; le pod démarre sous les restrictions de Pod Security Admission. *Preuve* :
    `kubectl get pod -n demo -o jsonpath='{.spec.containers[*].image}'` montre une référence `@sha256:`.

## 6. Modèle de menace

| Menace | Contrôle | Démo (J3-J4) |
| --- | --- | --- |
| Image poussée directement dans le registre, sans passer par la CI | signature exigée par l'admission | Attaque 1 |
| Image tirée d'un autre registre | règle d'origine de la politique d'admission | Attaque 1 (variante) |
| Image signée avec la clé de l'attaquant | vérification contre `cosign.pub` | Attaque 2 |
| Tag écrasé ou image modifiée après signature | signature et résolution par digest | Attaque 3 |
| Dépendance vulnérable introduite par une PR | Trivy bloquant avant signature | Attaque 4 |
| Image construite hors CI, provenance falsifiée | attestation SLSA exigée | Attaque 5 |
| Fuite de la clé privée de signature | non couvert : secrets CI, rotation | limite |
| Runner ou outil de CI compromis | non couvert : runner éphémère, versions épinglées | limite |
| Administrateur du cluster qui supprime le webhook | non couvert : RBAC, journal d'audit | limite |
| CVE publiée après le déploiement | non couvert : le scan a lieu au build | limite |

## 7. Garanties et limites

| Mécanisme | Garantit | Ne garantit pas |
| --- | --- | --- |
| SBOM | l'inventaire des composants au moment du build | qu'il soit complet, ni authentique s'il n'est pas signé |
| Scan Trivy | l'absence de CVE connues de la base à l'instant du scan | les failles inconnues, le code malveillant, les CVE de demain |
| Signature Cosign | qu'un détenteur de la clé a signé ce digest | que l'image soit saine ; clé ou CI compromise = signature de l'attaquant |
| Provenance SLSA | une déclaration sur dépôt, commit et builder | plus que ce que vaut l'isolation du builder |
| Admission Kyverno | le refus à la création des pods non conformes dans `demo` | les pods déjà admis, les namespaces exclus, un administrateur qui supprime le webhook |
| Réécriture par digest | que le pod exécute exactement l'image vérifiée | que cette image soit sans faille |
| TLS du registre | intégrité et identité du transport | le contenu des images |

## 8. Contrats d'interface entre A et B

| Point | Valeur |
| --- | --- |
| Nom du registre | `registry.s7.internal` (192.168.100.10, port 443) |
| Référence d'image | `registry.s7.internal/s7/demo-app@sha256:<digest>` (toujours par digest) |
| Clé publique de signature | `security/cosign/cosign.pub` |
| Certificat de la CA privée | `security/ca/ca.crt` (certificat public uniquement) |
| Namespace cible | `demo` |

## 9. Hypothèses et contraintes

- La machine du labo dispose de la virtualisation matérielle et d'au moins 16 Go de RAM : [A COMPLETER : confirmé ou non par l'inventaire]. Sinon, Plan B de l'ADR-001.
- Kyverno 1.19 prend en charge Kubernetes 1.33 à 1.35 : k3s reste en 1.35 pendant tout le projet.
- Les signatures produites par Cosign 3 sont vérifiables par Kyverno 1.19 : à confirmer par les spikes S3 et S4.
- Le réseau du labo laisse passer GitHub (binaire k3s, chart Kyverno via `kyverno.github.io`) : à confirmer par
  l'inventaire ; sinon, les artefacts sont copiés et vérifiés depuis un poste qui y a accès.
- [A COMPLETER : hypothèses CI et registre, étudiant B]
