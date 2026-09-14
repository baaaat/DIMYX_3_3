# ESP32 WiFi

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

Les sorties d’une tranche affectée à `USB` utilisent le contrôleur série ; les autres utilisent la carte ESP32 correspondant à leur identifiant. Une cible dont l’hôte ne peut pas être résolu est ignorée sans masquer les autres cibles valides. La découverte active sur le réseau n’est pas réalisée, car le protocole de découverte du firmware n’est pas fourni.
