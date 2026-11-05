# ADR-004 : Moteur de politiques d'admission

- **Date** : 2026-11-05
- **Statut** : proposée <!-- passer à « validée » après relecture et approbation de la PR par l'étudiant B -->
- **Auteur** : Étudiant A — **Relecteur** : Étudiant B
- **Spikes liés** : [S4](../spikes/S4.md) (comparaison des deux API Kyverno) ; dépend de S3 (signature Cosign 3, étudiant B)

## Contexte

La CI signe les images qui passent le scan (ADR-003). Le cluster doit vérifier lui-même cette preuve et **refuser à
l'admission** tout pod dont l'image n'est pas signée par la clé du projet : c'est le second niveau de la défense en
profondeur. En J4, il devra aussi exiger une attestation de provenance SLSA.

Faits établis au 05/11/2026 :

- Kyverno 1.19 (août 2026) déprécie `ClusterPolicy` et `Policy` au profit des politiques CEL ; la 1.19 est la dernière
  version qui les prend complètement en charge, et leur retrait est annoncé pour la 1.20
  ([annonce de la 1.19](https://kyverno.io/blog/2026/08/20/announcing-kyverno-release-1.19)). Dans les CRD de la
  v1.19.2, `kyverno.io/v1 ClusterPolicy` est marquée `deprecated` avec un avertissement à chaque `kubectl apply`.
- Dans la même version, l'API `ImageValidatingPolicy` est servie en `policies.kyverno.io/v1`. Son schéma (vérifié
  dans le CRD de la v1.19.2) prévoit un attesteur Cosign à clé publique (`attestors[].cosign.key.data`), la
  désactivation du journal de transparence (`ctlog.insecureIgnoreTlog`), les attestations in-toto et OCI 1.1
  (`attestations[].intoto`, `attestations[].referrer`) et `validationConfigurations` (`mutateDigest`,
  `verifyDigest`, `required`) ([documentation](https://main.kyverno.io/docs/policy-types/image-validating-policy/)).
- Dernière version au 05/11/2026 : **Kyverno v1.19.2**, chart Helm **3.9.2** (21/10/2026). Kyverno 1.19 prend en
  charge Kubernetes 1.33 à 1.35, et seule la dernière version mineure reçoit les correctifs communautaires
  ([endoflife.date](https://endoflife.date/kyverno)).

Faits mesurés : [A COMPLETER : résultat du spike S4 (pods admis et refusés, messages de refus obtenus avec chaque API, avertissement de dépréciation capturé)]

## Critères

| Critère | Poids (1 à 3) | Pourquoi |
| --- | --- | --- |
| Vérification de signature Cosign par clé publique et d'attestations | 3 | cœur de J3 et J4 |
| Pérennité de l'API pendant et après le projet | 2 | rapport et soutenance en février 2027 |
| Règles générales (origine des images, root, `latest`) dans le même outil | 2 | une politique d'origine est indispensable (voir Décision) |
| Documentation et exemples | 2 | peu de créneaux, pas d'enseignant en salle |
| Ressources consommées | 1 | une seule machine ; mesure M3 |

## Options considérées

### Option 1 : Kyverno 1.19, API `ImageValidatingPolicy` (CEL)

- Avantages : API actuelle et seule pérenne ; vérification Cosign par clé, attestations in-toto et OCI 1.1, réécriture
  par digest ; le même moteur porte d'autres règles (`ValidatingPolicy`).
- Limites : API récente, moins d'exemples ; expressions CEL à apprendre ; prise en charge par la CLI `kyverno test`
  non confirmée par la documentation.

### Option 2 : Kyverno 1.19, API `ClusterPolicy` + `verifyImages`

- Avantages : la plus documentée et la plus présente dans les tutoriels ; option `cosignOCI11` pour les signatures
  stockées en OCI 1.1 ; vérification des bundles Sigstore depuis Kyverno 1.13.
- Limites : dépréciée en 1.19, retrait annoncé en 1.20 ; le rapport final (février 2027) décrirait une API retirée.

### Option 3 : Sigstore policy-controller

- Avantages : conçu par le projet Sigstore pour vérifier les signatures et attestations Cosign.
- Limites : ne fait que de la vérification d'images ; les règles générales demanderaient un second outil.

### Option 4 : OPA Gatekeeper + Ratify

- Avantages : écosystème CNCF mature ; Ratify vérifie signatures et artefacts liés.
- Limites : deux composants à installer et à faire cohabiter ; langage Rego ; plus de RAM.

### Option 5 : ValidatingAdmissionPolicy (natif Kubernetes)

- Avantages : rien à installer, CEL natif.
- Limites : une politique native ne peut pas interroger un registre, donc elle ne peut pas vérifier une signature ;
  insuffisante seule.

## Comparaison

| Critère (poids) | Opt. 1 : IVPOL | Opt. 2 : ClusterPolicy | Opt. 3 : policy-controller | Opt. 4 : Gatekeeper + Ratify | Opt. 5 : VAP native |
| --- | --- | --- | --- | --- | --- |
| Signature + attestations (3) | ++ | ++ | ++ | + | −− impossible |
| Pérennité (2) | ++ | −− retrait annoncé | + | + | ++ |
| Règles générales (2) | ++ | ++ | −− | + | ++ |
| Documentation (2) | + | ++ | + | + | + |
| Ressources (1) | + | + | ++ | − | ++ |

## Décision

Nous retenons l'**option 1 : Kyverno v1.19.2 (chart 3.9.2), avec l'API `ImageValidatingPolicy`**. C'est la seule
option qui couvre à la fois la vérification de signature et d'attestation et les règles générales, avec une API qui
existera encore lors de la soutenance. L'option 2 reste notre Plan B, sur la même installation.

Règles de conception :

1. **Deux validations obligatoires dans la politique d'images** :
   - *origine* : toute image doit venir de `registry.s7.internal/s7/`. Sans cette règle, une politique limitée aux
     images de notre registre laisserait passer sans vérification une image tirée d'un autre registre ;
   - *signature* : `verifyImageSignatures` doit réussir avec `security/cosign/cosign.pub`.
   En J4 s'ajoute l'attestation de provenance SLSA (`verifyAttestationSignatures`).
2. **Digest** : `mutateDigest: true` (le tag est remplacé par le digest vérifié), `verifyDigest: true`,
   `required: true`. On vérifie ce qui sera exécuté, pas un tag modifiable.
3. **Périmètre** : la politique s'applique au namespace `demo` (`namespaceSelector`). Par défaut, le chart exclut déjà
   `kube-system` (`config.webhooks.namespaceSelector`) et le namespace de Kyverno (`excludeKyvernoNamespace: true`).
4. **Déploiement progressif** : `validationActions: [Audit]` le temps d'observer les résultats, puis `[Deny]`.
5. **Échec fermé** : `failurePolicy: Fail`. Si Kyverno ou le registre est injoignable, la création de pods dans
   `demo` est refusée. Nous préférons l'indisponibilité à l'admission d'une image non vérifiée ; le périmètre limité
   à `demo` évite de bloquer les composants système.
6. **Disponibilité** : 1 réplique du contrôleur d'admission en J2-J3 (valeur par défaut du chart, RAM limitée). La
   documentation demande au moins 2 répliques pour la haute disponibilité : l'effet de 2 répliques sera mesuré en J4
   (mesure M3). Une procédure de secours est écrite (voir Plan B).
7. **Délai** : `webhookConfiguration.timeoutSeconds: 15` (la vérification interroge le registre) ; la latence
   d'admission sera mesurée (M2).
8. **Confiance TLS** : le certificat de la CA privée est fourni au contrôleur d'admission par la valeur Helm
   `admissionController.caCertificates.data` (chart 3.9.2). `credentials.allowInsecureRegistry` n'est utilisé qu'en
   diagnostic, jamais dans la version rendue.
9. **Politiques comme du code** : versionnées dans `security/kyverno/`, relues en PR par l'étudiant B, testées par un
   script qui applique des pods de test et vérifie qu'ils sont admis ou refusés (voir S4), indépendamment de la
   prise en charge par la CLI Kyverno.
10. **Version figée** dans `versions.yaml` ; pas de passage en 1.20 pendant le projet sans nouvel ADR (vérification
    de la compatibilité avec Kubernetes 1.35 et de l'API).

## Conséquences

- **Ce que l'on gagne** : un contrôle d'admission indépendant de la CI, qui vérifie l'origine, la signature et plus
  tard la provenance ; une API qui ne sera pas retirée avant la soutenance.
- **Ce que l'on perd** : moins d'exemples disponibles qu'avec `ClusterPolicy` ; une dépendance forte à la
  disponibilité de Kyverno et du registre pour déployer dans `demo`.
- **Risques résiduels assumés** :
  - quand la 1.20 sortira, la 1.19 ne recevra plus de correctifs communautaires : nous restons sur une version figée
    et non corrigée pendant la fin du projet, ce qui est acceptable pour un laboratoire mais pas en production ;
  - le contrôle a lieu à l'admission seulement : il ne protège ni les pods déjà admis, ni les namespaces exclus, ni
    contre un administrateur du cluster qui supprimerait le webhook ;
  - les conteneurs d'initialisation et éphémères doivent être couverts par la politique : à vérifier dans S4.
- **Ce qu'il faudra surveiller** : la compatibilité entre les signatures produites par Cosign 3 (spike S3) et la
  vérification de Kyverno 1.19 ; la latence d'admission ; les journaux du contrôleur d'admission.

## Plan B

| Signal observable | Action | Coût |
| --- | --- | --- |
| L'API `ImageValidatingPolicy` ne vérifie pas nos signatures ou attestations (refus inexpliqué, fonction CEL en erreur) après une séance sur le chemin critique | basculer sur `ClusterPolicy` + `verifyImages` avec la même installation 1.19.2, qui la prend encore complètement en charge (brouillon prêt dans `security/kyverno/s4/`) | API dépréciée, à justifier dans le rapport |
| Kyverno ne sait vérifier aucune signature produite par Cosign 3 | essayer `cosignOCI11` (ancienne API) ou faire signer par Cosign 2.6.x (Plan B de l'ADR-003) ; en dernier recours, Sigstore policy-controller | un outil de plus, règles générales séparées |
| Kyverno bloque le cluster (webhook injoignable, politique erronée) | procédure de secours : supprimer les configurations de webhook dont le nom commence par `kyverno-` (Kyverno les recrée à son redémarrage ; comportement vérifié dans S4), puis corriger la politique en mode Audit | quelques minutes sans contrôle d'admission, à consigner au journal |

## Questions que pourrait poser le jury

- *Pourquoi l'API CEL plutôt que `ClusterPolicy`, qui est mieux documentée ?* Parce que `ClusterPolicy` est dépréciée
  dans la version même que nous installons, et que son retrait est annoncé.
- *Que se passe-t-il si Kyverno est arrêté ?* Avec `failurePolicy: Fail`, aucun pod ne peut être créé dans `demo` ;
  les autres namespaces ne sont pas concernés.
- *Pourquoi une règle d'origine en plus de la signature ?* Une vérification limitée aux images de notre registre ne
  dit rien des images venant d'ailleurs.
- *Que ne protège pas le contrôle d'admission ?* Les pods déjà en cours d'exécution, les namespaces exclus, un
  administrateur qui désactive le webhook, une CVE découverte après le déploiement.
- *Pourquoi commencer en Audit ?* Pour voir ce que la politique refuserait avant qu'elle ne bloque réellement.
