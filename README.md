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

Le sketch reste dans son fichier Processing principal. Les deux JSON sont versionnés : les sauvegardes réalisées dans l’interface peuvent donc apparaître dans `git diff`.

## Réorganiser les scènes

Sélectionner une scène, puis utiliser **MONTER** ou **DESCENDRE** pour la déplacer d’une position. La sélection suit la scène, y compris lors d’un changement de page. L’ordre est sauvegardé automatiquement dans `scenes.json` et conservé au redémarrage. Aux extrémités de la liste, le déplacement impossible est sans effet. La scène en cours de lecture reste la même.

## Séquenceur et effets

Activer **SEQ RUN** sur une tranche pour faire défiler ses pas, puis choisir **STR**, **PUL** ou **FEU** dans le menu d’effets. **MAN** laisse les pas jouer sans modulation supplémentaire. Le BPM règle le défilement ; FREQ et MIN règlent l’effet indépendamment. Changer d’effet ne coupe pas le séquenceur et ne le redémarre pas.

Pendant la séquence, l’intensité et la couleur proviennent du pas courant. L’effet module cette intensité : un pas à zéro reste éteint. Désactiver SEQ RUN restitue l’intensité manuelle et la couleur de base, en conservant l’effet choisi. REC mémorise la combinaison dans la scène.

Les anciennes scènes avec `fx: 4` sont converties au chargement en mode sans effet (`fx: 0`), en conservant leur état de séquenceur `sa` et leurs pas.

## Interrupteurs et clonage des tranches

Les interrupteurs **RGB** et **SEQ** sont des capsules : curseur rond à gauche et couleur assombrie pour **OFF**, curseur à droite et couleur vive pour **ON**. Le texte indique également l’état.

Cliquer sur **CLONER** sous la tranche source, puis sur **COLLER ICI** sous la destination. **ANNULER** sous la source abandonne la copie. Le collage remplace le niveau manuel, le mode mono/RGB, la couleur, les effets, le tempo et tous les pas par les réglages capturés au clic sur CLONER. Les pas restent indépendants ; un séquenceur actif repart au premier pas. Le nom et les affectations de sorties de la destination sont conservés.

La copie et le collage attendent la fin d’une transition de scène. Le collage agit immédiatement sur la tranche ; utiliser **REC** pour conserver le résultat dans une scène. Aucune scène n’est enregistrée automatiquement par le clonage.

## Documentation détaillée

- [Architecture et repères dans le code](docs/ARCHITECTURE.md)
- [Données persistantes](docs/DONNEES.md)
- [Communication et matériel](docs/PROTOCOLE_SERIE.md)
- [Contribuer et utiliser Git](CONTRIBUTING.md)

Aucune licence de redistribution n’est définie dans ce dépôt ; son choix reste à préciser par le propriétaire.
