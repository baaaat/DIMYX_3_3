# Portage Android « Représentation »

Le portage Android se trouve dans [`../android`](../android). Il s’agit d’une
interface de représentation séparée du sketch Processing : le PC conserve ses
fonctions d’édition et l’Android ne propose que le chargement, le déclenchement
et le pilotage tactile.

## Architecture livrée

`MainActivity` dessine l’interface paysage et délègue les données à un moteur
local. Le moteur lit les mêmes clés que `scenes.json` et `channelConfig.json` :
niveaux `m`, couleurs `cr/cg/cb`, effets `fx/f/min`, séquenceurs `sa/bpm/steps`
et affectations `pm/pr/pg/pb/board`.

Le transport Android envoie les commandes UDP déjà utilisées par le firmware :
`H`, `P,<pin>,<valeur>` et `X`. Les canaux `USB` ne sont pas envoyés par la
tablette et restent du ressort de la console PC. `esp32Boards.json` peut être
chargé après la configuration des tranches afin d’associer chaque identifiant à
son hôte et son port. Une carte réseau non décrite est provisoirement supposée
à `192.168.4.1:4210`, ce qui correspond au point d’accès ESP32 de la
configuration initiale.

## Règles de représentation

- Une scène déclenchée lance une transition locale de 600 ms.
- Les corrections tactiles sont des multiplicateurs volatils de 0 à 1.
- Une correction ne modifie jamais les données JSON.
- Un changement de scène remet toutes les corrections à 1.
- Le séquenceur et l’effet continuent leur programmation ; le fader agit
  seulement sur leur niveau de sortie.
- BLACKOUT envoie `X`, force la sortie locale à zéro et reste accessible dans
  toutes les vues.

L’état de connexion n’est pas déduit de la seule connexion de la tablette au
point d’accès. Android envoie périodiquement `H` et n’affiche `CONNECTE` qu’à
la réception d’une réponse `H` de l’ESP32. Une affectation `COMx` ou `USB` est
signalée comme non réseau et n’est pas envoyée par Android.

## Limites connues

La configuration Gradle et le workflow GitHub Actions sont présents. La
compilation locale n’a pas été exécutée car aucun SDK Android, Gradle ou `adb`
n’est installé dans cet environnement. La détection UDP automatique, la
sélection tactile d’une configuration matérielle et la validation de
perte/reconnexion sur quatre cartes restent à tester sur tablette et ESP32
réels.
