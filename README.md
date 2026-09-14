# DIMYX 3.3 — Console Théâtre

Console d’éclairage écrite en Processing (mode Java), avec interface ControlP5 et communication série. Le sketch gère 10 tranches mono ou RGB, des scènes avec transitions, des effets et des séquenceurs de 10 pas maximum.

## Démarrage

1. Disposer de Processing en mode Java, de la bibliothèque **ControlP5** et de `processing.serial`.
2. Conserver le nom du dossier `DIMYX_3_3` et ouvrir `DIMYX_3_3.pde` dans Processing.
3. Conserver `channelConfig.json` et `scenes.json` à côté du sketch.
4. Lancer le sketch. La fenêtre est redimensionnable et sa taille initiale tient compte de l’écran, jusqu’à 1600 × 1000 pixels.
5. Pour les sorties physiques, connecter un contrôleur compatible avec le [protocole série](docs/PROTOCOLE_SERIE.md). Le choix du port USB se trouve dans **SORTIES / USB**. Les cartes ESP32 valides sont chargées depuis `esp32Boards.json` et peuvent être affectées manuellement à chaque tranche dans **SORTIES**.

Les versions de Processing et ControlP5 utilisées à l’origine ne sont pas renseignées. Le firmware et la référence du matériel ne sont pas fournis. Le lancement et la compatibilité matérielle restent à valider sur l’installation cible.

La compilation et les tests d’interface ont été exécutés avec les installations locales **Processing 4.5.5** et **ControlP5 2.2.6**. Ils ne remplacent pas la validation sur le contrôleur physique.

## Organisation

```text
DIMYX_3_3/
├── DIMYX_3_3.pde          # Sketch et interface existants
├── channelConfig.json    # Noms et affectations des sorties
├── scenes.json           # Scènes enregistrées
├── README.md             # Présentation et démarrage
├── CONTRIBUTING.md       # Travail avec Git et validation
├── AGENTS.md             # Consignes de maintenance automatisée
├── TODO.md               # Suivi des travaux et validations
├── tests/                # Compilation et essais d’interface sans matériel
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

Activer **SEQ** sur une tranche pour faire défiler ses pas, puis ouvrir **FX** et choisir **STR**, **PUL** ou **FEU**. **MAN** laisse les pas jouer sans modulation supplémentaire. Le menu remplace temporairement les commandes RGB/SEQ/FREQ/MIN de cette tranche ; choisir un effet ou cliquer en dehors le referme. Le BPM règle le défilement ; FREQ et MIN règlent l’effet indépendamment. Ouvrir le menu ne change pas l’effet, et choisir un effet ne coupe pas le séquenceur ni ne le redémarre.

Pendant la séquence, l’intensité et la couleur proviennent du pas courant. L’effet module cette intensité : un pas à zéro reste éteint. Désactiver SEQ restitue l’intensité manuelle et la couleur de base, en conservant l’effet choisi. REC mémorise la combinaison dans la scène.

Les anciennes scènes avec `fx: 4` sont converties au chargement en mode sans effet (`fx: 0`), en conservant leur état de séquenceur `sa` et leurs pas.

## Interrupteurs et clonage des tranches

Les interrupteurs **RGB** et **SEQ** sont des capsules : curseur rond à gauche et couleur assombrie pour **OFF**, curseur à droite et couleur vive pour **ON**. Le texte indique également l’état.

Cliquer sur **CLONER** sous la tranche source, puis sur **COLLER ICI** sous la destination. **ANNULER** sous la source abandonne la copie. Le collage remplace le niveau manuel, la couleur, les effets, le tempo et tous les pas par les réglages capturés au clic sur CLONER. Les pas restent indépendants ; un séquenceur actif repart au premier pas. Le mode mono/RGB, le nom et les affectations de sorties de la destination sont conservés.

La copie et le collage attendent la fin d’une transition de scène. Le collage agit immédiatement sur la tranche ; utiliser **REC** pour conserver le résultat dans une scène. Aucune scène n’est enregistrée automatiquement par le clonage.

## Interface et petits écrans

Boutons, scènes, champs de saisie et curseurs reprennent les formes arrondies des interrupteurs. Les couleurs distinguent les commandes ; les valeurs restent affichées dans les curseurs horizontaux et à côté des faders. Les pas ont des cibles de 22 × 22 pixels, séparées par des espaces sans action.

La disposition est vérifiée pour des surfaces utiles de **800 × 540**, **1024 × 600**, **1280 × 800**, **1366 × 768** et **1600 × 1000** pixels. La résolution disponible et la mise à l’échelle du système comptent davantage que la diagonale de l’écran. La fenêtre Java2D impose une taille minimale pour conserver ces commandes accessibles.

- Les flèches près du titre parcourent les pages de tranches. Le compteur indique les tranches visibles. Les dix tranches continuent de jouer, même lorsqu’elles sont masquées ; le clonage fonctionne entre pages.
- À partir de 1000 pixels de largeur utile, les scènes restent à droite. En dessous, **SCENES / TRANCHES** bascule entre les deux vues. Le nombre de scènes par page suit la hauteur disponible.
- **SORTIES / USB** affiche les affectations mono/RGB, la liste des cartes disponibles et les ports détectés. Sur une fenêtre étroite, **USB / SORTIES** bascule entre ces deux vues. Sélectionner une carte dans la liste de chaque tranche, puis valider les pins avec **Entrée** avant de revenir avec **CONSOLE**.
- **BLACKOUT** reste visible en haut à droite dans toutes les vues.

Le choix de page et de vue n’est pas enregistré dans les JSON. Les [tests d’interface](CONTRIBUTING.md#tests-dinterface) permettent de vérifier la disposition et les interactions sans ouvrir de port physique.

## Documentation détaillée

- [Architecture et repères dans le code](docs/ARCHITECTURE.md)
- [Données persistantes](docs/DONNEES.md)
- [Communication et matériel](docs/PROTOCOLE_SERIE.md)
- [Contribuer et utiliser Git](CONTRIBUTING.md)

Aucune licence de redistribution n’est définie dans ce dépôt ; son choix reste à préciser par le propriétaire.
## BLIND, SORTIES et sequenceur mono

Le bouton **SORTIES** ouvre la configuration materielle. Le selecteur **RGB** est visible uniquement dans cette vue et n'apparait plus dans la console.

Le mode **BLIND** permet de programmer niveaux, couleurs, effets, sequenceurs et scenes sans envoyer les commandes de niveau au materiel. Le heartbeat USB reste actif. En quittant BLIND, l'etat programme est renvoye vers les sorties. **BLACKOUT** reste prioritaire et continue d'agir sur le materiel pendant BLIND.

Le sequenceur pilote aussi une tranche mono : dans ce cas, seule l'intensite du pas courant est utilisee. Sur une tranche RGB, le pas fournit aussi sa couleur.

Le bouton **FX** est cyclique : MAN -> STR -> FEU -> PUL -> MAN.
