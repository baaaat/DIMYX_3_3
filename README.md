# DIMYX 3.3 — Console Théâtre

Console d’éclairage écrite en Processing (mode Java), avec interface ControlP5 et communication série. Le sketch gère 10 tranches mono ou RGB, des scènes avec transitions, des effets et des séquenceurs de 10 pas maximum.

## Démarrage

1. Disposer de Processing en mode Java, de la bibliothèque **ControlP5** et de `processing.serial`.
2. Conserver le nom du dossier `DIMYX_3_3` et ouvrir `DIMYX_3_3.pde` dans Processing.
3. Conserver `channelConfig.json` et `scenes.json` à côté du sketch.
4. Lancer le sketch. La fenêtre mesure 1600 × 1000 pixels.
5. Pour les sorties physiques, connecter un contrôleur compatible avec le [protocole série](docs/PROTOCOLE_SERIE.md). En cas d’échec de la détection, l’interface affiche un sélecteur de port.

Les versions de Processing et ControlP5 utilisées à l’origine ne sont pas renseignées. Le firmware et la référence du matériel ne sont pas fournis. Le lancement et la compatibilité matérielle restent à valider sur l’installation cible.

## Organisation

```text
DIMYX_3_3/
├── DIMYX_3_3.pde          # Sketch et interface existants
├── channelConfig.json    # Noms et affectations des sorties
├── scenes.json           # Scènes enregistrées
├── README.md             # Présentation et démarrage
├── CONTRIBUTING.md       # Travail avec Git et validation
├── AGENTS.md             # Consignes de maintenance automatisée
├── .gitignore            # Exclusions des fichiers générés
├── .gitattributes        # Politique de fins de ligne
└── docs/
    ├── ARCHITECTURE.md    # Cartographie du sketch
    ├── DONNEES.md         # Formats JSON et sauvegardes
    └── PROTOCOLE_SERIE.md # Contrat observé côté Processing
```

Le sketch est conservé intégralement. La séparation entre application et documentation facilite la maintenance sans changer l’exécution. Les deux JSON sont versionnés : les sauvegardes réalisées dans l’interface peuvent donc apparaître dans `git diff`.

## Documentation

- [Architecture et repères dans le code](docs/ARCHITECTURE.md)
- [Données persistantes](docs/DONNEES.md)
- [Communication et matériel](docs/PROTOCOLE_SERIE.md)
- [Contribuer et utiliser Git](CONTRIBUTING.md)

Aucune licence de redistribution n’est définie dans ce dépôt ; son choix reste à préciser par le propriétaire.
