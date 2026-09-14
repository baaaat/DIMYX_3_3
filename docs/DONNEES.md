# Données persistantes

Les fichiers [`channelConfig.json`](../channelConfig.json) et [`scenes.json`](../scenes.json) sont lus et écrits par le sketch. Ils sont conservés et versionnés tels que reçus.

## Configuration des tranches

`channelConfig.json` contient un objet avec une liste `channels`. L’ordre correspond aux indices des tranches, de 0 à 9.

Le fichier peut aussi contenir `boards`, une liste d’alias humains associés aux identifiants matériels :

```json
"boards": [
  {"id": "ESP_A", "name": "Gradateur scène"}
]
```

Pour une carte USB, l’identifiant `id` est le `BOARD_ID` annoncé par le contrôleur. Le port `COMx` associé est détecté à l’exécution et n’est pas enregistré dans ce fichier.

| Clé | Sens |
| --- | --- |
| `name` | Nom affiché |
| `pm` | Sortie mono |
| `pr`, `pg`, `pb` | Sorties rouge, verte et bleue |
| `board` | Carte de sortie : `USB` ou identifiant ESP32 |
| `rgb` | Activation du mode RGB de la tranche |

Le callback `pin` accepte les sorties de 0 à 15 pour USB et jusqu’à 48 pour une carte ESP32. La configuration initiale réutilise plusieurs fois les mêmes sorties : elle ne décrit pas une affectation distincte pour chaque tranche. La correspondance avec le câblage dépend du contrôleur.

Les noms, sorties et mode RGB sont sauvegardés lors de leurs modifications. Ils sont valides pour toutes les scènes. En cas d’échec du chargement de configuration, le code tente de récupérer d’anciens champs dans la première scène, puis écrit une configuration.

## Scènes

`scenes.json` est une liste d’objets contenant `name` et `states`. Chaque scène attend 10 états, dans l’ordre des tranches.

| Clé d’un état | Sens |
| --- | --- |
| `m` | Valeur manuelle, échelle 0–4095 |
| `fx` | Effet : 0 sans modulation, 1 strobe, 2 feu, 3 pulsation ; ancien 4 converti en 0 au chargement |
| `f` | Paramètre de fréquence de l’effet |
| `min` | Minimum de l’effet, échelle 0–4095 |
| `cr`, `cg`, `cb` | Couleur de base, composantes 0–255 |
| `sa` | Activation du séquenceur, indépendante de `fx` |
| `bpm` | Tempo du séquenceur, minimum 20 |
| `steps` | Liste de pas : `i` (intensité 0–4095), `r`, `g`, `b` (0–255) |

Ces échelles décrivent l’usage du code ; elles ne constituent pas un schéma de validation automatique des fichiers. L’interface prévoit au maximum 10 pas, mais le chargeur parcourt tous les pas présents dans le JSON.

La création, l’enregistrement, le déplacement et la suppression d’une scène réécrivent la liste des scènes. L’ordre des objets dans le tableau JSON est l’ordre d’affichage. Les modifications de tranches doivent être capturées dans une scène pour y être conservées, sauf le nom, les sorties et le mode RGB qui appartiennent à la configuration des tranches. La durée de transition, le port série et la sélection courante ne sont pas enregistrés dans ces formats.

Il n’existe pas de champ de version de format. `loadScenes` intercepte globalement les erreurs et affiche « Aucun fichier », y compris pour certaines erreurs de contenu ; ce message ne prouve donc pas l’absence du fichier. Sauvegarder les données avant toute modification manuelle.
