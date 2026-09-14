# Communication série

Ce document décrit ce que fait le sketch Processing. Le firmware du contrôleur et le schéma de câblage ne sont pas présents dans le dépôt.

## Commandes observées

La connexion utilise **115200 bauds**. Les messages envoyés sont textuels et terminés par un saut de ligne `\n`.

| Direction | Message | Usage côté Processing |
| --- | --- | --- |
| Console → contrôleur | `H\n` | Demande de heartbeat |
| Console → contrôleur | `P,<sortie>,<valeur>\n` | Valeur de sortie, échelle 0–4095 |
| Console → contrôleur | `X\n` | Blackout demandé par l’utilisateur |
| Contrôleur → console | Texte contenant `THEATRE_CONSOLE` | Identification au démarrage |
| Contrôleur → console | `BOARD_ID:<identifiant>` (ou `BOARD_ID=<identifiant>`) | Association de l’identifiant matériel avec le port USB |
| Contrôleur → console | Réponse se terminant par `H` après suppression des espaces | Reconnaissance du heartbeat |

En fonctionnement, les réponses sont lues jusqu’au saut de ligne. Exemple d’envoi : `P,3,2048\n`. Les sorties réglables dans l’interface vont de 0 à 15 ; leur nature physique dépend du firmware.

## Temporisations

| Paramètre | Valeur |
| --- | ---: |
| Intervalle minimal entre mises à jour des sorties | 33 ms |
| Heartbeat | 500 ms |
| Expiration après dernière réponse, watchdog armé | 1500 ms |
| Tentative de reconnexion au dernier port | 2000 ms |
| Nouveau scan sans port connu | 5000 ms |

La détection ouvre les ports successivement, attend 1800 ms, lit le message de démarrage, envoie `H`, puis attend 300 ms. Elle mémorise chaque `BOARD_ID` reçu avec le port USB correspondant ; le premier contrôleur reconnu devient la connexion principale. Cette recherche est bloquante. Les valeurs de temporisation sont des seuils contrôlés dans la boucle, pas des garanties de temps réel.

## Perte et reprise

Le watchdog s’arme après réception d’un heartbeat reconnu. Lors d’une perte traitée par `handleConnectionLoss`, le sketch mémorise la scène active, remet les tranches à zéro localement, invalide le cache des sorties et ferme le port. Il essaie ensuite de se reconnecter au dernier port et de rappeler la scène mémorisée.

Le blackout local sur perte de connexion n’envoie pas `X` : l’extinction physique en l’absence de liaison dépend du firmware. Sa présence et son comportement restent à vérifier sur le matériel. Le bouton de blackout, lui, envoie `X` lorsque la liaison est disponible.

À compléter lors d’une validation matérielle : modèle du contrôleur, firmware et version, affectation des sorties, comportement en perte USB et versions de Processing/ControlP5 testées.
