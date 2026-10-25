# DIMYX Android — Représentation

Ce dossier contient le premier portage Android de la console DIMYX. Il est
indépendant du sketch Processing PC et ne modifie ni `DIMYX_3_3.pde`, ni les
fichiers de spectacle racine.

## Fonctionnalités

- affichage paysage de cinq tranches, pages 1–5 et 6–10 ;
- faders tactiles temporaires ;
- fader = multiplicateur de la source de scène ou du séquenceur ;
- liste et déclenchement des scènes ;
- transitions locales ;
- lecture des effets et séquenceurs ;
- BLACKOUT permanent ;
- chargement de `scenes.json`, `channelConfig.json` et `esp32Boards.json` par sélection de fichiers ;
- commandes UDP `H`, `P,<pin>,<valeur>` et `X` compatibles avec le firmware actuel.

L’état réseau distingue désormais trois cas :

- `WIFI : AUCUNE CARTE RESEAU` : les tranches sont encore affectées à `USB` ou
  `COMx` ;
- `WIFI : EN ATTENTE` : une cible réseau est configurée mais aucun heartbeat
  n’a été reçu ;
- `WIFI : CONNECTE` : un heartbeat `H` a été reçu d’une cible ESP32 depuis moins
  de 1,8 seconde.

## Compilation GitHub Actions

Le projet contient maintenant une configuration Gradle et le workflow
`.github/workflows/android.yml`. Chaque push sur `main` ou sur une branche
`feature/*`, ainsi que chaque pull request, compile un APK debug et le publie
comme artefact `dimyx-android-debug`.

La compilation utilise Java 17, Android Gradle Plugin 9.4.1 et Gradle 9.6.1. Le
projet local peut être ouvert dans Android Studio en sélectionnant le dossier
`android`.

## Utilisation des fichiers

Au premier lancement, l’application utilise un spectacle de démonstration
intégré uniquement pour vérifier l’interface. Le bouton de chargement permet de
sélectionner successivement `scenes.json`, `channelConfig.json`, puis
`esp32Boards.json` depuis la tablette. Les fichiers racine du projet ne sont
jamais réécrits.

La connexion réseau suppose le point d’accès ESP32 décrit dans
`../docs/ESP32_WIFI.md`. Pour une carte configurée dans `esp32Boards.json`,
l’application utilise son adresse et son port UDP. Les cartes `USB` sont
ignorées par Android et restent pilotées par la version PC.

## Interaction des niveaux

Le moteur conserve les niveaux, couleurs, effets et pas de la scène active.
Chaque fader Android ajoute une correction volatile de `0.0` à `1.0` :

```text
sortie = scène/séquenceur × correction tactile × effet
```

Le changement de scène remet toutes les corrections à `1.0`. BLACKOUT coupe
immédiatement les sorties et désactive localement la lecture active ; un rappel
de scène restaure ensuite les paramètres enregistrés.
