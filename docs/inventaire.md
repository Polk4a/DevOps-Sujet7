# Inventaire des machines et du réseau

Pilote : étudiant A. Cet inventaire est produit par un script, pour être rejouable et servir de base au rapport de
reproductibilité (J5). Il conditionne l'ADR-001 (virtualisation, dimensionnement), l'ADR-002 (accès à GitHub) et
l'ADR-003 (accès à Sigstore).

## Méthode

Sur **chaque** machine fournie, depuis la racine du dépôt :

```bash
sudo apt-get install -y cpu-checker      # pour kvm-ok (facultatif)
bash infra/inventaire.sh | tee -a docs/inventaire.md
```

Le script ne modifie rien. Il relève le matériel, la virtualisation, le réseau (IP, DNS, proxy, MTU, chevauchement des
plages prévues), teste l'accès sortant vers les services dont la chaîne dépend, puis déduit les conséquences pour les
ADR. Ces conséquences sont à relire : un code HTTP 403 peut venir d'un proxy du labo plutôt que du service visé.

## Synthèse et décisions

[A COMPLETER après exécution du script : 3 à 5 lignes. Virtualisation disponible ou non (ADR-001, option 1 ou Plan B) ; profil de VM retenu (architecture, section 4.2) ; GitHub et dépôt Helm de Kyverno joignables ou non ; miroirs nécessaires ; plage 192.168.100.0/24 libre ou à changer.]

## Relevés bruts

<!-- Les sections produites par infra/inventaire.sh sont ajoutées ci-dessous, une par machine. -->
