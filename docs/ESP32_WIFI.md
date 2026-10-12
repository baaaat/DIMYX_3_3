# ESP32 Wi-Fi autonome

Le firmware fourni dans [`firmware/esp32-c3/dimyx_esp32_c3.ino`](../firmware/esp32-c3/dimyx_esp32_c3.ino) configure l'ESP32-C3 en point d'accès (`DIMYX-ESP32-C3`). La console Processing se connecte directement à ce réseau ; aucun routeur n'est nécessaire. L'adresse par défaut est `192.168.4.1` et le port UDP `4210`.

DIMYX charge les cibles ESP32 valides depuis `esp32Boards.json` au démarrage. Elles apparaissent automatiquement dans la liste **CARTE** de la vue **SORTIES** ; l’affectation à chaque tranche reste manuelle et est enregistrée dans `channelConfig.json`.

Exemple :

```json
{
  "boards": [
    {"id":"ESP1","host":"192.168.1.201","port":4210,"enabled":true},
    {"id":"ESP2","host":"192.168.1.202","port":4210,"enabled":true}
  ]
}
```

Le transport utilise UDP. Le contrat reprend les commandes texte du lien serie :

- `H\n` : heartbeat
- `P,<pin>,<valeur>\n` : sortie 0..4095
- `X\n` : blackout

Les sorties d’une tranche affectée à `USB` utilisent le contrôleur série. Un identifiant reçu sous la forme `BOARD_ID:<identifiant>` sur un port USB peut aussi être choisi directement dans **CARTE** : les commandes sont alors envoyées au port associé, même si son nom `COMx` change. Les autres identifiants utilisent la carte ESP32 correspondant à leur entrée. Une cible dont l’hôte ne peut pas être résolu est ignorée sans masquer les autres cibles valides. La découverte active sur le réseau n’est pas réalisée, car le protocole de découverte du firmware n’est pas fourni.
## Réseau multi-cartes sans routeur

Une seule carte doit être configurée en `ROLE_ACCESS_POINT`. Elle crée le réseau `DIMYX-ESP32-C3` et accepte jusqu'à huit appareils, dont le PC. Toutes les autres cartes doivent être configurées en `ROLE_STATION` avec une adresse IP fixe distincte (`192.168.4.11`, `.12`, `.13`, etc.). Elles rejoignent alors le réseau du maître au lieu de créer leur propre réseau.

Dans `dimyx_esp32_c3.ino`, modifier avant chaque programmation :

```cpp
const DeviceRole DEVICE_ROLE = ROLE_ACCESS_POINT; // maître
// ou
const DeviceRole DEVICE_ROLE = ROLE_STATION;      // esclave
const IPAddress STATION_IP(192, 168, 4, 11);       // unique par carte
```

Le PC se connecte uniquement au réseau du maître. Dans `esp32Boards.json`, chaque carte est ensuite déclarée avec son adresse IP et l'identifiant annoncé par `BOARD_ID` (`ESP32-C3-MASTER` ou `ESP32-C3-NODE`).

## Mise en service

1. Programmer l'ESP32-C3 avec le sketch du dossier `firmware/esp32-c3`.
2. Connecter l'ordinateur au réseau Wi-Fi créé par l'ESP32-C3.
3. Ajouter dans `esp32Boards.json` la carte réellement programmée, avec `host: "192.168.4.1"`, `port: 4210` et l'identifiant annoncé par `BOARD_ID`.
4. Dans **SORTIES**, affecter cette carte aux tranches et régler les GPIO selon le câblage.

Le firmware coupe les sorties après deux secondes sans heartbeat. Cette sécurité ne remplace pas une protection électrique adaptée. La découverte active n'est pas réalisée et aucune configuration de démonstration n'est ajoutée automatiquement.
